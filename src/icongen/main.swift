import AppKit
import Foundation

// 生成 AppIcon.iconset：用 AppDelegate 里同一份画法渲染多尺寸 PNG
let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes {
    let img = IconFactory.make(size: CGFloat(s))
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: outDir).appendingPathComponent("icon_\(s)x\(s).png")
        try? png.write(to: url)
    }
}

// 标准命名
let map: [Int: [String]] = [
    16: ["icon_16x16.png"],
    32: ["icon_16x16@2x.png", "icon_32x32.png"],
    64: ["icon_32x32@2x.png"],
    128: ["icon_128x128.png"],
    256: ["icon_128x128@2x.png", "icon_256x256.png"],
    512: ["icon_256x256@2x.png", "icon_512x512.png"],
    1024: ["icon_512x512@2x.png"],
]
let fm = FileManager.default
for (src, names) in map {
    for name in names {
        let from = URL(fileURLWithPath: outDir).appendingPathComponent("icon_\(src)x\(src).png")
        let to = URL(fileURLWithPath: outDir).appendingPathComponent(name)
        if fm.fileExists(atPath: from.path) {
            try? fm.removeItem(at: to)
            try? fm.copyItem(at: from, to: to)
        }
    }
}
print("iconset ready:", outDir)
