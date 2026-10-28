import AppKit
import Foundation

/// 菜单栏常驻：实时温度/功耗 + 常用操作，像成熟工具那样不占 Dock 也能用
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var item: NSStatusItem?
    private var timer: Timer?

    func install() {
        guard item == nil else { return }
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = it

        if let img = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: "烤机台") {
            img.isTemplate = true
            it.button?.image = img
            it.button?.imagePosition = .imageLeading
        }
        it.button?.title = " —"

        let menu = NSMenu()
        let start = NSMenuItem(title: "开始烤机", action: #selector(onStart), keyEquivalent: "")
        start.target = self
        menu.addItem(start)
        let stop = NSMenuItem(title: "停手", action: #selector(onStop), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)
        menu.addItem(.separator())

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

        let show = NSMenuItem(title: "显示主窗口", action: #selector(onShow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let quit = NSMenuItem(title: "退出烤机台", action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        it.menu = menu

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        guard let s = Metrics.shared.latest else {
            item?.button?.title = " —"
            return
        }
        let t = Int(s.cpuTemp.rounded())
        let w = Int(s.allW.rounded())
        item?.button?.title = Burner.shared.running ? " \(t)° · \(w)W" : " \(t)°"
        NSApp.dockTile.badgeLabel = Burner.shared.running ? "\(t)°" : nil
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
        NSApp.terminate(nil)
    }
    @objc private func onMode(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            NotificationCenter.default.post(name: .uiAction, object: "mode:" + id)
        }
    }
}

extension Notification.Name {
    static let uiAction = Notification.Name("uiAction")
}
