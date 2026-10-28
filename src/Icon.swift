import AppKit

// 简约石墨底 + 四根上升的暖色圆角柱（温度等级的抽象），不画卡通火焰
enum IconFactory {
    static func make(size: CGFloat = 256) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let k = size / 256
        let rect = NSRect(x: 0, y: 0, width: size, height: size)

        let bg = NSBezierPath(roundedRect: rect.insetBy(dx: 6 * k, dy: 6 * k), xRadius: 56 * k, yRadius: 56 * k)
        let grad = NSGradient(colors: [
            NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.17, alpha: 1),
            NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.09, alpha: 1),
        ], atLocations: [0, 1], colorSpace: .deviceRGB)!
        grad.draw(in: bg, angle: -90)

        // 顶部一道很淡的高光，像 iOS 图标的玻璃感
        let gloss = NSBezierPath(roundedRect: NSRect(x: 20 * k, y: 176 * k, width: 216 * k, height: 60 * k),
                                 xRadius: 30 * k, yRadius: 30 * k)
        NSColor(calibratedWhite: 1, alpha: 0.045).setFill()
        gloss.fill()

        // 四根圆角柱，逐级升高、颜色由暖金到橙红
        let cols: [(NSColor, CGFloat)] = [
            (NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.42, alpha: 1), 52),
            (NSColor(calibratedRed: 1.00, green: 0.66, blue: 0.30, alpha: 1), 88),
            (NSColor(calibratedRed: 1.00, green: 0.50, blue: 0.22, alpha: 1), 124),
            (NSColor(calibratedRed: 1.00, green: 0.35, blue: 0.20, alpha: 1), 160),
        ]
        let barW: CGFloat = 26
        let gap: CGFloat = 14
        let totalW = barW * 4 + gap * 3
        let x0 = (size / k - totalW) / 2 * k
        for (i, item) in cols.enumerated() {
            let h = item.1 * k
            let x = x0 + CGFloat(i) * (barW + gap) * k
            let y = 52 * k
            let r = NSRect(x: x, y: y, width: barW * k, height: h)
            let path = NSBezierPath(roundedRect: r, xRadius: 13 * k, yRadius: 13 * k)
            item.0.setFill()
            path.fill()
        }

        img.unlockFocus()
        return img
    }
}
