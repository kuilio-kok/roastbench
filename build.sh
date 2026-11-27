#!/bin/zsh
# 把 Swift 源码打包成 Mac工具箱.app（universal: arm64 + x86_64）
# 内含 WidgetKit 扩展（控制中心控制项 + 通知中心小组件，需要 macOS 26+）
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"
NAME="Mac 工具箱"          # 用户可见名称（Dock / 菜单 / 关于）
EXEC="Mac工具箱"           # 可执行文件与 app 包名（避免路径空格问题）
BUNDLE="$ROOT/$EXEC.app"
APP_ID="cn.wangchuanhe.roastbench"
WIDGET_ID="$APP_ID.widget"
WIDGET_NAME="ToolboxWidget"
APPEX="$BUNDLE/Contents/PlugIns/$WIDGET_NAME.appex"
VERSION="3.3"
BUILD_NO="33"

rm -rf "$BUNDLE" build
mkdir -p build "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/ui" "$BUNDLE/Contents/PlugIns"
mkdir -p "$APPEX/Contents/MacOS"

APP_SRC=(src/main.swift src/Icon.swift src/StatusBar.swift src/Inspect.swift src/Cleaners.swift src/Maintenance.swift src/widget/Snapshot.swift)
# 扩展和主 App 共用 Snapshot.swift：宿主按同一份路径规则写快照，扩展读自己容器
WIDGET_SRC=(src/widget/MemProbe.swift src/widget/Snapshot.swift src/widget/Widgets.swift)

echo "▶ 编译主程序 arm64"
swiftc -O -target arm64-apple-macos14.0 -o build/app_arm64 $APP_SRC

echo "▶ 编译主程序 x86_64"
swiftc -O -target x86_64-apple-macos14.0 -o build/app_x86_64 $APP_SRC

echo "▶ 合并通用二进制"
lipo -create -output "$BUNDLE/Contents/MacOS/$EXEC" build/app_arm64 build/app_x86_64
chmod +x "$BUNDLE/Contents/MacOS/$EXEC"

echo "▶ 编译小组件扩展（ControlWidget 需要 macOS 26+）"
for ARCH in arm64 x86_64; do
  swiftc -O -parse-as-library -target $ARCH-apple-macos26.0 \
    -framework WidgetKit -framework SwiftUI -framework AppIntents -framework AppKit \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o build/widget_$ARCH $WIDGET_SRC
done
lipo -create -output "$APPEX/Contents/MacOS/$WIDGET_NAME" build/widget_arm64 build/widget_x86_64
chmod +x "$APPEX/Contents/MacOS/$WIDGET_NAME"

cat > "$APPEX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>$WIDGET_NAME</string>
    <key>CFBundleDisplayName</key>        <string>Mac 工具箱</string>
    <key>CFBundleIdentifier</key>         <string>$WIDGET_ID</string>
    <key>CFBundleExecutable</key>         <string>$WIDGET_NAME</string>
    <key>CFBundlePackageType</key>        <string>XPC!</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>            <string>$BUILD_NO</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleSupportedPlatforms</key> <array><string>MacOSX</string></array>
    <key>LSMinimumSystemVersion</key>     <string>26.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key> <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

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
    <key>CFBundleIdentifier</key>         <string>$APP_ID</string>
    <key>CFBundleExecutable</key>         <string>$EXEC</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>            <string>$BUILD_NO</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSSupportsAutomaticTermination</key> <true/>
    <key>NSRequiresAquaSystemAppearance</key> <false/>
    <key>LSApplicationCategoryType</key>  <string>public.app-category.utilities</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>    <string>cn.wangchuanhe.roastbench.url</string>
            <key>CFBundleURLSchemes</key> <array><string>mactoolbox</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# 扩展必须在沙盒里跑（WidgetKit 只执行沙盒 appex），宿主不必沙盒
cat > build/widget.entitlements <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key> <true/>
</dict>
</plist>
ENT

echo "▶ 签名（由内向外）"
codesign --force --timestamp=none --sign - --entitlements build/widget.entitlements "$APPEX"
codesign --force --timestamp=none --sign - -i "$APP_ID" "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE" && echo "   签名校验通过"

xattr -dr com.apple.quarantine "$BUNDLE" 2>/dev/null || true

echo "▶ 注册到 LaunchServices / 插件库"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -f "$BUNDLE" 2>/dev/null || true
pluginkit -a "$APPEX" 2>/dev/null || true

echo "✅ 完成：$BUNDLE"
echo "   控制中心控制项需要 macOS 26+，第一次加完如果没出现，执行：killall chronod NotificationCenter"
du -sh "$BUNDLE"
