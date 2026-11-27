import AppKit

/// 常驻悬浮窗：一小块卡片贴在屏幕角落，随时能看内存 / 温度 / 功耗，
/// 不用点菜单栏也不用展开控制中心。拖动可换位置，双击开主窗口，右键有菜单。
final class HUDController: NSObject {
    static let shared = HUDController()

    private var panel: NSPanel?
    private var widget: StatusWidgetView?
    private var timer: Timer?

    var isVisible: Bool { panel?.isVisible == true }

    /// 启动时按设置决定要不要显示
    func start() {
        if Settings.shared.hud { show() } else { hide() }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        widget = nil
    }

    func show() {
        if panel != nil { return }
        build()
        panel?.orderFrontRegardless()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.render() }
        timer = t
        RunLoop.main.add(t, forMode: .common)
        render()
    }

    /// 指标组合变了：重建行、跟着改窗口大小（保持右上角位置不动）
    func reload() {
        guard let panel = panel, let widget = widget else { return }
        let top = panel.frame.maxY
        widget.setMetrics(Settings.shared.menuRows.components(separatedBy: ","))
        let size = widget.frame.size
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height,
                              width: size.width, height: size.height), display: true)
        render()
    }

    private func render() {
        widget?.render(Metrics.shared.latest)
    }

    private func build() {
        let w = StatusWidgetView()
        w.setMetrics(Settings.shared.menuRows.components(separatedBy: ","))
        widget = w

        let container = HUDContainer(frame: w.frame)
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        container.onDoubleClick = { Toolbox.openModule(nil) }
        container.menu = buildMenu()
        container.addSubview(w)

        // 右上角一个小叉，不想看的时候一点就收
        let close = NSButton(frame: NSRect(x: w.frame.width - 26, y: w.frame.height - 26, width: 18, height: 18))
        close.isBordered = false
        close.imagePosition = .imageOnly
        close.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "隐藏")
        close.contentTintColor = .tertiaryLabelColor
        close.target = self
        close.action = #selector(onClose)
        close.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(close)

        let p = NSPanel(contentRect: w.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = container
        p.setFrameAutosaveName("ToolboxHUDFrame")
        if p.frame.origin == .zero { placeTopRight(p) }
        panel = p
    }

    private func placeTopRight(_ p: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: v.maxX - p.frame.width - 16, y: v.maxY - p.frame.height - 12))
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        let open = NSMenuItem(title: "打开主窗口", action: #selector(onOpen), keyEquivalent: "")
        open.target = self
        m.addItem(open)
        let set = NSMenuItem(title: "调整显示哪些数据…", action: #selector(onSettings), keyEquivalent: "")
        set.target = self
        m.addItem(set)
        m.addItem(.separator())
        let hide = NSMenuItem(title: "收起来", action: #selector(onClose), keyEquivalent: "")
        hide.target = self
        m.addItem(hide)
        return m
    }

    @objc private func onClose() {
        Settings.shared.set("hud", false)
        hide()
        NotificationCenter.default.post(name: .hudChanged, object: nil)
    }

    @objc private func onOpen() {
        Toolbox.openModule(nil)
    }

    @objc private func onSettings() {
        Toolbox.openModule("settings")
    }
}

/// 悬浮窗底板：双击开主窗口，右键出菜单，空白处可拖动整块
final class HUDContainer: NSVisualEffectView {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }
}

extension Notification.Name {
    /// 悬浮窗显示状态变了（设置页的开关要同步）
    static let hudChanged = Notification.Name("hudChanged")
}
