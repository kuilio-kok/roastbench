import WidgetKit
import SwiftUI
import AppIntents
import AppKit

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

extension Facts {
    static func preview() -> Facts {
        var f = Facts()
        f.memUsed = 23.2e9; f.memTotal = 34.4e9
        f.swapUsed = 0.65e9; f.swapTotal = 2.1e9
        f.cpu = 22; f.gpu = 18
        f.temp = 52; f.power = 12; f.fan = 1500; f.battery = 87
        f.hasThermal = true
        return f
    }
}

// MARK: - 小组件：三个预设（静态配置）
// 为什么不用 AppIntentConfiguration：带可配置参数的小组件需要 Xcode 生成的
// App Intents 元数据，纯命令行环境生成不了，系统会实例化失败 —— 表现就是
// 加进去一片空白、timeline 一次都不被调用。静态配置不吃元数据，稳。

/// 扩展侧日志：写到自己的容器里，出问题能直接看
enum WidgetDebug {
    static func log(_ msg: String) {
        let path = NSHomeDirectory() + "/Library/Application Support/widget-debug.log"
        let line = "\(Date()) \(msg)\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8) ?? Data())
            h.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

enum Preset: String {
    case mem, core, thermal

    /// 每一项都要展示哪些指标，顺序即显示顺序
    var ids: [String] {
        switch self {
        case .mem:     return ["used"]
        case .core:    return ["used", "cpu", "temp", "power", "swap"]
        case .thermal: return ["temp", "power", "fan", "batt", "gpu"]
        }
    }
}

struct MetricsEntry: TimelineEntry {
    struct Item: Identifiable {
        let id: String
        let label: String
        let value: String
        let percent: Double?   // 有值就在数值前画一根小条
        let icon: String
    }

    let date: Date
    let percent: Double
    let usedText: String
    let items: [Item]
    let hasThermal: Bool

    /// 内存水位：0 正常 / 1 偏高 / 2 吃紧，决定配色
    var level: Int { percent > 0.85 ? 2 : (percent > 0.7 ? 1 : 0) }
}

enum EntryBuilder {
    static func build(preset: Preset, preview: Bool = false) -> MetricsEntry {
        let f = preview ? Facts.preview() : Facts.current()
        var items: [MetricsEntry.Item] = []

        for id in preset.ids {
            switch id {
            case "used":
                guard f.memTotal > 0 else { continue }
                items.append(.init(id: "used", label: "已用",
                                   value: String(format: "%.1f / %.0f GB", f.memUsed / 1e9, f.memTotal / 1e9),
                                   percent: nil, icon: "internaldrive"))
            case "free":
                items.append(.init(id: "free", label: "可用",
                                   value: String(format: "%.1f GB", f.memAvailable / 1e9),
                                   percent: nil, icon: "square.stack.3d.up"))
            case "cpu":
                items.append(.init(id: "cpu", label: "CPU",
                                   value: String(format: "%.0f%%", f.cpu),
                                   percent: min(max(f.cpu / 100, 0), 1), icon: "cpu"))
            case "gpu":
                guard f.hasThermal else { continue }   // GPU 占用同样来自快照
                items.append(.init(id: "gpu", label: "GPU",
                                   value: String(format: "%.0f%%", f.gpu),
                                   percent: min(max(f.gpu / 100, 0), 1), icon: "cpu.fill"))
            case "swap":
                items.append(.init(id: "swap", label: "交换",
                                   value: String(format: "%.2f GB", f.swapUsed / 1e9),
                                   percent: f.swapTotal > 0 ? min(f.swapUsed / f.swapTotal, 1) : nil,
                                   icon: "arrow.left.arrow.right"))
            case "temp":
                guard f.hasThermal else { continue }
                items.append(.init(id: "temp", label: "温度",
                                   value: String(format: "%.0f°C", f.temp),
                                   percent: min(max((f.temp - 30) / 75, 0), 1), icon: "thermometer.medium"))
            case "power":
                guard f.hasThermal else { continue }
                items.append(.init(id: "power", label: "功耗",
                                   value: String(format: "%.0f W", f.power),
                                   percent: min(max(f.power / 60, 0), 1), icon: "bolt"))
            case "fan":
                guard f.hasThermal else { continue }
                items.append(.init(id: "fan", label: "风扇",
                                   value: String(format: "%.0f rpm", f.fan),
                                   percent: min(max(f.fan / 6000, 0), 1), icon: "fanblades"))
            case "batt":
                guard f.battery > 0 else { continue }
                items.append(.init(id: "batt", label: "电池",
                                   value: String(format: "%.0f%%", f.battery),
                                   percent: min(max(f.battery / 100, 0), 1), icon: "battery.75"))
            default:
                continue
            }
        }

        return MetricsEntry(date: Date(),
                            percent: f.memPercent,
                            usedText: String(format: "%.1f / %.0f GB", f.memUsed / 1e9, f.memTotal / 1e9),
                            items: items,
                            hasThermal: f.hasThermal)
    }
}

struct PresetProvider: TimelineProvider {
    let preset: Preset

    func placeholder(in context: Context) -> MetricsEntry {
        EntryBuilder.build(preset: preset, preview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (MetricsEntry) -> Void) {
        completion(EntryBuilder.build(preset: preset, preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MetricsEntry>) -> Void) {
        let e = EntryBuilder.build(preset: preset)
        WidgetDebug.log("timeline \(preset.rawValue) family=\(context.family.rawValue) pct=\(e.percent) items=\(e.items.count) thermal=\(e.hasThermal)")
        // 一分钟一次；系统会按预算合并，主 App 也会主动推重载
        completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(60))))
    }
}

extension View {
    func toolboxWidgetBackground(_ entry: MetricsEntry) -> some View {
        containerBackground(for: .widget) {
            ZStack {
                Rectangle().fill(.fill.tertiary)
                LinearGradient(colors: [Color.level(entry.level).opacity(0.16), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

// MARK: - 视觉

extension Color {
    static func level(_ l: Int) -> Color {
        switch l {
        case 2: return .red
        case 1: return .orange
        default: return .teal
        }
    }
}

/// 内存环：外圈细底环 + 度数渐变，中间大号百分比
struct MemRing: View {
    var percent: Double
    var tint: Color
    var size: CGFloat
    var line: CGFloat = 9

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.09), lineWidth: line)
            Circle()
                .trim(from: 0, to: min(max(percent, 0.004), 1))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint], center: .center),
                    style: StrokeStyle(lineWidth: line, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int((percent * 100).rounded()))")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: size * 0.12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("内存占用")
        .accessibilityValue("\(Int((percent * 100).rounded()))%")
    }
}

/// 一行指标：图标 + 名称 + （小条）+ 数值
struct MetricLine: View {
    var item: MetricsEntry.Item
    var tint: Color
    var showBar: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 13)
            Text(item.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if showBar, let p = item.percent {
                Capsule().fill(Color.primary.opacity(0.10))
                    .frame(width: 34, height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule().fill(tint)
                                .frame(width: max(3, g.size.width * min(max(p, 0), 1)))
                        }
                    }
                    .clipShape(Capsule())
            }
            Text(item.value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// 大号用的指标方块：图标 + 名称 + 大号数值
struct MetricTile: View {
    var item: MetricsEntry.Item
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                Text(item.label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(item.value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

struct MetricsWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    var entry: MetricsEntry
    /// 预览用：强制指定尺寸族（正常运行时用系统的 widgetFamily）
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? envFamily }

    private var tint: Color { .level(entry.level) }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            default: medium
            }
        }
        .tint(tint)
    }

    // 小号：环 + 容量 + 最多一条附加
    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "memorychip.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text("内存")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(entry.date, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            HStack {
                Spacer(minLength: 0)
                MemRing(percent: entry.percent, tint: tint, size: 94, line: 8)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.usedText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let first = entry.items.first(where: { $0.id != "used" && $0.id != "free" }) {
                    MetricLine(item: first, tint: tint, showBar: false)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 中号：左边环，右边 4 行（通知中心里最顺手的尺寸）
    private var medium: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 4) {
                MemRing(percent: entry.percent, tint: tint, size: 96, line: 9)
                if !entry.items.contains(where: { $0.id == "used" }) {
                    Text(entry.usedText)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100)

            VStack(alignment: .leading, spacing: 7) {
                header
                if entry.items.isEmpty {
                    Text("点右上角编辑\n挑想看的指标")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(entry.items.prefix(4))) { item in
                        MetricLine(item: item, tint: tint)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // 大号：上面环 + 三行摘要，下面把指标铺成方块，空间不浪费
    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                MemRing(percent: entry.percent, tint: tint, size: 128, line: 11)
                VStack(alignment: .leading, spacing: 7) {
                    header
                    if !entry.items.contains(where: { $0.id == "used" }) {
                        Text(entry.usedText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(entry.items.prefix(2))) { item in
                        MetricLine(item: item, tint: tint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if entry.items.count > 2 {
                Divider().opacity(0.4)
                let tiles = Array(entry.items.dropFirst(2).prefix(6))
                let rows = (tiles.count + 1) / 2
                VStack(spacing: 8) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 8) {
                            MetricTile(item: tiles[r * 2], tint: tint)
                            if r * 2 + 1 < tiles.count {
                                MetricTile(item: tiles[r * 2 + 1], tint: tint)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(pressureText).font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !entry.hasThermal {
                    Image(systemName: "info.circle").font(.system(size: 8.5))
                    Text("温度/功耗需打开 App").font(.system(size: 8.5))
                    Spacer(minLength: 6)
                }
                Text(entry.date, style: .time).font(.system(size: 9))
            }
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pressureText: String {
        switch entry.level {
        case 2: return "内存吃紧"
        case 1: return "内存偏高"
        default: return "内存正常"
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "memorychip.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text("Mac 工具箱")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(entry.date, style: .time)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 三个静态小组件

struct MemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "cn.wangchuanhe.toolbox.widget.mem",
                            provider: PresetProvider(preset: .mem)) { entry in
            MetricsWidgetView(entry: entry).toolboxWidgetBackground(entry)
        }
        .configurationDisplayName("内存")
        .description("只看内存占用，一划就到")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "cn.wangchuanhe.toolbox.widget.core",
                            provider: PresetProvider(preset: .core)) { entry in
            MetricsWidgetView(entry: entry).toolboxWidgetBackground(entry)
        }
        .configurationDisplayName("内存与占用")
        .description("内存 + CPU + 温度 + 功耗")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ThermalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "cn.wangchuanhe.toolbox.widget.thermal",
                            provider: PresetProvider(preset: .thermal)) { entry in
            MetricsWidgetView(entry: entry).toolboxWidgetBackground(entry)
        }
        .configurationDisplayName("温度与功耗")
        .description("温度、功耗、风扇、电池")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - 入口

#if !PREVIEW
@main
struct ToolboxWidgets: WidgetBundle {
    var body: some Widget {
        MemWidget()
        CoreWidget()
        ThermalWidget()
        MemControl()
        ScreenCleanControl()
        KeyboardCleanControl()
        NoSleepControl()
    }
}
#endif
