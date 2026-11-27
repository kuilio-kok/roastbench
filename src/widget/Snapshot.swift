import Foundation

// MARK: - 主 App 写的快照
// 小组件扩展是沙盒进程（WidgetKit 只跑沙盒 appex），拿不到 SMC / macmon 的温度功耗。
// 所以主 App 每 2 秒把当前数据写进扩展自己的容器，扩展从自己容器里读 —— 这是
// 「非沙盒宿主 + 沙盒扩展」最稳的共享方式，不需要 App Group，也不需要任何证书。
enum Snapshot {
    static let widgetBundleID = "cn.wangchuanhe.roastbench.widget"
    static let fileName = "widget-snapshot.json"

    /// 扩展侧路径：沙盒里 NSHomeDirectory() 就是容器 Data 目录
    static var containerPath: String {
        NSHomeDirectory() + "/Library/Application Support/" + fileName
    }

    /// 宿主侧路径：直接构造扩展的容器绝对路径
    static var hostPath: String {
        containerRoot + "/Data/Library/Application Support/" + fileName
    }

    /// 扩展的沙盒容器根目录（扩展第一次跑之前不存在）
    static var containerRoot: String {
        NSHomeDirectory() + "/Library/Containers/" + widgetBundleID
    }

    struct Snap {
        var ts: Double = 0
        var cpuTemp: Double = 0
        var gpuTemp: Double = 0
        var power: Double = 0
        var fan: Double = 0
        var cpu: Double = 0
        var gpu: Double = 0
        var ramUsed: Double = 0
        var ramTotal: Double = 0
        var swapUsed: Double = 0
        var swapTotal: Double = 0
        var diskFree: Double = 0
        var diskTotal: Double = 0
        var battery: Double = 0
        var charging = ""

        var percent: Double { ramTotal > 0 ? min(max(ramUsed / ramTotal, 0), 1) : 0 }
        var fresh: Bool { ts > 0 && Date().timeIntervalSince1970 - ts < 600 }
    }

    /// 扩展侧：读自己容器里的快照
    static func load() -> Snap? {
        guard let raw = try? String(contentsOfFile: containerPath, encoding: .utf8),
              let d = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        var s = Snap()
        func num(_ k: String) -> Double { (obj[k] as? NSNumber)?.doubleValue ?? 0 }
        s.ts = num("t")
        s.cpuTemp = num("ct"); s.gpuTemp = num("gt")
        s.power = num("aw"); s.fan = num("fan")
        s.cpu = num("cu"); s.gpu = num("gu")
        s.ramUsed = num("ru") * 1e9; s.ramTotal = num("rt") * 1e9
        s.swapUsed = num("su") * 1e9; s.swapTotal = num("st") * 1e9
        s.diskFree = num("df"); s.diskTotal = num("dt")
        s.battery = num("b")
        s.charging = obj["p"] as? String ?? ""
        return s.fresh ? s : nil
    }
}
