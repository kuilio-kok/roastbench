import AppKit
import WebKit
import Foundation
import Metal
import CoreGraphics
import IOKit
import IOKit.pwr_mgt
import IOKit.ps
import ServiceManagement
import UserNotifications
import Darwin
import UniformTypeIdentifiers

// MARK: - 小工具

func shell(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    try? p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func sysctlString(_ key: String) -> String {
    shell("/usr/sbin/sysctl", ["-n", key])
}

/// 自定义壁纸的落盘路径（App Support 目录，roast://wallpaper 读取）
func wallpaperFilePath() -> URL? {
    guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true) else { return nil }
    let sub = dir.appendingPathComponent("烤机台")
    try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    return sub.appendingPathComponent("wallpaper.jpg")
}

func jsonEscape(_ s: String) -> String {
    var out = ""
    for ch in s {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default: out.append(ch)
        }
    }
    return out
}

// MARK: - 机型

let MODEL_NAMES: [String: String] = [
    "MacBookAir10,1": "MacBook Air 13\" (M1, 2020)",
    "Mac14,2": "MacBook Air 13\" (M2, 2022)",
    "Mac14,15": "MacBook Air 15\" (M2, 2023)",
    "Mac15,12": "MacBook Air 13\" (M3, 2024)",
    "Mac15,13": "MacBook Air 15\" (M3, 2024)",
    "MacBookPro18,1": "MacBook Pro 16\" (2021)",
    "MacBookPro18,2": "MacBook Pro 16\" (2021)",
    "MacBookPro18,3": "MacBook Pro 14\" (2021)",
    "MacBookPro18,4": "MacBook Pro 14\" (2021)",
    "Mac14,7": "MacBook Pro 13\" (M2, 2022)",
    "Mac14,5": "MacBook Pro 14\" (2023)",
    "Mac14,6": "MacBook Pro 14\" (M2 Pro/Max, 2023)",
    "Mac14,9": "MacBook Pro 16\" (2023)",
    "Mac14,10": "MacBook Pro 16\" (2023)",
    "Mac15,3": "MacBook Pro 14\" (M3, 2023)",
    "Mac15,6": "MacBook Pro 14\" (M3 系列, 2023)",
    "Mac15,7": "MacBook Pro 14\" (M3 系列, 2023)",
    "Mac15,8": "MacBook Pro 16\" (M3 系列, 2023)",
    "Mac15,10": "MacBook Pro 16\" (M3 系列, 2023)",
    "Mac15,11": "MacBook Pro 16\" (M3 系列, 2023)",
    "Macmini9,1": "Mac mini (M1, 2020)",
    "Mac14,3": "Mac mini (M2, 2023)",
    "Mac14,12": "Mac mini (M2 Pro, 2023)",
    "Mac13,1": "Mac Studio (M1 Max, 2022)",
    "Mac13,2": "Mac Studio (M1 Ultra, 2022)",
    "Mac14,13": "Mac Studio (M2 Max, 2023)",
    "Mac14,14": "Mac Studio (M2 Ultra, 2023)",
    "Mac14,8": "Mac Pro (2023)",
    "MacPro7,1": "Mac Pro (Intel, 2019)",
    "Macmini8,1": "Mac mini (Intel, 2018)",
    "iMac21,1": "iMac 24\" (M1, 2021)",
    "iMac21,2": "iMac 24\" (M1, 2021)",
    "Mac15,4": "iMac 24\" (M3, 2023)",
    "Mac15,5": "iMac 24\" (M3, 2023)",
    "VirtualMac2,1": "虚拟机中的 macOS",
]

struct MachineInfo {
    var displayName: String
    var modelName: String
    var modelId: String
    var chip: String
    var appleSilicon: Bool
    var ncpu: Int
    var pcores: Int
    var ecores: Int
    var memoryGB: Double
    var macos: String
    var gpu: String         // GPU 型号
    var fanless: Bool?      // nil = 还没判定
    var power: String       // ac / battery / unknown

    var json: String {
        let fan = fanless.map { String($0) } ?? "null"
        return """
        {"display_name":"\(jsonEscape(displayName))","model_name":"\(jsonEscape(modelName))",\
        "model_id":"\(modelId)","chip":"\(jsonEscape(chip))","apple_silicon":\(appleSilicon),\
        "ncpu":\(ncpu),"pcores":\(pcores),"ecores":\(ecores),"memory_gb":\(memoryGB),\
        "macos":"\(macos)","gpu":"\(jsonEscape(gpu))","fanless":\(fan),"power":"\(power)"}
        """
    }
}

final class Machine {
    private(set) var info: MachineInfo

    init() {
        let modelId = sysctlString("hw.model")
        let chip = sysctlString("machdep.cpu.brand_string")
        let ncpu = Int(sysctlString("hw.ncpu")) ?? 1
        let pc = Int(sysctlString("hw.perflevel0.logicalcpu")) ?? ncpu
        let ec = Int(sysctlString("hw.perflevel1.logicalcpu")) ?? 0
        let mem = Double(sysctlString("hw.memsize")) ?? 0
        let apple = chip.hasPrefix("Apple")
        let osver = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(osver.majorVersion).\(osver.minorVersion).\(osver.patchVersion)"

        // 不在这里跑 system_profiler（要好几秒，会卡主线程），先用映射表，后台再补
        var fanless: Bool? = nil
        if modelId.hasPrefix("MacBookAir") { fanless = true }

        info = MachineInfo(displayName: MODEL_NAMES[modelId] ?? modelId,
                           modelName: modelId, modelId: modelId,
                           chip: chip.isEmpty ? "Apple Silicon" : chip, appleSilicon: apple,
                           ncpu: ncpu, pcores: pc, ecores: ec, memoryGB: (mem / 1073741824 * 10).rounded() / 10,
                           macos: macOS, gpu: "识别中…", fanless: fanless, power: PowerWatcher.cached().0)
    }

    /// 后台补全营销名（system_profiler 慢），完成后回调刷新 UI
    func refreshNameAsync(onDone: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let prof = shell("/usr/sbin/system_profiler", ["SPHardwareDataType"])
            var name = self.info.modelId
            if let line = prof.components(separatedBy: "\n").first(where: { $0.contains("Model Name:") }) {
                name = line.replacingOccurrences(of: "Model Name:", with: "").trimmingCharacters(in: .whitespaces)
            }
            var gpu = "未知"
            let disp = shell("/usr/sbin/system_profiler", ["SPDisplaysDataType"])
            if let gl = disp.components(separatedBy: "\n").first(where: { $0.contains("Chipset Model:") }) {
                gpu = gl.replacingOccurrences(of: "Chipset Model:", with: "").trimmingCharacters(in: .whitespaces)
            }
            if let cl = disp.components(separatedBy: "\n").first(where: { $0.contains("Total Number of Cores") }) {
                let num = cl.replacingOccurrences(of: "Total Number of Cores:", with: "").trimmingCharacters(in: .whitespaces)
                if !num.isEmpty { gpu = gpu + " · " + num + " 核" }
            }
            DispatchQueue.main.async {
                self.info.gpu = gpu
                // 映射表里有的保持表里的（更具体），没有的用 system_profiler 结果
                if MODEL_NAMES[self.info.modelId] == nil {
                    self.info.displayName = name
                }
                self.info.modelName = name
                if self.info.fanless == nil && name.contains("MacBook Air") { self.info.fanless = true }
                onDone()
            }
        }
    }

    func refreshFanless(fromFanCount count: Int) {
        info.fanless = (count == 0)
    }
    func setPower(_ s: String) { info.power = s }
}

// MARK: - 电源监听（拔电秒感知）

final class PowerWatcher {
    private static let queue = DispatchQueue(label: "power.watch", qos: .utility)
    static var onChange: ((String, Int) -> Void)?
    private static var lastSource = ""
    private static var lastPercent = -1
    private static var runLoopSource: CFRunLoopSource?

    static func read() -> (String, Int) {
        let out = shell("/usr/bin/pmset", ["-g", "batt"])
        var pct = 0
        if let r = out.range(of: #"(\d+)%"#, options: .regularExpression) {
            pct = Int(out[r].replacingOccurrences(of: "%", with: "")) ?? 0
        }
        let src: String
        if out.contains("AC Power") || out.contains("charged") { src = "ac" }
        else if out.contains("Battery Power") { src = "battery" }
        else { src = "unknown" }
        return (src, pct)
    }

    static func source() -> String { read().0 }
    static func percent() -> Int { read().1 }

    // 缓存值：采样 JSON 用它，避免每 250ms 起一个 pmset 进程
    private static var cachedSource = "ac"
    private static var cachedPercent = 100
    static func cached() -> (String, Int) { (cachedSource, cachedPercent) }

    static func start() {
        let (src, pct) = read()
        lastSource = src
        lastPercent = pct
        cachedSource = src
        cachedPercent = pct

        // IOKit 电源事件监听：接电/断电即时触发（毫秒级）
        if let s = IOPSNotificationCreateRunLoopSource(powerEventCallback, nil)?.takeRetainedValue() {
            runLoopSource = s
            CFRunLoopAddSource(CFRunLoopGetCurrent(), s, .defaultMode)
        }

        // 兜底轮询：电量百分比渐变 IOKit 未必逐个通知
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            queue.async { checkNow() }
        }
    }

    /// IOKit 回调入口（C 函数指针，不能捕获上下文，故走静态方法）
    static func kick() { queue.async { checkNow() } }

    private static func checkNow() {
        let (src, pct) = read()
        if src != lastSource || pct != lastPercent {
            lastSource = src
            lastPercent = pct
            cachedSource = src
            cachedPercent = pct
            DispatchQueue.main.async { onChange?(src, pct) }
        }
    }
}

/// IOKit 电源通知的 C 回调，转发给 PowerWatcher
private let powerEventCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    PowerWatcher.kick()
}

// MARK: - 设置 / 历史

final class Settings {
    static let shared = Settings()
    private let ud = UserDefaults.standard
    private enum K {
        static let theme = "theme"
        static let fuse = "fuse"
        static let fuseTemp = "fuseTemp"
        static let interval = "interval"
        static let windowSec = "windowSec"
        static let defaultMode = "defaultMode"
        static let showPeak = "showPeak"
        static let accent = "accent"
        static let chartTheme = "chartTheme"
        static let wallpaper = "wallpaper"
        static let customColors = "customColors"
        static let dashboard = "dashboard"
        static let glassAlpha = "glassAlpha"
        static let density = "density"
        static let sideWidth = "sideWidth"
        static let radius = "radius"
        static let chartFill = "chartFill"
        static let chartLine = "chartLine"
        static let lang = "lang"
        static let fontSize = "fontSize"
        static let history = "history"
    }

    var theme: String { ud.string(forKey: K.theme) ?? "auto" }
    var fuse: Bool { ud.object(forKey: K.fuse) == nil ? true : ud.bool(forKey: K.fuse) }
    var fuseTemp: Int { ud.object(forKey: K.fuseTemp) == nil ? 108 : ud.integer(forKey: K.fuseTemp) }
    var interval: Int { ud.object(forKey: K.interval) == nil ? 250 : ud.integer(forKey: K.interval) }
    var windowSec: Int { ud.object(forKey: K.windowSec) == nil ? 60 : ud.integer(forKey: K.windowSec) }
    var defaultMode: String { ud.string(forKey: K.defaultMode) ?? "auto" }
    var showPeak: Bool { ud.object(forKey: K.showPeak) == nil ? true : ud.bool(forKey: K.showPeak) }
    var accent: String { ud.string(forKey: K.accent) ?? "" }
    var chartTheme: String { ud.string(forKey: K.chartTheme) ?? "apple" }
    var wallpaper: String { ud.string(forKey: K.wallpaper) ?? "none" }
    var dashboard: String { ud.string(forKey: K.dashboard) ?? "" }
    var glassAlpha: Int { ud.object(forKey: K.glassAlpha) == nil ? 72 : ud.integer(forKey: K.glassAlpha) }
    var density: String { ud.string(forKey: K.density) ?? "standard" }
    var sideWidth: Int { ud.object(forKey: K.sideWidth) == nil ? 278 : ud.integer(forKey: K.sideWidth) }
    var radius: Int { ud.object(forKey: K.radius) == nil ? 14 : ud.integer(forKey: K.radius) }
    var chartFill: Bool { ud.object(forKey: K.chartFill) == nil ? true : ud.bool(forKey: K.chartFill) }
    var chartLine: Double { ud.object(forKey: K.chartLine) == nil ? 1.6 : ud.double(forKey: K.chartLine) }
    var lang: String { ud.string(forKey: K.lang) ?? "auto" }
    var fontSize: Int { ud.object(forKey: K.fontSize) == nil ? 13 : ud.integer(forKey: K.fontSize) }
    func setDashboard(_ json: String) { ud.set(json, forKey: K.dashboard) }
    func setGlassAlpha(_ v: Int) { ud.set(v, forKey: K.glassAlpha) }
    var customColors: [String: String] { ud.dictionary(forKey: K.customColors) as? [String: String] ?? [:] }
    func setCustomColor(_ key: String, _ hex: String) {
        var d = customColors
        d[key] = hex
        ud.set(d, forKey: K.customColors)
    }
    func clearCustomColors() { ud.removeObject(forKey: K.customColors) }

    func set(_ key: String, _ value: Any) {
        let map: [String: String] = [
            "theme": K.theme, "fuse": K.fuse, "fuseTemp": K.fuseTemp,
            "interval": K.interval, "windowSec": K.windowSec,
            "defaultMode": K.defaultMode, "showPeak": K.showPeak,
            "accent": K.accent, "chartTheme": K.chartTheme, "wallpaper": K.wallpaper,
            "density": K.density, "sideWidth": K.sideWidth, "radius": K.radius,
            "chartFill": K.chartFill, "chartLine": K.chartLine,
            "lang": K.lang, "fontSize": K.fontSize,
        ]
        if let real = map[key] { ud.set(value, forKey: real) }
    }

    func applyTheme() {
        switch theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil          // 跟随系统
        }
    }

    func isDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func loadHistory() -> [[String: Any]] {
        (ud.array(forKey: K.history) as? [[String: Any]]) ?? []
    }
    func saveRun(_ record: [String: Any]) {
        var all = loadHistory()
        all.insert(record, at: 0)
        if all.count > 20 { all = Array(all.prefix(20)) }
        ud.set(all, forKey: K.history)
    }
    func clearHistory() { ud.removeObject(forKey: K.history) }

    var json: String {
        """
        {"theme":"\(theme)","fuse":\(fuse),"fuseTemp":\(fuseTemp),\
        "interval":\(interval),"windowSec":\(windowSec),"defaultMode":"\(defaultMode)",\
        "showPeak":\(showPeak),"accent":"\(accent)","chartTheme":"\(chartTheme)",\
        "wallpaper":"\(wallpaper)",\
        "customColors":\(customColorsJSON),"glassAlpha":\(glassAlpha),\
        "density":"\(density)","sideWidth":\(sideWidth),"radius":\(radius),\
        "chartFill":\(chartFill),"chartLine":\(chartLine),"lang":"\(lang)","fontSize":\(fontSize),\
        "dashboard":"\(jsonEscape(dashboard))","dark":\(isDark())}
        """
    }

    private var customColorsJSON: String {
        if let d = try? JSONSerialization.data(withJSONObject: customColors),
           let str = String(data: d, encoding: .utf8) { return str }
        return "{}"
    }
}

// MARK: - macmon 数据源

final class Metrics {
    static let shared = Metrics()

    struct Sample {
        var cpuTemp = 0.0, gpuTemp = 0.0
        var cpuW = 0.0, gpuW = 0.0, allW = 0.0, sysW = 0.0
        var fan = 0.0, fanCount = 0
        var pFreq = 0.0, eFreq = 0.0, gFreq = 0.0
        var cpuUsage = 0.0, gpuUsage = 0.0
        var ramTotal = 0.0, ramUsed = 0.0, swapTotal = 0.0, swapUsed = 0.0
    }

    var onSample: ((Sample) -> Void)?
    var onUnavailable: (() -> Void)?
    private(set) var available = false
    private(set) var latest: Sample?
    private var proc: Process?
    private var buffer = ""
    private(set) var gotFirst = false
    private var skipped = 0

    var fused: Bool { Settings.shared.fuse }
    var fuseTripped = false

    func start() {
        var path = Bundle.main.path(forResource: "macmon", ofType: nil)
        if path == nil {
            for c in ["/opt/homebrew/bin/macmon", "/usr/local/bin/macmon"] where FileManager.default.fileExists(atPath: c) {
                path = c
                break
            }
        }
        guard let exec = path, FileManager.default.fileExists(atPath: exec) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.onUnavailable?() }
            return
        }
        if !FileManager.default.isExecutableFile(atPath: exec) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec)
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: exec)
        p.arguments = ["pipe", "-i", "\(Settings.shared.interval)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.onUnavailable?() }
            return
        }
        proc = p

        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            self?.consume(chunk)
        }

        // 5 秒还没数据就判定不可用（比如 Intel 机型）
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.gotFirst != true { DispatchQueue.main.async { self?.onUnavailable?() } }
        }
    }

    private func consume(_ chunk: String) {
        buffer += chunk
        while let idx = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<idx.lowerBound])
            buffer = String(buffer[idx.upperBound...])
            handle(line)
        }
    }

    private func dbl(_ any: Any?) -> Double {
        if let n = any as? NSNumber { return n.doubleValue }
        return 0
    }

    private func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return }

        var s = Sample()
        let temp = dict["temp"] as? [String: Any]
        s.cpuTemp = dbl(temp?["cpu_temp_avg"])
        s.gpuTemp = dbl(temp?["gpu_temp_avg"])
        s.cpuW = dbl(dict["cpu_power"])
        s.gpuW = dbl(dict["gpu_power"])
        s.allW = dbl(dict["all_power"])
        s.sysW = dbl(dict["sys_power"])
        s.pFreq = dbl(dict["pcpu_freq_mhz"])
        s.eFreq = dbl(dict["ecpu_freq_mhz"])
        s.gFreq = dbl(dict["gpu_freq_mhz"])
        s.cpuUsage = dbl(dict["cpu_usage_pct"]) * 100
        s.gpuUsage = dbl(dict["gpu_scaled_ratio"]) * 100
        let fans = dict["fans"] as? [[String: Any]] ?? []
        s.fanCount = fans.count
        s.fan = fans.map { dbl($0["rpm"]) }.max() ?? 0
        if let mem = dict["memory"] as? [String: Any] {
            s.ramTotal = dbl(mem["ram_total"])
            s.ramUsed = dbl(mem["ram_usage"])
            s.swapTotal = dbl(mem["swap_total"])
            s.swapUsed = dbl(mem["swap_usage"])
        }

        DispatchQueue.main.async {
            if !self.gotFirst {
                self.gotFirst = true
                self.available = true
            }
            self.latest = s
            if s.fanCount >= 0 { MachineHolder.shared.machine.refreshFanless(fromFanCount: s.fanCount) }
            if self.fused && !self.fuseTripped {
                let worst = max(s.cpuTemp, s.gpuTemp)
                if worst >= Double(Settings.shared.fuseTemp) {
                    self.fuseTripped = true
                    NotificationCenter.default.post(name: .fuseTripped, object: worst)
                }
            }
            self.onSample?(s)
        }
    }

    func stop() {
        proc?.terminate()
        proc = nil
    }

    /// 采样间隔变了就重启数据源
    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.start() }
    }

    static func json(_ s: Sample, power: String, batt: Int) -> String {
        let d = DiskWatcher.shared
        let rt = s.ramTotal / 1e9, ru = s.ramUsed / 1e9
        let st = s.swapTotal / 1e9, su = s.swapUsed / 1e9
        return String(format: """
        {"ct":%.1f,"gt":%.1f,"cw":%.2f,"gw":%.2f,"aw":%.2f,"sw":%.1f,"fan":%.0f,"fn":%d,\
        "pf":%.0f,"ef":%.0f,"gf":%.0f,"cu":%.1f,"gu":%.1f,\
        "rt":%.1f,"ru":%.1f,"st":%.1f,"su":%.2f,"dr":%.1f,"dw":%.1f,"dt":%.1f,"df":%.1f,\
        "p":"%@","b":%d,"t":%.3f}
        """, s.cpuTemp, s.gpuTemp, s.cpuW, s.gpuW, s.allW, s.sysW, s.fan, s.fanCount,
             s.pFreq, s.eFreq, s.gFreq, s.cpuUsage, s.gpuUsage,
             rt, ru, st, su, d.readMB, d.writeMB, d.diskTotalGB, d.diskFreeGB,
             power as NSString, batt, Date().timeIntervalSince1970)
    }
}

extension Notification.Name {
    static let fuseTripped = Notification.Name("fuseTripped")
    static let burnStopped = Notification.Name("burnStopped")
        static let burnStarted = Notification.Name("burnStarted")
    static let burnStage = Notification.Name("burnStage")
    static let burnFinished = Notification.Name("burnFinished")
}

// MARK: - 磁盘监控（IOKit 累计字节差分 + statfs 容量）

final class DiskWatcher {
    static let shared = DiskWatcher()
    private(set) var readMB = 0.0, writeMB = 0.0
    private(set) var diskTotalGB = 0.0, diskFreeGB = 0.0
    private var lastRead: UInt64 = 0, lastWrite: UInt64 = 0
    private var lastT: CFAbsoluteTime = 0
    private var timer: Timer?
    private var started = false

    /// 累计读/写总量（GB），用于验机 / SSD 寿命估算
    var totalReadGB: Double { Double(lastRead) / 1e9 }
    var totalWriteGB: Double { Double(lastWrite) / 1e9 }

    func start() {
        guard !started else { return }
        started = true
        let (r, w) = ioBytes()
        lastRead = r; lastWrite = w; lastT = CFAbsoluteTimeGetCurrent()
        updateCapacity()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate(); timer = nil; started = false
    }

    private func tick() {
        let (r, w) = ioBytes()
        let now = CFAbsoluteTimeGetCurrent()
        let dt = max(now - lastT, 0.1)
        readMB = Double(r >= lastRead ? r - lastRead : 0) / 1e6 / dt
        writeMB = Double(w >= lastWrite ? w - lastWrite : 0) / 1e6 / dt
        lastRead = r; lastWrite = w; lastT = now
        updateCapacity()
    }

    private func updateCapacity() {
        var s = statfs()
        guard statfs("/", &s) == 0 else { return }
        let total = UInt64(s.f_blocks) * UInt64(s.f_bsize)
        let free = UInt64(s.f_bavail) * UInt64(s.f_bsize)
        diskTotalGB = Double(total) / 1e9
        diskFreeGB = Double(free) / 1e9
    }

    private func ioBytes() -> (UInt64, UInt64) {
        var totalRead: UInt64 = 0, totalWrite: UInt64 = 0
        var iter: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return (0, 0) }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return (0, 0) }
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                if let r = stats["Bytes (Read)"] as? NSNumber { totalRead += r.uint64Value }
                if let w = stats["Bytes (Write)"] as? NSNumber { totalWrite += w.uint64Value }
            }
            IOObjectRelease(svc)
            svc = IOIteratorNext(iter)
        }
        IOObjectRelease(iter)
        return (totalRead, totalWrite)
    }
}

final class MachineHolder {
    static let shared = MachineHolder()
    let machine = Machine()
}

// MARK: - GPU 压测（Metal，进程内）

final class GPUBurn {
    private var pipeline: MTLComputePipelineState?
    private var queue: MTLCommandQueue?
    private var outBuf: MTLBuffer?
    private var prepared = false
    private var running = false
    private var paused = false
    private var iters: UInt32 = 400000
    var supported: Bool { prepare() }

    private func prepare() -> Bool {
        if prepared { return pipeline != nil }
        prepared = true
        guard let dev = MTLCreateSystemDefaultDevice() else { return false }
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void burn(device float *out [[buffer(0)]],
                         constant uint &iters [[buffer(1)]],
                         uint id [[thread_position_in_grid]]) {
            float a = float(id) * 0.00001f + 1.0f;
            float b = 1.0000001f;
            float c = 0.0000001f;
            for (uint i = 0; i < iters; i++) {
                a = fma(a, b, c);
                b = fma(b, a, c);
                a = a * b + c;
                b = b * a - c;
            }
            out[id & 1023] = a + b;
        }
        """
        guard let lib = try? dev.makeLibrary(source: src, options: nil),
              let fn = lib.makeFunction(name: "burn"),
              let pipe = try? dev.makeComputePipelineState(function: fn) else { return false }
        pipeline = pipe
        queue = dev.makeCommandQueue()
        outBuf = dev.makeBuffer(length: 4096, options: .storageModeShared)
        return true
    }

    func set(active v: Bool) {
        if v && !running {
            running = true
            DispatchQueue.global(qos: .default).async { self.loop() }
        } else if !v {
            running = false
        }
    }
    func set(paused v: Bool) { paused = v }

    private func loop() {
        guard prepare(), let pipe = pipeline, let q = queue, let out = outBuf else { return }
        let tpg = min(pipe.maxTotalThreadsPerThreadgroup, 512)
        while running {
            if paused { Thread.sleep(forTimeInterval: 0.05); continue }
            autoreleasepool {
                guard let cb = q.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return }
                enc.setComputePipelineState(pipe)
                enc.setBuffer(out, offset: 0, index: 0)
                enc.setBytes(&iters, length: MemoryLayout<UInt32>.size, index: 1)
                enc.dispatchThreads(MTLSize(width: 16384, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: tpg, height: 1, depth: 1))
                enc.endEncoding()
                cb.commit()
            }
        }
    }
}

// MARK: - CPU / 内存 / 磁盘 压测线s

final class BurnThread: Thread {
    var running = true
    var paused = false
    var enabled = true        // 阶梯模式用来逐个唤醒
    let idx: Int
    init(idx: Int) { self.idx = idx; super.init() }

    override func main() {
        // 四条独立 FMA 链交错，喂饱 P 核的全部 SIMD 执行端口
        var a0 = SIMD4<Float>(1.000001, 1.000002, 1.000003, 1.000004)
        var a1 = SIMD4<Float>(1.000005, 1.000006, 1.000007, 1.000008)
        var a2 = SIMD4<Float>(1.000009, 1.000010, 1.000011, 1.000012)
        var a3 = SIMD4<Float>(1.000013, 1.000014, 1.000015, 1.000016)
        let b = SIMD4<Float>(repeating: 1.0000001)
        let c = SIMD4<Float>(repeating: 0.0000001)
        let n = 8_000_000                       // 32MB / 线程，超出 L2/SLC
        var buf = [Float](repeating: 0.0001, count: n)
        var i = 0
        qualityOfService = .default

        while running {
            if paused || !enabled { Thread.sleep(forTimeInterval: 0.05); continue }
            for _ in 0..<1500 {
                a0 = a0 * b + c
                a1 = a1 * b - c
                a2 = a2 * b + c
                a3 = a3 * b - c
                a0 = a0 * b - c
                a1 = a1 * b + c
                a2 = a2 * b - c
                a3 = a3 * b + c
            }
            i = (i + 4096) % n
            buf[i] += a0.x + a1.x + a2.x + a3.x
        }
    }
}

final class MemThread: Thread {
    var running = true
    var paused = false
    override func main() {
        let total = Double(sysctlString("hw.memsize")) ?? 8_589_934_592
        let size = Int(min(total * 0.15, 2_147_483_648))
        var buf = [UInt8](repeating: 0, count: size)
        let step = 512
        qualityOfService = .utility
        while running {
            if paused { Thread.sleep(forTimeInterval: 0.05); continue }
            var i = 0
            while i < size {
                buf[i] = buf[i] &+ 1
                i += step
            }
        }
    }
}

final class IOThread: Thread {
    var running = true
    var paused = false
    override func main() {
        let dir = NSTemporaryDirectory() + "roastbench"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let file = dir + "/io.bin"
        let chunk = [UInt8](repeating: 7, count: 1024 * 1024)
        qualityOfService = .utility
        while running {
            if paused { Thread.sleep(forTimeInterval: 0.05); continue }
            autoreleasepool {
                if FileManager.default.createFile(atPath: file, contents: nil) {
                    if let h = FileHandle(forWritingAtPath: file) {
                        for _ in 0..<300 { h.write(Data(chunk)) }
                        try? h.synchronize()
                        try? h.close()
                    }
                }
                if let r = FileHandle(forReadingAtPath: file) {
                    while (try? r.read(upToCount: 1024 * 1024))?.isEmpty == false {}
                    try? r.close()
                }
                try? FileManager.default.removeItem(atPath: file)
            }
        }
    }
}

// MARK: - 压测总控

struct ModeConfig {
    var cpu: Bool, gpu: Bool, mem: Bool, io: Bool
    var ratio: Double = 1.0
    var pulse: (Int, Int)? = nil
    var ramp: Bool = false          // 阶梯：每 20s 加一档
    var thermo: Bool = false        // 恒温闭环
}

final class Burner {
    static let shared = Burner()

    static let modes: [String: ModeConfig] = [
        "max":     ModeConfig(cpu: true,  gpu: true,  mem: true,  io: true),
        "cpu":     ModeConfig(cpu: true,  gpu: false, mem: true,  io: false),
        "gpu":     ModeConfig(cpu: false, gpu: true,  mem: false, io: false),
        "mem":     ModeConfig(cpu: false, gpu: false, mem: true,  io: false),
        "io":      ModeConfig(cpu: false, gpu: false, mem: false, io: true),
        "pulse":   ModeConfig(cpu: true,  gpu: true,  mem: false, io: false, pulse: (45, 15)),
        "passive": ModeConfig(cpu: true,  gpu: false, mem: false, io: false, ratio: 0.5),
        "battery": ModeConfig(cpu: true,  gpu: true,  mem: true,  io: true),
        "step":    ModeConfig(cpu: true,  gpu: true,  mem: false, io: false, ramp: true),
        "thermo":  ModeConfig(cpu: true,  gpu: true,  mem: false, io: false, thermo: true),
    ]

    private(set) var running = false
    private(set) var mode = "max"
    private(set) var startedAt = Date()
    private(set) var launched: [String] = []
    private(set) var paused = false

    var durationLimit: Double = 0      // 秒，0 = 手动
    var targetTemp: Double = 95        // 恒温目标
    var threadOverride: Int = 0        // 0 = 按模式自动

    private var cpuThreads: [BurnThread] = []
    private var memThreads: [MemThread] = []
    private var ioThreads: [IOThread] = []
    private var pulseThread: Thread?
    private var controlThread: Thread?
    private let gpu = GPUBurn()
    private var sleepAssertion: IOPMAssertionID = 0
    private var hasAssertion = false

    func gpuSupported() -> Bool { gpu.supported }

    func start(mode m: String, ncpu: Int) -> [String] {
        guard !running else { return [] }
        guard let cfg = Burner.modes[m] else { return [] }
        mode = m
        launched = []
        paused = false

        if cfg.cpu {
            let threads = threadOverride > 0 ? threadOverride : max(1, Int((Double(ncpu) * cfg.ratio).rounded(.up)))
            for i in 0..<threads {
                let t = BurnThread(idx: i)
                t.stackSize = 1 << 21
                if cfg.ramp { t.enabled = (i == 0) }
                cpuThreads.append(t)
                t.start()
            }
            launched.append("cpu x\(threads)")
        }
        if cfg.gpu && gpu.supported {
            gpu.set(active: true)
            launched.append("gpu")
        }
        if cfg.mem {
            let t = MemThread(); memThreads.append(t); t.start(); launched.append("mem")
        }
        if cfg.io {
            let t = IOThread(); ioThreads.append(t); t.start(); launched.append("io")
        }
        if let (on, off) = cfg.pulse {
            let t = Thread { [weak self] in
                guard let self = self else { return }
                while self.running {
                    Thread.sleep(forTimeInterval: Double(on))
                    if !self.running { break }
                    self.setPaused(true)
                    Thread.sleep(forTimeInterval: Double(off))
                    if !self.running { break }
                    self.setPaused(false)
                }
            }
            t.qualityOfService = .utility
            pulseThread = t
            t.start()
            launched.append("pulse \(on)/\(off)")
        }
        if cfg.ramp {
            let t = Thread { [weak self] in
                guard let self = self else { return }
                let total = self.cpuThreads.count
                for stage in 1...10 {
                    if !self.running { break }
                    let active = max(1, Int((Double(total) * Double(stage) / 10.0).rounded(.up)))
                    for (i, th) in self.cpuThreads.enumerated() { th.enabled = i < active }
                    NotificationCenter.default.post(name: .burnStage, object: stage)
                    // 每档 20 秒
                    for _ in 0..<200 { if !self.running { break }; Thread.sleep(forTimeInterval: 0.1) }
                }
            }
            t.qualityOfService = .utility
            controlThread = t
            t.start()
            launched.append("ramp 10档")
        }
        if cfg.thermo {
            let t = Thread { [weak self] in
                guard let self = self else { return }
                while self.running {
                    let cur = Metrics.shared.latest?.cpuTemp ?? 0
                    if cur > self.targetTemp {
                        self.setPaused(true)
                    } else if cur < self.targetTemp - 0.6 {
                        self.setPaused(false)
                    }
                    Thread.sleep(forTimeInterval: 0.2)
                }
                self.setPaused(false)
            }
            t.qualityOfService = .utility
            controlThread = t
            t.start()
            launched.append("thermo \(Int(targetTemp))°C")
        }

        // 防睡眠：烤机期间不允许系统休眠
        if !hasAssertion {
            let name = "烤机台压测中" as CFString
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                name, &sleepAssertion)
            hasAssertion = (r == kIOReturnSuccess)
        }

        running = true
        startedAt = Date()
        if durationLimit > 0 {
            let limit = durationLimit
            DispatchQueue.main.asyncAfter(deadline: .now() + limit) { [weak self] in
                guard let self = self, self.running else { return }
                NotificationCenter.default.post(name: .burnStopped, object: nil)
                NotificationCenter.default.post(name: .burnFinished, object: nil)
            }
        }
        return launched
    }

    func setPaused(_ v: Bool) {
        guard paused != v else { return }
        paused = v
        cpuThreads.forEach { $0.paused = v }
        memThreads.forEach { $0.paused = v }
        ioThreads.forEach { $0.paused = v }
        gpu.set(paused: v)
    }

    func stop() {
        guard running else { return }
        running = false
        paused = false
        cpuThreads.forEach { $0.paused = false; $0.running = false }
        memThreads.forEach { $0.paused = false; $0.running = false }
        ioThreads.forEach { $0.paused = false; $0.running = false }
        cpuThreads = []
        memThreads = []
        ioThreads = []
        pulseThread = nil
        controlThread = nil
        gpu.set(paused: false)
        gpu.set(active: false)
        if hasAssertion {
            IOPMAssertionRelease(sleepAssertion)
            hasAssertion = false
        }
    }

    func elapsed() -> Double { -startedAt.timeIntervalSinceNow }
}

// MARK: - 自定义 URL scheme

final class SchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFinish(); return }
        let rel = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // 自定义壁纸：roast://wallpaper
        if rel == "wallpaper" || rel.hasPrefix("wallpaper.") {
            let data = wallpaperFilePath().flatMap { try? Data(contentsOf: $0) }
            let status = (data?.isEmpty == false) ? 200 : 404
            let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "image/jpeg", "Cache-Control": "no-cache"])!
            task.didReceive(resp)
            if let data = data, !data.isEmpty { task.didReceive(data) }
            task.didFinish()
            return
        }

        var ext = (rel as NSString).pathExtension
        var base = (rel as NSString).deletingPathExtension
        if base.isEmpty { base = "index"; ext = "html" }

        let fileURL = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "ui")
        let data = fileURL.flatMap { try? Data(contentsOf: $0) }

        let mime: String
        switch ext {
        case "js": mime = "application/javascript"
        case "css": mime = "text/css"
        case "ico": mime = "image/x-icon"
        default: mime = "text/html"
        }
        let status = (data?.isEmpty == false) ? 200 : 404
        let resp = HTTPURLResponse(url: url, statusCode: status,
                                   httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime + "; charset=utf-8"])!
        task.didReceive(resp)
        if let data = data, !data.isEmpty {
            task.didReceive(data)
        }
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - 主窗口

final class MainController: NSViewController, WKScriptMessageHandler {
    private var webView: WKWebView!
    private let viewLoadedFlag = NSLock()
    private var pageReady = false
    private var pendingPush: [String] = []
    private var appearanceObs: NSKeyValueObservation?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1180, height: 760))

        // 原生毛玻璃底
        let effect = NSVisualEffectView(frame: root.bounds)
        effect.material = .windowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        root.addSubview(effect)

        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(SchemeHandler(), forURLScheme: "roast")
        cfg.userContentController.add(self, name: "api")

        let wv = WKWebView(frame: root.bounds, configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        wv.allowsBackForwardNavigationGestures = false
        root.addSubview(wv)
        webView = wv

        Metrics.shared.onSample = { [weak self] s in
            let (src, pct) = PowerWatcher.cached()
            self?.push(Metrics.json(s, power: src, batt: pct))
        }
        Metrics.shared.onUnavailable = { [weak self] in
            self?.eval("window.__metricsUnavailable && window.__metricsUnavailable()")
        }

        PowerWatcher.onChange = { [weak self] src, pct in
            MachineHolder.shared.machine.setPower(src)
            self?.eval("window.__power && window.__power('\(src)',\(pct))")
        }

        NotificationCenter.default.addObserver(forName: .fuseTripped, object: nil, queue: .main) { [weak self] n in
            guard let t = n.object as? Double else { return }
            Burner.shared.stop()
            self?.eval("window.__note && window.__note('温度保险丝触发：\(Int(t))°C，已自动收手')")
            self?.eval("window.__stopped && window.__stopped(false)")
        }
        NotificationCenter.default.addObserver(forName: .burnStopped, object: nil, queue: .main) { [weak self] _ in
            Burner.shared.stop()
            self?.eval("window.__stopped && window.__stopped(true)")
        }
        NotificationCenter.default.addObserver(forName: .burnStage, object: nil, queue: .main) { [weak self] n in
            if let st = n.object as? Int {
                self?.eval("window.__stage && window.__stage(\(st))")
            }
        }
        NotificationCenter.default.addObserver(forName: .burnFinished, object: nil, queue: .main) { _ in
            let content = UNMutableNotificationContent()
            content.title = "烤机完成"
            content.body = "这一轮结束了，成绩单已经生成。"
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req) { _ in }
        }
        NotificationCenter.default.addObserver(forName: .burnStarted, object: nil, queue: .main) { [weak self] _ in
            self?.eval("window.__started && window.__started('\(Burner.shared.mode)')")
        }

        NotificationCenter.default.addObserver(forName: .uiAction, object: nil, queue: .main) { [weak self] n in
            guard let a = n.object as? String else { return }
            switch a {
            case "start":
                self?.eval("window.__uiStart && window.__uiStart()")
            case "stop":
                self?.eval("window.__uiStop && window.__uiStop()")
            case "show":
                NSApp.activate(ignoringOtherApps: true)
                self?.view.window?.makeKeyAndOrderFront(nil)
            default:
                if a.hasPrefix("mode:") {
                    let m = String(a.dropFirst(5))
                    self?.eval("window.__setMode && window.__setMode('\(m)')")
                }
            }
        }

        PowerWatcher.start()
        Metrics.shared.start()
        DiskWatcher.shared.start()

        // 系统主题一变，立刻告诉页面（配合 CSS token 切换）
        appearanceObs = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.pushTheme() }
        }

        // 后台补全机型营销名，好了推给页面
        MachineHolder.shared.machine.refreshNameAsync { [weak self] in
            let i = MachineHolder.shared.machine.info
            self?.eval("window.__inforefresh && window.__inforefresh(\(i.json))")
        }

        if let u = URL(string: "roast://app/index.html") {
            wv.load(URLRequest(url: u))
        }
        self.view = root
    }

    private func eval(_ js: String) {
        guard pageReady else { pendingPush.append(js); return }
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("[eval error] \(error.localizedDescription) :: \(js.prefix(160))")
            }
        }
    }

    private func push(_ sampleJSON: String) {
        eval("window.__tick && window.__tick(\(sampleJSON))")
    }

    func flushPending() {
        pageReady = true
        let items = pendingPush
        pendingPush = []
        items.forEach { eval($0) }
    }

    // MARK: 消息桥
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return }
        // 页面第一次说话就说明它准备好了
        if !pageReady { pageReady = true; flushPending() }
        print("[bridge] op=\(op) ready=\(pageReady)")
        let id = body["id"] as? Int ?? 0

        switch op {
        case "ready":
            pageReady = true
            flushPending()
            eval("window.__ready && window.__ready()")

        case "info":
            let i = MachineHolder.shared.machine.info
            let gpuOK = Burner.shared.gpuSupported()
            let caps = """
            {"cpu":true,"gpu":\(gpuOK),"macmon":\(Metrics.shared.available),\
            "macmon_pending":\(Metrics.shared.gotFirst ? "false" : "true")}
            """
            notice(id, """
            {"ok":true,"info":\(i.json),"caps":\(caps),\
            "running":\(Burner.shared.running),"mode":"\(Burner.shared.mode)",\
            "started_at":\(Int(Burner.shared.startedAt.timeIntervalSince1970)),\
            "settings":\(Settings.shared.json)}
            """)

        case "start":
            let mode = body["mode"] as? String ?? "max"
            let launched = Burner.shared.start(mode: mode, ncpu: MachineHolder.shared.machine.info.ncpu)
            let list = launched.map { "\"\($0)\"" }.joined(separator: ",")
            notice(id, """
            {"ok":\(launched.isEmpty ? "false" : "true"),"launched":[\(list)],\
            "started_at":\(Int(Date().timeIntervalSince1970)),\
            "battery":\(PowerWatcher.percent())}
            """)
            eval("window.__started && window.__started('\(mode)')")

        case "stop":
            Burner.shared.stop()
            notice(id, "{\"ok\":true}")
            eval("window.__stopped && window.__stopped(true)")

        case "battery":
            notice(id, "{\"percent\":\(PowerWatcher.percent())}")

        case "jserror":
            print("[js error] \(body["msg"] ?? "?")")

        case "fuse":
            if let on = body["on"] as? Bool { Settings.shared.set("fuse", on) }
            notice(id, "{\"ok\":true}")

        case "set":
            let key = body["key"] as? String ?? ""
            if let v = body["value"] { Settings.shared.set(key, v) }
            if key == "theme" { Settings.shared.applyTheme() }
            if key == "interval" { Metrics.shared.restart() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.eval("window.__theme && window.__theme(\(Settings.shared.isDark()))")
            }
            notice(id, "{\"ok\":true,\"settings\":\(Settings.shared.json)}")

        case "restoreDefaults":
            Settings.shared.set("theme", "auto") ; Settings.shared.applyTheme()
            Settings.shared.set("fuse", true)
            Settings.shared.set("fuseTemp", 108)
            Settings.shared.set("interval", 250)
            Settings.shared.set("windowSec", 60)
            Settings.shared.set("defaultMode", "auto")
            Settings.shared.set("showPeak", true)
            Settings.shared.set("accent", "")
            Settings.shared.set("chartTheme", "apple")
            Settings.shared.set("wallpaper", "none")
            Settings.shared.clearCustomColors()
            Settings.shared.setDashboard("")
            Settings.shared.setGlassAlpha(72)
            Settings.shared.set("density", "standard")
            Settings.shared.set("sideWidth", 278)
            Settings.shared.set("radius", 14)
            Settings.shared.set("chartFill", true)
            Settings.shared.set("chartLine", 1.6)
            Settings.shared.set("lang", "auto")
            Settings.shared.set("fontSize", 13)
            Metrics.shared.restart()
            notice(id, "{\"ok\":true,\"settings\":\(Settings.shared.json)}")

        case "history":
            if let data = try? JSONSerialization.data(withJSONObject: Settings.shared.loadHistory()),
               let s = String(data: data, encoding: .utf8) {
                notice(id, "{\"ok\":true,\"history\":\(s)}")
            } else {
                notice(id, "{\"ok\":true,\"history\":[]}")
            }

        case "clearHistory":
            Settings.shared.clearHistory()
            notice(id, "{\"ok\":true}")

        case "saveRun":
            if let rec = body["record"] as? [String: Any] { Settings.shared.saveRun(rec) }
            notice(id, "{\"ok\":true}")

        case "export":
            let rows = body["rows"] as? [[String: Any]] ?? []
            self.saveCSV(rows)
            notice(id, "{\"ok\":true}")

        case "drag":
            if let w = webView.window, let e = NSApp.currentEvent { w.performDrag(with: e) }

        case "params":
            if let d = body["duration"] as? Double { Burner.shared.durationLimit = d }
            if let t = body["target"] as? Double { Burner.shared.targetTemp = t }
            if let n = body["threads"] as? Int { Burner.shared.threadOverride = n }
            notice(id, "{\"ok\":true}")

        case "pin":
            let on = body["on"] as? Bool ?? false
            webView.window?.level = on ? .floating : .normal
            notice(id, "{\"ok\":true}")

        case "compact":
            let on = body["on"] as? Bool ?? false
            self.setCompact(on)
            notice(id, "{\"ok\":true}")

        case "saveDashboard":
            if let j = body["json"] as? String { Settings.shared.setDashboard(j) }
            notice(id, "{\"ok\":true}")

        case "setGlass":
            if let v = body["value"] as? Int { Settings.shared.setGlassAlpha(v) }
            notice(id, "{\"ok\":true}")

        case "customColor":
            let k = body["key"] as? String ?? ""
            if k == "_reset" {
                Settings.shared.clearCustomColors()
            } else if let h = body["hex"] as? String {
                Settings.shared.setCustomColor(k, h)
            }
            notice(id, "{\"ok\":true,\"settings\":\(Settings.shared.json)}")

        case "pickWallpaper":
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.title = "选择壁纸图片"
            var ok = false
            if panel.runModal() == .OK, let url = panel.url,
               let data = try? Data(contentsOf: url), let dest = wallpaperFilePath() {
                try? data.write(to: dest)
                ok = true
            }
            notice(id, "{\"ok\":\(ok)}")
            if ok { self.eval("window.__wallpaperPicked && window.__wallpaperPicked()") }

        case "verify":
            DispatchQueue.global(qos: .utility).async {
                let v = self.collectVerify()
                DispatchQueue.main.async {
                    self.notice(id, "{\"ok\":true,\"verify\":\(v)}")
                }
            }

        case "hardware":
            DispatchQueue.global(qos: .utility).async {
                let df = shell("/bin/df", ["-h", "/"])
                var diskTotal = "—", diskFree = "—"
                let parts = df.components(separatedBy: "\n")
                if parts.count > 1 {
                    let cols = parts[1].split(separator: " ").filter { !$0.isEmpty }
                    if cols.count >= 4 { diskTotal = String(cols[1]); diskFree = String(cols[3]) }
                }
                let up = shell("/usr/bin/uptime", [])
                var uptime = "—"
                if let m = up.range(of: "up .*", options: .regularExpression) {
                    uptime = String(up[m]).replacingOccurrences(of: "up ", with: "")
                }
                var cycles = "—"
                let io = shell("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"])
                if let line = io.components(separatedBy: "\n").first(where: { $0.contains("CycleCount") }) {
                    if let r = line.range(of: #"= \d+"#, options: .regularExpression) {
                        cycles = String(line[r]).replacingOccurrences(of: "= ", with: "")
                    }
                }
                let hw = self.sysinfoJSON(diskTotal: diskTotal, diskFree: diskFree, uptime: uptime, cycles: cycles)
                DispatchQueue.main.async {
                    self.notice(id, "{\"ok\":true,\"hw\":\(hw)}")
                }
            }

        case "exportImage":
            if let b64 = body["data"] as? String, let data = Data(base64Encoded: b64) {
                self.savePNG(data)
            }
            notice(id, "{\"ok\":true}")

        case "loginItem":
            let on = body["on"] as? Bool ?? false
            do {
                if on { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                notice(id, "{\"ok\":true}")
            } catch {
                notice(id, "{\"ok\":false}")
            }

        default:
            notice(id, "{\"ok\":false}")
        }
    }

    private func setCompact(_ on: Bool) {
        guard let w = webView.window else { return }
        if on {
            w.minSize = NSSize(width: 360, height: 400)
            w.setFrame(NSRect(x: w.frame.origin.x, y: w.frame.origin.y + w.frame.height - 470,
                              width: 400, height: 470), display: true, animate: true)
        } else {
            w.minSize = NSSize(width: 980, height: 660)
            w.setFrame(NSRect(x: w.frame.origin.x, y: w.frame.origin.y, width: 1160, height: 760),
                       display: true, animate: true)
        }
    }

    private func savePNG(_ data: Data) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "烤机台成绩单.png"
            panel.allowedFileTypes = ["png"]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    private func sysinfoJSON(diskTotal: String, diskFree: String, uptime: String, cycles: String) -> String {
        let i = MachineHolder.shared.machine.info
        return """
        {"model":"\(jsonEscape(i.displayName))","id":"\(i.modelId)","chip":"\(jsonEscape(i.chip))",\
        "gpu":"\(jsonEscape(i.gpu))","cores":\(i.ncpu),"pcores":\(i.pcores),"ecores":\(i.ecores),\
        "ram":"\(i.memoryGB) GB","macos":"\(i.macos)","disk_total":"\(diskTotal)","disk_free":"\(diskFree)",\
        "uptime":"\(jsonEscape(uptime))","cycles":"\(cycles)","power":"\(i.power)"}
        """
    }

    /// 验机采集：电池健康 / 磁盘读写寿命 / 序列号 / 配置
    private func collectVerify() -> String {
        let i = MachineHolder.shared.machine.info

        var cycle = -1, health = -1, design = 0, full = 0
        var condition = "—"
        let power = shell("/usr/sbin/system_profiler", ["SPPowerDataType"])
        if let r = power.range(of: #"Cycle Count:\s*(\d+)"#, options: .regularExpression) {
            cycle = Int(String(power[r]).components(separatedBy: ":").last!.trimmingCharacters(in: .whitespaces)) ?? -1
        }
        if let r = power.range(of: #"Maximum Capacity:\s*(\d+)"#, options: .regularExpression) {
            health = Int(String(power[r]).components(separatedBy: ":").last!.trimmingCharacters(in: .whitespaces)) ?? -1
        }
        if let r = power.range(of: #"Condition:\s*(\w+)"#, options: .regularExpression) {
            condition = String(power[r]).components(separatedBy: ":").last!.trimmingCharacters(in: .whitespaces)
        }
        let batt = shell("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"])
        if let r = batt.range(of: #""DesignCapacity"=(\d+)"#, options: .regularExpression) {
            design = Int(batt[r].components(separatedBy: "=").last!.trimmingCharacters(in: .whitespaces)) ?? 0
        }
        if let r = batt.range(of: #""FullChargeCapacity"=(\d+)"#, options: .regularExpression) {
            full = Int(batt[r].components(separatedBy: "=").last!.trimmingCharacters(in: .whitespaces)) ?? 0
        }

        var serial = "—"
        let expert = shell("/usr/sbin/ioreg", ["-rd1", "-c", "IOPlatformExpertDevice"])
        if let r = expert.range(of: #""IOPlatformSerialNumber" = ""#) {
            let after = expert[r.upperBound...]
            if let end = after.firstIndex(of: "\"") { serial = String(after[..<end]) }
        }

        let dr = Int(DiskWatcher.shared.totalReadGB.rounded())
        let dw = Int(DiskWatcher.shared.totalWriteGB.rounded())

        return """
        {"serial":"\(jsonEscape(serial))",\
        "battery":{"cycle":\(cycle),"health":\(health),"condition":"\(jsonEscape(condition))","design":\(design),"full":\(full)},\
        "disk":{"read_gb":\(dr),"write_gb":\(dw)},\
        "model":"\(jsonEscape(i.displayName))","chip":"\(jsonEscape(i.chip))","gpu":"\(jsonEscape(i.gpu))",\
        "ram":\(i.memoryGB),"macos":"\(i.macos)","cores":\(i.ncpu),"pcores":\(i.pcores),"ecores":\(i.ecores)}
        """
    }

    private func pushTheme() {
        eval("window.__theme && window.__theme(\(Settings.shared.isDark()))")
    }

    private func saveCSV(_ rows: [[String: Any]]) {
        guard rows.count > 1 else { return }
        let keys = rows[0].keys.sorted()
        var csv = keys.joined(separator: ",") + "\n"
        for r in rows {
            csv += keys.map { String(describing: r[$0] ?? "") }.joined(separator: ",") + "\n"
        }
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "烤机台数据.csv"
            panel.allowedFileTypes = ["csv"]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func notice(_ id: Int, _ json: String) {
        eval("window.__reply && window.__reply(\(id),\(json))")
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Settings.shared.applyTheme()
        NSApp.applicationIconImage = IconFactory.make()
        buildMenu()

        let frame = NSRect(x: 0, y: 0, width: 1200, height: 780)
        let win = NSWindow(contentRect: frame,
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "烤机台"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.backgroundColor = .clear
        win.isOpaque = false
        win.minSize = NSSize(width: 980, height: 660)
        win.setFrameAutosaveName("RoastBenchMain")
        win.center()
        win.contentViewController = MainController()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        StatusBarController.shared.install()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // 调试钩子：ROAST_AUTOSTART=1 时启动即自动开烤
        if ProcessInfo.processInfo.environment["ROAST_AUTOSTART"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                _ = Burner.shared.start(mode: "max", ncpu: MachineHolder.shared.machine.info.ncpu)
            }
            NotificationCenter.default.post(name: .burnStarted, object: nil)
            if let t = ProcessInfo.processInfo.environment["ROAST_AUTOSTOP"], let d = Double(t) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3 + d) {
                    NotificationCenter.default.post(name: .burnStopped, object: nil)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Burner.shared.stop()
        Metrics.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于烤机台", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出烤机台", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "全选", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a"))
        edit.submenu = editMenu
        menu.addItem(edit)
        NSApp.mainMenu = menu
    }
}

setbuf(stdout, nil)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
