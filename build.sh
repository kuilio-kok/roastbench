#!/bin/zsh
# 把 Swift 源码打包成 Mac工具箱.app（universal: arm64 + x86_64）
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"
NAME="Mac 工具箱"          # 用户可见名称（Dock / 菜单 / 关于）
EXEC="Mac工具箱"           # 可执行文件与 app 包名（避免路径空格问题）
BUNDLE="$ROOT/$EXEC.app"

rm -rf "$BUNDLE" build
mkdir -p build "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/ui"

echo "▶ 编译 arm64"
swiftc -O -target arm64-apple-macos14.0 \
  -o build/app_arm64 src/main.swift src/Icon.swift src/StatusBar.swift src/Inspect.swift

echo "▶ 编译 x86_64"
swiftc -O -target x86_64-apple-macos14.0 \
  -o build/app_x86_64 src/main.swift src/Icon.swift src/StatusBar.swift src/Inspect.swift

echo "▶ 合并通用二进制"
lipo -create -output "$BUNDLE/Contents/MacOS/$EXEC" build/app_arm64 build/app_x86_64
chmod +x "$BUNDLE/Contents/MacOS/$EXEC"

echo "▶ 生成图标（浅色 / 深色两套）"
swiftc -O -o build/icongen src/Icon.swift src/icongen/main.swift
rm -rf build/AppIcon.iconset build/AppIconDark.iconset
./build/icongen build/AppIcon.iconset light >/dev/null
./build/icongen build/AppIconDark.iconset dark >/dev/null
iconutil -c icns build/AppIcon.iconset     -o "$BUNDLE/Contents/Resources/AppIcon.icns"
iconutil -c icns build/AppIconDark.iconset -o "$BUNDLE/Contents/Resources/AppIconDark.icns"

echo "▶ 拷贝资源"
cp src/ui/index.html src/ui/style.css src/ui/app.js "$BUNDLE/Contents/Resources/ui/"

# 内嵌 macmon（Apple Silicon 数据源，省掉 Homebrew）
if [ -f /tmp/mmdl/macmon ]; then
  cp /tmp/mmdl/macmon "$BUNDLE/Contents/Resources/macmon"
  chmod +x "$BUNDLE/Contents/Resources/macmon"
else
  echo "⚠️  没找到 /tmp/mmdl/macmon，手动下载："
  echo "   curl -L https://github.com/vladkens/macmon/releases/download/v0.10.0/macmon-v0.10.0.tar.gz | tar xz"
fi

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>$NAME</string>
    <key>CFBundleDisplayName</key>        <string>$NAME</string>
    <key>CFBundleIdentifier</key>         <string>cn.wangchuanhe.roastbench</string>
    <key>CFBundleExecutable</key>         <string>$EXEC</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>3.1</string>
    <key>CFBundleVersion</key>            <string>31</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSSupportsAutomaticTermination</key> <true/>
    <key>NSRequiresAquaSystemAppearance</key> <false/>
    <key>LSApplicationCategoryType</key>  <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

xattr -dr com.apple.quarantine "$BUNDLE" 2>/dev/null || true
echo "✅ 完成：$BUNDLE"
du -sh "$BUNDLE"
