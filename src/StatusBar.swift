import AppKit
import Foundation
import WidgetKit

/// 菜单栏常驻：标题指标与面板数据行都可自由组合，另带常用操作入口
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var item: NSStatusItem?
    private var timer: Timer?
    private var widget: StatusWidgetView?
    private var noSleepItem: NSMenuItem?
    private var hudItem: NSMenuItem?

    /// 可选指标：id 与设置里的白名单、小组件里的参数一一对应
    struct Metric {
        let id: String
        let name: String
    }
    static let catalog: [Metric] = [
        Metric(id: "mem", name: "内存占用"),
        Metric(id: "cpu", name: "CPU 占用"),
        Metric(id: "gpu", name: "GPU 占用"),
        Metric(id: "temp", name: "CPU 温度"),
        Metric(id: "power", name: "整机功耗"),
        Metric(id: "fan", name: "风扇转速"),
        Metric(id: "disk", name: "磁盘读写"),
        Metric(id: "batt", name: "电池电量"),
    ]

    func install() {
        guard item == nil else { return }
        guard Settings.shared.menuBar else { return }
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = it

        if let img = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: "Mac 工具箱") {
            img.isTemplate = true
            it.button?.image = img
            it.button?.imagePosition = .imageLeading
        }
        it.button?.title = " —"

        let menu = NSMenu()

        // —— 数据小组件面板（内容随设置里的组合变化）——
        let widget = StatusWidgetView()
        self.widget = widget
        let widgetItem = NSMenuItem()
        widgetItem.view = widget
        menu.addItem(widgetItem)
        menu.addItem(.separator())

        // —— 烤机 ——
        let start = NSMenuItem(title: "开始烤机", action: #selector(onStart), keyEquivalent: "")
        start.target = self
        menu.addItem(start)
        let stop = NSMenuItem(title: "停手", action: #selector(onStop), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)

        let modeItem = NSMenuItem(title: "压力模式", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let modes = [
            ("max", "极限双烤"), ("cpu", "CPU 单烤"), ("gpu", "GPU 单烤"),
            ("mem", "内存单烤"), ("io", "磁盘单烤"), ("pulse", "温度探底"),
            ("step", "阶梯升载"), ("thermo", "恒温模式"), ("passive", "凉拌模式"), ("battery", "电池降频"),
        ]
        for (id, name) in modes {
            let mi = NSMenuItem(title: name, action: #selector(onMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = id
            sub.addItem(mi)
        }
        modeItem.submenu = sub
        menu.addItem(modeItem)
        menu.addItem(.separator())

        // —— 维护：键盘清洁 / 屏幕清洁 / 合盖不休眠 ——
        let kb = NSMenuItem(title: "键盘清洁", action: #selector(onKeyboardClean), keyEquivalent: "")
        kb.target = self
        menu.addItem(kb)

        let sc = NSMenuItem(title: "屏幕清洁", action: #selector(onScreenClean), keyEquivalent: "")
        sc.target = self
        menu.addItem(sc)

        let noSleep = NSMenuItem(title: "合盖不休眠", action: #selector(onToggleNoSleep), keyEquivalent: "")
        noSleep.target = self
        noSleep.state = NoSleep.shared.isEnabled() ? .on : .off
        noSleepItem = noSleep
        menu.addItem(noSleep)

        let hud = NSMenuItem(title: "常驻悬浮窗", action: #selector(onToggleHUD), keyEquivalent: "")
        hud.target = self
        hud.state = Settings.shared.hud ? .on : .off
        hudItem = hud
        menu.addItem(hud)

        let cc = NSMenuItem(title: "添加到控制中心…", action: #selector(onOpenControlCenter), keyEquivalent: "")
        cc.target = self
        menu.addItem(cc)
        menu.addItem(.separator())

        let show = NSMenuItem(title: "显示主窗口", action: #selector(onShow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let quit = NSMenuItem(title: "退出 Mac 工具箱", action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        it.menu = menu

        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.refresh() }
        timer = t
        RunLoop.main.add(t, forMode: .common)
        refresh()
    }

    /// 设置改动后重建（指标组合、显示与否都可能变）
    func reload() {
        uninstall()
        install()
    }

    private func refresh() {
        widget?.setMetrics(Settings.shared.menuRows.components(separatedBy: ","))
        noSleepItem?.state = NoSleep.shared.isEnabled() ? .on : .off
        hudItem?.state = Settings.shared.hud ? .on : .off

        guard let s = Metrics.shared.latest else {
            item?.button?.title = " —"
            widget?.render(nil)
            return
        }
        let parts = Settings.shared.menuTitle.components(separatedBy: ",").compactMap { titleText($0, s) }
        item?.button?.title = " " + parts.joined(separator: " · ")
        NSApp.dockTile.badgeLabel = Burner.shared.running ? "\(Int(s.cpuTemp.rounded()))°" : nil
        widget?.render(s)
        WidgetSnapshot.write(s)
    }

    /// 菜单栏标题里的短字段
    private func titleText(_ id: String, _ s: Metrics.Sample) -> String? {
        switch id {
        case "temp":  return "\(Int(s.cpuTemp.rounded()))°"
        case "power": return "\(Int(s.allW.rounded()))W"
        case "mem":   return String(format: "%.0f%%", s.ramTotal > 0 ? s.ramUsed / s.ramTotal * 100 : 0)
        case "cpu":   return "CPU \(Int(s.cpuUsage.rounded()))%"
        case "gpu":   return "GPU \(Int(s.gpuUsage.rounded()))%"
        case "fan":   return "\(Int(s.fan.rounded()))"
        case "disk":
            let speed = DiskWatcher.shared.readMB + DiskWatcher.shared.writeMB
            return String(format: "%.0fM/s", speed)
        case "batt":  return "\(PowerWatcher.cached().1)%"
        default:      return nil
        }
    }

    /// 退出时撤掉菜单栏图标与定时器，避免残留与"僵尸"计时器
    func uninstall() {
        timer?.invalidate()
        timer = nil
        if let it = item { NSStatusBar.system.removeStatusItem(it) }
        item = nil
        widget = nil
        noSleepItem = nil
        hudItem = nil
    }

    @objc private func onStart() {
        NotificationCenter.default.post(name: .uiAction, object: "start")
    }
    @objc private func onStop() {
        NotificationCenter.default.post(name: .uiAction, object: "stop")
    }
    @objc private func onShow() {
        NotificationCenter.default.post(name: .uiAction, object: "show")
    }
    @objc private func onQuit() {
        Burner.shared.stop()
        CleanMode.shared.stop()
        NSApp.terminate(nil)
    }
    @objc private func onMode(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            NotificationCenter.default.post(name: .uiAction, object: "mode:" + id)
        }
    }

    @objc private func onKeyboardClean() {
        Toolbox.run(.keyboardClean)
    }

    @objc private func onScreenClean() {
        Toolbox.run(.screenClean)
    }

    @objc private func onToggleHUD() {
        Settings.shared.set("hud", !Settings.shared.hud)
    }

    @objc private func onOpenControlCenter() {
        Toolbox.openControlCenterSettings()
    }

    @objc private func onToggleNoSleep() {
        let target = !NoSleep.shared.isEnabled()
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = NoSleep.shared.set(target)
            DispatchQueue.main.async {
                self.refresh()
                if !ok {
                    let a = NSAlert()
                    a.messageText = "合盖不休眠未生效"
                    a.informativeText = "可能取消了管理员授权，或密码输入有误。"
                    a.addButton(withTitle: "知道了")
                    a.runModal()
                }
            }
        }
    }
}

extension Notification.Name {
    static let uiAction = Notification.Name("uiAction")
}

// MARK: - 菜单栏数据小组件面板

/// 简单的水平进度条
final class BarView: NSView {
    var ratio: CGFloat = 0 { didSet { needsDisplay = true } }
    var color: NSColor = .controlAccentColor { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r)
        NSColor.separatorColor.setFill()
        track.fill()
        let ratio = min(max(self.ratio, 0), 1)
        if ratio > 0 {
            let w = max(bounds.width * ratio, bounds.height)
            let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: r, yRadius: r)
            color.setFill()
            fill.fill()
        }
    }
}

/// 一行指标：名称 + 进度条 + 数值
private final class MetricRow: NSView {
    let id: String
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "—")
    private let bar = BarView()

    init(id: String, name: String) {
        self.id = id
        super.init(frame: NSRect(x: 0, y: 0, width: 272, height: 16))

        nameLabel.stringValue = name
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.widthAnchor.constraint(equalToConstant: 58).isActive = true

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 68).isActive = true

        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let h = NSStackView(views: [nameLabel, bar, valueLabel])
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 8
        h.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h)
        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: leadingAnchor),
            h.trailingAnchor.constraint(equalTo: trailingAnchor),
            h.topAnchor.constraint(equalTo: topAnchor),
            h.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    func update(_ s: Metrics.Sample?) {
        guard let s = s else {
            valueLabel.stringValue = "—"
            bar.ratio = 0
            return
        }
        var ratio: CGFloat = 0
        var color = NSColor.controlAccentColor
        switch id {
        case "mem":
            let p = s.ramTotal > 0 ? s.ramUsed / s.ramTotal : 0
            valueLabel.stringValue = String(format: "%.1f/%.0f GB", s.ramUsed / 1e9, s.ramTotal / 1e9)
            ratio = CGFloat(p)
            color = p > 0.85 ? .systemRed : (p > 0.7 ? .systemOrange : .controlAccentColor)
        case "cpu":
            valueLabel.stringValue = String(format: "%.0f%%", s.cpuUsage)
            ratio = CGFloat(min(max(s.cpuUsage / 100, 0), 1))
        case "gpu":
            valueLabel.stringValue = String(format: "%.0f%%", s.gpuUsage)
            ratio = CGFloat(min(max(s.gpuUsage / 100, 0), 1))
        case "temp":
            valueLabel.stringValue = String(format: "%.0f°C", s.cpuTemp)
            ratio = CGFloat(min(max((s.cpuTemp - 30) / 75, 0), 1))
            color = s.cpuTemp > 90 ? .systemRed : (s.cpuTemp > 75 ? .systemOrange : .systemTeal)
        case "power":
            valueLabel.stringValue = String(format: "%.0f W", s.allW)
            ratio = CGFloat(min(max(s.allW / 60, 0), 1))
        case "fan":
            valueLabel.stringValue = String(format: "%.0f rpm", s.fan)
            ratio = CGFloat(min(max(s.fan / 6000, 0), 1))
        case "disk":
            let r = DiskWatcher.shared.readMB, w = DiskWatcher.shared.writeMB
            valueLabel.stringValue = String(format: "↓%.0f ↑%.0f", r, w)
            ratio = CGFloat(min(max((r + w) / 300, 0), 1))
        case "batt":
            let (_, pct) = PowerWatcher.cached()
            valueLabel.stringValue = "\(pct)%"
            ratio = CGFloat(min(max(Double(pct) / 100, 0), 1))
            color = pct < 20 ? .systemRed : .systemGreen
        default:
            valueLabel.stringValue = "—"
        }
        bar.ratio = ratio
        bar.color = color
    }
}

/// 小组件面板：按设置里的组合动态生成行，数据实时刷新
final class StatusWidgetView: NSView {
    private var rows: [String] = []
    private var rowViews: [String: MetricRow] = [:]
    private let stack = NSStackView()
    private let detailLabel = NSTextField(labelWithString: "等待数据…")
    private let footLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 296, height: 172))
        build()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        let title = NSTextField(labelWithString: "Mac 工具箱")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.stringValue = "内存 · CPU · GPU · 温度"

        let head = NSStackView(views: [title, detailLabel])
        head.orientation = .horizontal
        head.alignment = .firstBaseline
        head.spacing = 8

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        footLabel.font = .systemFont(ofSize: 10, weight: .regular)
        footLabel.textColor = .tertiaryLabelColor
        footLabel.lineBreakMode = .byTruncatingTail
        footLabel.maximumNumberOfLines = 1

        let outer = NSStackView(views: [head, stack, footLabel])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 10
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            outer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
        ])
        setMetrics(Settings.shared.menuRows.components(separatedBy: ","))
    }

    /// 组合变了才重建行视图，没变就只更新数值
    func setMetrics(_ ids: [String]) {
        let clean = ids.filter { id in StatusBarController.catalog.contains { $0.id == id } }
        guard clean != rows else { return }
        rows = clean

        stack.arrangedSubviews.forEach { v in
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        rowViews.removeAll()

        for id in clean {
            guard let meta = StatusBarController.catalog.first(where: { $0.id == id }) else { continue }
            let row = MetricRow(id: id, name: meta.name)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 17).isActive = true
            row.widthAnchor.constraint(equalToConstant: 272).isActive = true
            rowViews[id] = row
            stack.addArrangedSubview(row)
        }
        // 面板高度跟着行数走，菜单里才不会留大片空白
        let h = 62 + CGFloat(max(clean.count, 1)) * 25
        setFrameSize(NSSize(width: 296, height: h))
    }

    func render(_ s: Metrics.Sample?) {
        rowViews.values.forEach { $0.update(s) }
        guard let s = s else {
            detailLabel.stringValue = "数据源未就绪"
            footLabel.stringValue = ""
            return
        }
        let swap = s.swapTotal > 0 ? String(format: "%.1f GB", s.swapUsed / 1e9) : "—"
        footLabel.stringValue = String(format: "交换 %@ · 风扇 %.0f rpm · 功耗 %.0f W", swap, s.fan, s.allW)
        let enabled = rows.compactMap { id in StatusBarController.catalog.first { $0.id == id }?.name }
        detailLabel.stringValue = enabled.isEmpty ? "在偏好设置里选择指标" : enabled.joined(separator: " · ")
    }

    func refresh() { render(Metrics.shared.latest) }
}

// MARK: - 给小组件写快照

/// 主 App 是「非沙盒」，可以直接把数据写进扩展自己的沙盒容器；
/// 扩展（沙盒进程）从自己容器里读，不用 App Group、不用证书。
enum WidgetSnapshot {
    /// 上次主动让小组件刷新的时间：太频繁会被系统砍掉预算
    private static var lastReload = Date.distantPast

    static func write(_ s: Metrics.Sample) {
        let fm = FileManager.default
        // 扩展还没被系统加载过时容器不存在，这时候别往里塞东西
        guard fm.fileExists(atPath: Snapshot.containerRoot) else { return }

        let url = URL(fileURLWithPath: Snapshot.hostPath)
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let (src, pct) = PowerWatcher.cached()
        let d = DiskWatcher.shared
        let json: [String: Any] = [
            "t": Date().timeIntervalSince1970,
            "ct": s.cpuTemp, "gt": s.gpuTemp,
            "aw": s.allW, "fan": s.fan,
            "cu": s.cpuUsage, "gu": s.gpuUsage,
            "ru": s.ramUsed / 1e9, "rt": s.ramTotal / 1e9,
            "su": s.swapUsed / 1e9, "st": s.swapTotal / 1e9,
            "df": d.diskFreeGB, "dt": d.diskTotalGB,
            "b": pct, "p": src,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        // 每 4 分钟推一次重载，小组件不用干等着自己的 1 分钟节奏
        if Date().timeIntervalSince(lastReload) > 240 {
            lastReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
        // 先写临时文件再换名，避免小组件读到写了一半的 JSON
        let tmp = dir.appendingPathComponent(".widget-snapshot.tmp")
        do {
            try data.write(to: tmp)
            _ = try? fm.replaceItemAt(url, withItemAt: tmp)
        } catch {
            return
        }
    }
}
