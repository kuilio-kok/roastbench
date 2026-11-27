import WidgetKit
import SwiftUI
import AppIntents
import AppKit

// 三个控制项和小组件按钮共用的跳转逻辑：统一走 mactoolbox:// URL scheme，
// 由主 App 接管执行（清洁模式、pmset 提权这些都得在主进程里做）。
enum ToolboxLink {
    static func open(_ action: String) {
        if let u = URL(string: "mactoolbox://\(action)") {
            NSWorkspace.shared.open(u)
        }
    }
}

struct ScreenCleanIntent: AppIntent {
    static var title: LocalizedStringResource = "屏幕清洁"
    static var description = IntentDescription("深色全屏铺满屏幕，看清灰尘再擦")
    static var openAppWhenRun = false
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult {
        ToolboxLink.open("screen")
        return .result()
    }
}

struct KeyboardCleanIntent: AppIntent {
    static var title: LocalizedStringResource = "键盘清洁"
    static var description = IntentDescription("锁住键盘，放心擦键帽与缝隙")
    static var openAppWhenRun = false
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult {
        ToolboxLink.open("keyboard")
        return .result()
    }
}

struct NoSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "合盖不休眠"
    static var description = IntentDescription("打开开关页，输入管理员密码后生效")
    static var openAppWhenRun = false
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult {
        ToolboxLink.open("nosleep")
        return .result()
    }
}

struct DashboardIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 Mac 工具箱"
    static var openAppWhenRun = false
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult {
        ToolboxLink.open("show")
        return .result()
    }
}

// MARK: - 控制中心控制项

struct ScreenCleanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "cn.wangchuanhe.toolbox.control.screen") {
            ControlWidgetButton(action: ScreenCleanIntent()) {
                Label("屏幕清洁", systemImage: "sparkles")
            }
        }
        .displayName("屏幕清洁")
        .description("深色全屏铺满，看清灰尘与指纹")
    }
}

struct KeyboardCleanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "cn.wangchuanhe.toolbox.control.keyboard") {
            ControlWidgetButton(action: KeyboardCleanIntent()) {
                Label("键盘清洁", systemImage: "keyboard")
            }
        }
        .displayName("键盘清洁")
        .description("锁住键盘，放心擦键帽与缝隙")
    }
}

struct NoSleepControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "cn.wangchuanhe.toolbox.control.nosleep") {
            ControlWidgetButton(action: NoSleepIntent()) {
                Label("合盖不休眠", systemImage: "moon.zzz")
            }
        }
        .displayName("合盖不休眠")
        .description("合上盖子也不睡，跑长任务时用")
    }
}

// MARK: - 内存控制项（百分比直接写在控制中心里）

struct MemValue {
    var percent: Double
    var text: String
}

struct MemValueProvider: ControlValueProvider {
    var previewValue: MemValue { MemValue(percent: 0.42, text: "42%") }

    func currentValue() async throws -> MemValue {
        let f = Facts.current()
        return MemValue(percent: f.memPercent, text: String(format: "%.0f%%", f.memPercent * 100))
    }
}

struct MemControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        // 控制项模板只吃 Label / Text / Image，所以百分比写进按钮标题 ——
        // 下拉控制中心看到的就是最新数字。
        StaticControlConfiguration(kind: "cn.wangchuanhe.toolbox.control.mem",
                                   provider: MemValueProvider()) { value in
            ControlWidgetButton(action: DashboardIntent()) {
                Label("内存 \(value.text)", systemImage: "memorychip")
            }
        }
        .displayName("内存占用")
        .description("控制中心直接看内存用了多少")
    }
}

// MARK: - 数据来源：主 App 的快照优先，拿不到就本地算

struct Facts {
    var memUsed: Double = 0
    var memTotal: Double = 0
    var swapUsed: Double = 0
    var swapTotal: Double = 0
    var cpu: Double = 0
    var gpu: Double = 0
    var temp: Double = 0
    var power: Double = 0
    var fan: Double = 0
    var battery: Double = 0
    var hasThermal = false   // 没快照就拿不到温度/功耗/风扇

    var memPercent: Double { memTotal > 0 ? min(max(memUsed / memTotal, 0), 1) : 0 }
    var memAvailable: Double { max(memTotal - memUsed, 0) }

    static func current() -> Facts {
        if let s = Snapshot.load() {
            var f = Facts()
            f.memUsed = s.ramUsed; f.memTotal = s.ramTotal
            f.swapUsed = s.swapUsed; f.swapTotal = s.swapTotal
            f.cpu = s.cpu; f.gpu = s.gpu
            f.temp = s.cpuTemp; f.power = s.power; f.fan = s.fan
            f.battery = s.battery
            f.hasThermal = true
            return f
        }
        // 兜底：沙盒里自己采内存与 CPU
        let m = MemProbe.sample()
        var f = Facts()
        f.memUsed = Double(m.used); f.memTotal = Double(m.total)
        f.swapUsed = Double(m.swapUsed); f.swapTotal = Double(m.swapTotal)
        f.cpu = MemProbe.cpuPercent()
        return f
    }
}

// MARK: - 小组件：指标可自由组合

struct MetricsOptions: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "指标组合"
    static var description = IntentDescription("挑想看的几项，随时改")

    @Parameter(title: "内存占用率", default: true)
    var memPercent: Bool

    @Parameter(title: "已用 / 总容量", default: true)
    var memUsed: Bool

    @Parameter(title: "可用容量", default: false)
    var memAvailable: Bool

    @Parameter(title: "交换空间", default: false)
    var swap: Bool

    @Parameter(title: "CPU 占用", default: false)
    var cpu: Bool

    @Parameter(title: "GPU 占用", default: false)
    var gpu: Bool

    @Parameter(title: "CPU 温度", default: false)
    var temp: Bool

    @Parameter(title: "整机功耗", default: false)
    var power: Bool

    @Parameter(title: "风扇转速", default: false)
    var fan: Bool

    @Parameter(title: "电池电量", default: false)
    var battery: Bool
}

struct MetricsEntry: TimelineEntry {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let percent: Double?
    }
    let date: Date
    let percent: Double
    let totalText: String
    let items: [Item]
    let empty: Bool
    let live: Bool
}

struct MetricsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MetricsEntry {
        MetricsEntry(date: Date(), percent: 0.62, totalText: "20.1 / 32 GB",
                     items: [
                        .init(label: "内存占用", value: "62%", percent: 0.62),
                        .init(label: "已用 / 总", value: "20.1 / 32 GB", percent: nil),
                     ], empty: false, live: true)
    }

    func snapshot(for configuration: MetricsOptions, in context: Context) async -> MetricsEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: MetricsOptions, in context: Context) async -> Timeline<MetricsEntry> {
        let e = entry(for: configuration)
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(60)))
    }

    private func entry(for c: MetricsOptions) -> MetricsEntry {
        let f = Facts.current()
        var items: [MetricsEntry.Item] = []

        if c.memPercent {
            items.append(.init(label: "内存占用",
                               value: String(format: "%.0f%%", f.memPercent * 100),
                               percent: f.memPercent))
        }
        if c.memUsed {
            items.append(.init(label: "已用 / 总",
                               value: String(format: "%.1f / %.0f GB", f.memUsed / 1e9, f.memTotal / 1e9),
                               percent: nil))
        }
        if c.memAvailable {
            items.append(.init(label: "可用",
                               value: String(format: "%.1f GB", f.memAvailable / 1e9),
                               percent: nil))
        }
        if c.swap {
            items.append(.init(label: "交换",
                               value: String(format: "%.2f GB", f.swapUsed / 1e9),
                               percent: f.swapTotal > 0 ? min(f.swapUsed / f.swapTotal, 1) : nil))
        }
        if c.cpu {
            items.append(.init(label: "CPU",
                               value: String(format: "%.0f%%", f.cpu),
                               percent: min(max(f.cpu / 100, 0), 1)))
        }
        if c.gpu {
            items.append(.init(label: "GPU",
                               value: String(format: "%.0f%%", f.gpu),
                               percent: min(max(f.gpu / 100, 0), 1)))
        }
        // 温度 / 功耗 / 风扇只有主 App 的快照里有，没快照就不显示空行
        if c.temp && f.hasThermal {
            items.append(.init(label: "CPU 温度",
                               value: String(format: "%.0f°C", f.temp),
                               percent: min(max((f.temp - 30) / 75, 0), 1)))
        }
        if c.power && f.hasThermal {
            items.append(.init(label: "功耗",
                               value: String(format: "%.0f W", f.power),
                               percent: min(max(f.power / 60, 0), 1)))
        }
        if c.fan && f.hasThermal {
            items.append(.init(label: "风扇",
                               value: String(format: "%.0f rpm", f.fan),
                               percent: min(max(f.fan / 6000, 0), 1)))
        }
        if c.battery {
            items.append(.init(label: "电池",
                               value: String(format: "%.0f%%", f.battery),
                               percent: min(max(f.battery / 100, 0), 1)))
        }

        return MetricsEntry(date: Date(),
                            percent: f.memPercent,
                            totalText: String(format: "%.1f / %.0f GB", f.memUsed / 1e9, f.memTotal / 1e9),
                            items: items,
                            empty: items.isEmpty,
                            live: f.hasThermal)
    }
}

struct MetricsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "cn.wangchuanhe.toolbox.widget.metrics",
                               intent: MetricsOptions.self,
                               provider: MetricsProvider()) { entry in
            MetricsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("内存与占用")
        .description("内存、交换、CPU、温度、功耗，自己挑着看")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MetricsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: MetricsEntry

    private var accent: Color {
        entry.percent > 0.85 ? .red : (entry.percent > 0.7 ? .orange : .teal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "memorychip.fill").font(.system(size: 10))
                Text("Mac 工具箱").font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 0)
                Text(String(format: "%.0f%%", entry.percent * 100))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(accent)
                        .frame(width: max(3, geo.size.width * min(max(entry.percent, 0), 1)))
                }
            }
            .frame(height: 5)

            if entry.empty {
                Spacer(minLength: 0)
                Text("长按 → 编辑小组件\n挑想看的指标")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                let shown = family == .systemSmall ? Array(entry.items.prefix(3)) : Array(entry.items.prefix(5))
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(shown) { item in
                        HStack(spacing: 4) {
                            Text(item.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 2)
                            Text(item.value)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                Spacer(minLength: 0)
                if !entry.live {
                    Text("打开 App 后温度/功耗才有数")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - 入口

@main
struct ToolboxWidgets: WidgetBundle {
    var body: some Widget {
        MetricsWidget()
        MemControl()
        ScreenCleanControl()
        KeyboardCleanControl()
        NoSleepControl()
    }
}
