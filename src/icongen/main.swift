import AppKit
import Foundation

// 生成 iconset：用与 AppDelegate 同一份 IconFactory 画法渲染多尺寸 PNG
// 用法: icongen <输出目录> [light|dark]
let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "AppIcon.iconset"
let dark = args.count > 2 && args[2] == "dark"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// iconset 要求的标准文件名 → 像素尺寸（逐个直接渲染，避免改名互相覆盖）
let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in outputs {
    let img = IconFactory.make(size: CGFloat(px), dark: dark)
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
        try? png.write(to: url)
    }
}
print("iconset ready:", outDir, dark ? "(dark)" : "(light)")
