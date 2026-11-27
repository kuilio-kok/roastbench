import Foundation
import AppIntents

#if canImport(AppKit)
import AppKit
#endif

// 控制中心控制项用的意图：扩展和主 App 各编译一份。
// 扩展里跑的时候拉不起 App（WidgetKit 扩展受限），所以：
//   1. 先往容器里塞一条「待执行动作」，App 起来 / 被激活时来取；
//   2. 再顺手试一次 URL scheme，成不成都不影响第 1 条。
// 主 App 里跑的时候（openAppWhenRun 生效时意图会转到 App 进程）直接执行。
enum ToolboxDispatch {
    static func perform(_ action: String) {
        #if WIDGET_EXT
        Snapshot.Pending.write(action)
        if let u = URL(string: "mactoolbox://\(action)") {
            NSWorkspace.shared.open(u)
        }
        #else
        Toolbox.run(ToolboxAction(rawValue: action) ?? .show)
        #endif
    }
}

struct ScreenCleanIntent: AppIntent {
    static var title: LocalizedStringResource = "屏幕清洁"
    static var description = IntentDescription("深色全屏铺满屏幕，看清灰尘再擦")
    static var openAppWhenRun = true
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult {
        ToolboxDispatch.perform("screen")
        return .result()
    }
}

struct KeyboardCleanIntent: AppIntent {
    static var title: LocalizedStringResource = "键盘清洁"
    static var description = IntentDescription("锁住键盘，放心擦键帽与缝隙")
    static var openAppWhenRun = true
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult {
        ToolboxDispatch.perform("keyboard")
        return .result()
    }
}

struct NoSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "合盖不休眠"
    static var description = IntentDescription("打开开关页，输入管理员密码后生效")
    static var openAppWhenRun = true
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult {
        ToolboxDispatch.perform("nosleep")
        return .result()
    }
}

struct DashboardIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 Mac 工具箱"
    static var openAppWhenRun = true
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult {
        ToolboxDispatch.perform("show")
        return .result()
    }
}
