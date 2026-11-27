import AppKit
import CoreGraphics
import ApplicationServices

// MARK: - 合盖不休眠（clamshell / disablesleep）
// 用 pmset 的未公开参数 disablesleep：电池供电下合盖也不休眠，是移动场景唯一管用的方案。
// 开关需要管理员权限，通过 osascript 弹系统密码框提权，App 本身不持有、不记录密码。
final class NoSleep {
    static let shared = NoSleep()

    /// 读取当前是否已关闭休眠（pmset -g 输出里 SleepDisabled = 1）
    func isEnabled() -> Bool {
        let out = shell("/usr/bin/pmset", ["-g"])
        for line in out.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("SleepDisabled") {
                let parts = t.split(separator: " ").map(String.init)
                return parts.count >= 2 && parts[1] == "1"
            }
        }
        return false
    }

    /// 通过系统密码框提权切换。必须在后台线程调用：密码框是模态阻塞的。
    /// 用「实际状态是否到达目标」来判断成败，避免解析 osascript 的 stderr。
    @discardableResult
    func set(_ on: Bool) -> Bool {
        let val = on ? "1" : "0"
        let script = "do shell script \"pmset -a disablesleep \(val)\" with administrator privileges"
        _ = shell("/usr/bin/osascript", ["-e", script])
        Thread.sleep(forTimeInterval: 0.2)
        return isEnabled() == on
    }
}

// MARK: - 外部入口（URL scheme / 控制中心 / 菜单栏共用）

enum ToolboxAction: String {
    case screenClean = "screen"
    case keyboardClean = "keyboard"
    case noSleep = "nosleep"
    case show = "show"
}

enum Toolbox {
    /// 统一执行入口：控制中心按钮、菜单栏、URL scheme 都走这里
    static func run(_ action: ToolboxAction) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            switch action {
            case .screenClean:
                CleanMode.shared.startScreen()
            case .keyboardClean:
                _ = CleanMode.shared.startKeyboard()
            case .noSleep:
                openModule("nosleep")
            case .show:
                openModule(nil)
            }
        }
    }

    /// 把主窗口拎到前面，并让页面跳到指定模块
    static func openModule(_ id: String?) {
        NotificationCenter.default.post(name: .uiAction, object: id.map { "nav:" + $0 } ?? "show")
    }

    /// mactoolbox://screen / mactoolbox://keyboard / mactoolbox://nosleep
    static func handle(url: URL) {
        let key = (url.host ?? url.path.replacingOccurrences(of: "/", with: ""))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let action = ToolboxAction(rawValue: key.lowercased()) else {
            run(.show)
            return
        }
        run(action)
    }

    /// 打开系统设置的「控制中心」面板，指导把控制项拖出来
    static func openControlCenterSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.controlcenter",
        ]
        for c in candidates {
            if let u = URL(string: c), NSWorkspace.shared.open(u) { return }
        }
        if let u = URL(string: "x-apple.systempreferences:com.apple.settings") {
            NSWorkspace.shared.open(u)
        }
    }
}

// MARK: - 清洁模式（键盘清洁 / 屏幕清洁）

/// 普通的 borderless 窗口不能成为 key window，键盘事件会继续送到别的 App。
/// 这里重写 canBecomeKey/canBecomeMain，让全屏遮罩自己接住所有按键 —— 这是
/// 「不需要辅助功能授权也能锁键盘」的关键，不用 CGEventTap 就不用申请权限。
private final class CleanWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CleanMode {
    static let shared = CleanMode()

    private var window: NSWindow?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    private var guardTimer: Timer?

    var active: Bool { window != nil }

    private func accessibilityEnabled() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// 键盘清洁：全屏遮罩吃掉所有按键。返回 0 = 已进入。
    /// 授权是可选的增强项（拿到后连 Cmd+Tab 之外的系统级按键也能吞），不再是前置条件。
    @discardableResult
    func startKeyboard() -> Int {
        if window != nil { return 0 }
        showOverlay(title: "键盘清洁",
                    hint: "键盘已锁定，放心擦拭\n按 Esc 或点击屏幕退出",
                    isKeyboard: true)
        return 0
    }

    /// 屏幕清洁：全屏纯色背景，看清灰尘；点击或按任意键退出，无需任何权限。
    func startScreen() {
        if window != nil { return }
        showOverlay(title: "屏幕清洁",
                    hint: "深色背景方便看清灰尘与污渍\n按任意键或点击屏幕退出",
                    isKeyboard: false)
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        guardTimer?.invalidate()
        guardTimer = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    private func showOverlay(title: String, hint: String, isKeyboard: Bool) {
        // 覆盖所有屏幕（含外接屏）的并集
        var rect = NSRect.zero
        for s in NSScreen.screens { rect = rect.union(s.frame) }

        let w = CleanWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver
        w.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.035, blue: 0.045, alpha: 1)
        w.isOpaque = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = false
        w.acceptsMouseMovedEvents = false

        let content = CleanOverlayView(frame: rect)
        content.title = title
        content.hint = hint
        content.onExit = { [weak self] in self?.stop() }
        w.contentView = content
        window = w

        // 该窗口成为 key window 后，按键只会送到本进程，其他 App 收不到
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeMain()

        installLocalMonitor(isKeyboard: isKeyboard)
        // 顺手把 CGEventTap 装上（已授权时连系统级快捷键一起吞，没授权也不影响使用）
        if accessibilityEnabled() { installKeyTap() }
        if isKeyboard { startGuard() }
    }

    /// 每 0.5 秒确认一次自己还是前台，防止 Cmd+Tab / 点 Dock 之类的操作把遮罩挤到后面
    private func startGuard() {
        guardTimer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let w = self.window else { return }
            if !NSApp.isActive || !w.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                w.makeKeyAndOrderFront(nil)
            }
        }
        guardTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    /// 全局键盘事件拦截（可选增强）：擦键盘时按键不触发任何操作，Esc（键码 53）退出。
    private func installKeyTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let t = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                  place: .headInsertEventTap,
                                  options: .defaultTap,
                                  eventsOfInterest: mask,
                                  callback: { _, type, event, _ in
            if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                DispatchQueue.main.async { CleanMode.shared.stop() }
            }
            return nil // 吞掉全部键盘事件
        }, userInfo: nil)
        guard let t = t else { return }
        tap = t
        let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        source = s
        CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    /// 本进程内的按键处理：键盘清洁只放行 Esc，屏幕清洁任意键退出
    private func installLocalMonitor(isKeyboard: Bool) {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            guard let self = self else { return nil }
            if isKeyboard {
                if e.keyCode == 53 { self.stop() }
                return nil // 吞掉按键，不让它触发任何响应
            }
            self.stop()
            return nil
        }
    }
}

/// 全屏遮罩视图：居中标题 + 提示，点击任意位置退出
final class CleanOverlayView: NSView {
    var title = ""
    var hint = ""
    var onExit: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .regular),
            .foregroundColor: NSColor(white: 1, alpha: 0.55),
        ]
        let tSize = (title as NSString).size(withAttributes: titleAttrs)
        let hSize = (hint as NSString).size(withAttributes: hintAttrs)
        let cx = bounds.midX
        let cy = bounds.midY
        (title as NSString).draw(at: NSPoint(x: cx - tSize.width / 2, y: cy + 28), withAttributes: titleAttrs)
        (hint as NSString).draw(at: NSPoint(x: cx - hSize.width / 2, y: cy - 26), withAttributes: hintAttrs)
    }

    override func mouseDown(with event: NSEvent) {
        onExit?()
    }
}
