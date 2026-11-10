import AppKit

// 与界面侧栏同款的「四宫格 mark」：2×2 圆角方块，左上 .55 / 右上 .8 / 左下 .8 / 右下 1
// 浅色系统 → 浅底深 mark；深色系统 → 深底浅 mark。图形元素、圆角比例与 24×24 视图完全对应。
enum IconFactory {
    /// (x, y, w, h, alpha)，坐标系为界面 SVG 的 24×24（y 向下）
    private static let cells: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, a: CGFloat)] = [
        (3.5, 4.5, 7, 7, 0.55),
        (13.5, 4.5, 7, 7, 0.80),
        (3.5, 14.5, 7, 5, 0.80),
        (13.5, 14.5, 7, 5, 1.00),
    ]
    private static let markW: CGFloat = 17   // 3.5 → 20.5
    private static let markH: CGFloat = 15   // 4.5 → 19.5
    private static let rx: CGFloat = 2       // 界面 rx=2

    private static func color(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    static func make(size: CGFloat = 256, dark: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let canvas = NSRect(x: 0, y: 0, width: size, height: size)

        // 底板：macOS 标准圆角方
        let inset = size * 0.05
        let bg = NSBezierPath(roundedRect: canvas.insetBy(dx: inset, dy: inset),
                              xRadius: size * 0.222, yRadius: size * 0.222)
        let bgColors: [NSColor] = dark
            ? [color(0x3C3C43, alpha: 1), color(0x121215, alpha: 1)]
            : [color(0xFFFFFF, alpha: 1), color(0xDCE0E8, alpha: 1)]
        NSGradient(colors: bgColors, atLocations: [0, 1], colorSpace: .sRGB)!.draw(in: bg, angle: -90)

        // mark：按 24×24 视图等比放大到画布的 46%，整体居中
        let k = size * 0.50 / markW
        let ox = (size - markW * k) / 2
        let oy = (size - markH * k) / 2
        let markHex: UInt32 = dark ? 0x8CC0FF : 0x0B47C8
        for c in cells {
            let r = NSRect(x: ox + (c.x - 3.5) * k,
                           y: oy + (markH - (c.y - 4.5) - c.h) * k,   // y 翻转
                           width: c.w * k, height: c.h * k)
            let p = NSBezierPath(roundedRect: r, xRadius: rx * k, yRadius: rx * k)
            color(markHex, alpha: c.a).setFill()
            p.fill()
        }

        img.unlockFocus()
        return img
    }
}

// MARK: - Dock 图标随系统深浅外观实时切换

enum AppIconManager {
    private static var cache: [Bool: NSImage] = [:]
    private static var observer: NSKeyValueObservation?

    static func isDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// 两套图标只解码一次，之后复用内存里的 NSImage
    private static func image(dark: Bool) -> NSImage {
        if let hit = cache[dark] { return hit }
        let name = dark ? "AppIconDark" : "AppIcon"
        var img: NSImage? = nil
        if let url = Bundle.main.url(forResource: name, withExtension: "icns") {
            img = NSImage(contentsOf: url)
        }
        let fallback = img ?? IconFactory.make(size: 512, dark: dark)
        cache[dark] = fallback
        return fallback
    }

    static func apply() {
        NSApp.applicationIconImage = image(dark: isDark())
    }

    /// 只在 App 生命周期内注册一次；外观一变（含 App 内主题切换）立刻换图，不重启
    static func start() {
        guard observer == nil else { return }
        observer = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { _, _ in
            DispatchQueue.main.async { AppIconManager.apply() }
        }
    }
}
