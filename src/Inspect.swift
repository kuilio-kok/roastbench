import Foundation
import AppKit
import IOKit

// MARK: - 整机信息 / 验机报告采集
//
// 一次性把本机"能查到的硬件与安全信息"采集齐，分块输出给前端渲染。
// 所有数据源均为系统只读命令，不写盘、不改配置。

enum Inspector {

    // MARK: 报告数据模型

    struct Item {
        let k: String
        let v: String
        var level: String = "info"      // info / ok / warn / bad
        var note: String = ""

        var json: String {
            "{\"k\":\"\(jsonEscape(k))\",\"v\":\"\(jsonEscape(v))\",\"level\":\"\(level)\",\"note\":\"\(jsonEscape(note))\"}"
        }
    }

    struct Section {
        let id: String
        let title: String
        let sub: String
        var items: [Item]

        var json: String {
            let body = items.map { $0.json }.joined(separator: ",")
            return "{\"id\":\"\(id)\",\"title\":\"\(jsonEscape(title))\",\"sub\":\"\(jsonEscape(sub))\",\"items\":[\(body)]}"
        }
    }

    /// 最近一次采集结果，供导出使用
    private(set) static var lastSections: [Section] = []
    private(set) static var lastJSON: String = ""
    private(set) static var lastText: String = ""
    private(set) static var lastTime: Date = Date()

    // MARK: 轻量解析工具

    private static func str(_ any: Any?) -> String {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let a as [Any]: return a.compactMap { str($0) }.joined(separator: ", ")
        case let d as [String: Any]: return str(d["_name"])
        default: return ""
        }
    }

    private static func dict(_ any: Any?) -> [String: Any] {
        any as? [String: Any] ?? [:]
    }

    private static func list(_ any: Any?) -> [[String: Any]] {
        any as? [[String: Any]] ?? []
    }

    /// 正则取第一个捕获组
    private static func match(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group else { return nil }
        let r = m.range(at: group)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
    }

    /// ioreg 里的十六进制字符串（<7436303030...>）还原成文本
    private static func hexText(_ raw: String) -> String {
        let t = raw.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
        var bytes: [UInt8] = []
        var i = t.startIndex
        while let j = t.index(i, offsetBy: 2, limitedBy: t.endIndex) {
            if let b = UInt8(t[i..<j], radix: 16) { bytes.append(b) }
            i = j
        }
        let trimmed = bytes.prefix { $0 != 0 }
        return String(bytes: trimmed, encoding: .utf8) ?? ""
    }

    private static func fileBirth(_ path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let d = attrs[.creationDate] as? Date else { return nil }
        return d
    }

    private static func fmtDate(_ d: Date?) -> String {
        guard let d = d else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    /// 去掉 system_profiler 内部枚举前缀（spdisplays_built-in-liquid-retina-xdr → Built-in Liquid Retina XDR）
    private static func prettyEnum(_ raw: String, prefix: String) -> String {
        var s = raw
        if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        s = s.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        guard !s.isEmpty else { return "—" }
        let known = ["built in liquid retina xdr": "内置 Liquid Retina XDR",
                     "built in retina": "内置 Retina 显示屏"]
        let low = s.lowercased()
        if let hit = known.first(where: { low.contains($0.key) }) { return hit.value }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    // MARK: 采集

    static func collect() -> String {
        let started = Date()
        let info = MachineHolder.shared.machine.info

        // ① 一次性拿到所有 system_profiler 数据（JSON 输出，省掉本地化文本解析）
        let types = ["SPHardwareDataType", "SPMemoryDataType", "SPStorageDataType",
                     "SPNVMeDataType", "SPPowerDataType", "SPDisplaysDataType",
                     "SPCameraDataType", "SPAirPortDataType"]
        let raw = shell("/usr/sbin/system_profiler", ["-json"] + types)
        let sp = (try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: [])) as? [String: Any] ?? [:]

        let hw = dict(list(sp["SPHardwareDataType"]).first)
        let mem = dict(list(sp["SPMemoryDataType"]).first)
        let storage = list(sp["SPStorageDataType"])
        let nvmeRoot = dict(list(sp["SPNVMeDataType"]).first)
        let nvme = dict(list(nvmeRoot["_items"]).first)
        let power = list(sp["SPPowerDataType"])
        let battInfo = dict(power.first { str($0["_name"]) == "spbattery_information" })
        let disp = dict(list(sp["SPDisplaysDataType"]).first)
        let cams = list(sp["SPCameraDataType"])
        let wifi = dict(list(dict(list(sp["SPAirPortDataType"]).first)["spairport_airport_interfaces"]).first)

        // 根卷（挂载点 /）容量信息
        let rootVol = dict(storage.first { str($0["mount_point"]) == "/" })

        // ② 平台层：平台标识 / 主板序列号 / 监管型号
        let plat = shell("/usr/sbin/ioreg", ["-c", "IOPlatformExpertDevice", "-d", "2"])
        let platformHex = match(#""platform-name" = <([0-9a-fA-F]+)>"#, in: plat) ?? ""
        let platformRaw = hexText(platformHex)
        let platformId = platformRaw.isEmpty ? "—" : "ARM64_" + platformRaw.uppercased()
        let boardSerial = hexText(match(#""mlb-serial-number" = <([0-9a-fA-F]+)>"#, in: plat) ?? "")
        let regModel = hexText(match(#""regulatory-model-number" = <([0-9a-fA-F]+)>"#, in: plat) ?? "")
        let targetType = hexText(match(#""target-type" = <([0-9a-fA-F]+)>"#, in: plat) ?? "")
        let productName = match(#""product-name" = <"([^"]+)">"#, in: plat) ?? ""

        // ③ 屏幕面板：面板 ID + True Tone 校准
        // 面板 ID 与 True Tone 校准参数分散在不同节点上，-rn 过滤会漏，故取一次全量注册表
        let ioregAll = shell("/usr/sbin/ioreg", ["-l"])
        let panelId = match(#""Panel_ID" = "([^"]+)""#, in: ioregAll) ?? ""
        let trueTone = ioregAll.contains("truetone-shift-a") && ioregAll.contains("truetone-shift-b")

        // ④ 电池原始容量
        let smartBatt = shell("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"])
        let designCap = Int(match(#""DesignCapacity"=(\d+)"#, in: smartBatt) ?? "") ?? 0
        let fullCap = Int(match(#""FullChargeCapacity"=(\d+)"#, in: smartBatt) ?? "") ?? 0

        // ⑤ 安全状态
        let sip = shell("/usr/bin/csrutil", ["status"])
        let ssr = shell("/usr/bin/csrutil", ["authenticated-root", "status"])
        let fv = shell("/usr/bin/fdesetup", ["status"])
        let bio = shell("/usr/bin/bioutil", ["-r"])

        // ⑥ 系统版本 / 时间线
        let ver = ProcessInfo.processInfo.operatingSystemVersion
        let sysVer = "\(ver.majorVersion).\(ver.minorVersion).\(ver.patchVersion)"
        let build = shell("/usr/bin/sw_vers", ["-buildVersion"])
        let kernel = shell("/usr/bin/uname", ["-r"])
        let installDate = fileBirth("/System/Library/CoreServices/SystemVersion.plist")
        let setupDate = fileBirth("/var/db/.AppleSetupDone")
        let bootSec = TimeInterval(match(#"sec = (\d+)"#, in: sysctlString("kern.boottime")) ?? "") ?? 0
        let bootDate = bootSec > 0 ? Date(timeIntervalSince1970: bootSec) : nil

        // —— 取字段 ——
        let modelId = str(hw["machine_model"])
        let modelNumber = str(hw["model_number"])
        let serial = str(hw["serial_number"])
        let chip = str(hw["chip_type"])
        let cores = str(hw["number_processors"])
        let memory = str(hw["physical_memory"])
        let activationRaw = str(hw["activation_lock_status"])
        let gpuModel = str(disp["sppci_model"])
        let gpuCores = str(disp["sppci_cores"])
        let displays = list(disp["spdisplays_ndrvs"])
        let mainDisp = dict(displays.first)
        let displayType = prettyEnum(str(mainDisp["spdisplays_display_type"]), prefix: "spdisplays_")
        let pixelRes = str(mainDisp["_spdisplays_pixels"])
        let logicalRes = str(mainDisp["_spdisplays_resolution"])
        let vendorId = str(mainDisp["_spdisplays_display-vendor-id"])
        let productId = str(mainDisp["_spdisplays_display-product-id"])

        let battModel = dict(battInfo["sppower_battery_model_info"])
        let battHealth = dict(battInfo["sppower_battery_health_info"])
        let battCharge = dict(battInfo["sppower_battery_charge_info"])
        let battSerial = str(battModel["sppower_battery_serial_number"])
        let battChip = str(battModel["sppower_battery_device_name"])
        let battFw = str(battModel["sppower_battery_firmware_version"])
        let cycle = Int(str(battHealth["sppower_battery_cycle_count"])) ?? -1
        let healthPct = Int((str(battHealth["sppower_battery_health_maximum_capacity"])).replacingOccurrences(of: "%", with: "")) ?? -1
        let battState = str(battHealth["sppower_battery_health"])
        let socPct = Int(str(battCharge["sppower_battery_state_of_charge"])) ?? -1

        let ssdModel = str(nvme["device_model"]).isEmpty ? str(dict(rootVol["physical_drive"])["device_name"]) : str(nvme["device_model"])
        let ssdSize = str(nvme["size"])
        let ssdSerial = str(nvme["device_serial"])
        let ssdSmart = str(nvme["smart_status"])
        let ssdTrim = str(nvme["spnvme_trim_support"])
        let ssdRev = str(nvme["device_revision"])
        let ssdProtocol = str(dict(rootVol["physical_drive"])["protocol"])
        let freeBytes = (rootVol["free_space_in_bytes"] as? NSNumber)?.doubleValue ?? 0
        let totalBytes = (rootVol["size_in_bytes"] as? NSNumber)?.doubleValue ?? 0

        let wifiCard = str(wifi["spairport_wireless_card_type"])
        let wifiMac = str(wifi["spairport_wireless_mac_address"])
        let wifiPhy = str(wifi["spairport_supported_phymodes"])
        let wifiCountry = str(wifi["spairport_wireless_country_code"])
        let wifiFwRaw = str(wifi["spairport_wireless_firmware_version"])
        let wifiFw = match(#"version ([0-9][0-9.]*[0-9])"#, in: wifiFwRaw) ?? wifiFwRaw.components(separatedBy: "\n").first ?? ""

        var sections: [Section] = []

        // MARK: 一、整机身份
        var identity: [Item] = []
        let marketing = productName.isEmpty ? (MODEL_NAMES[modelId] ?? info.displayName) : productName
        identity.append(Item(k: "机型名称", v: marketing, level: "ok"))
        identity.append(Item(k: "型号标识符", v: modelId.isEmpty ? "—" : modelId,
                             note: "系统识别机型，官网核对保修以此为准"))
        if !modelNumber.isEmpty {
            identity.append(Item(k: "订购号 / 设备型号", v: modelNumber,
                                 note: modelNumber.hasPrefix("Z") ? "Z 开头为出厂定制（CTO）机型" : "标准零售机型"))
        }
        identity.append(Item(k: "监管型号", v: regModel.isEmpty ? "—" : regModel, note: "机身底部印制的 A 编号"))
        identity.append(Item(k: "系统序列号", v: serial.isEmpty ? "未读到" : serial,
                             level: serial.count >= 10 ? "ok" : "bad",
                             note: serial.count >= 10 ? "可在 Apple 官网查询保修与激活状态" : "长度异常，需人工核对"))
        identity.append(Item(k: "主板序列号", v: boardSerial.isEmpty ? "—" : boardSerial, note: "MLB，主板唯一标识"))
        identity.append(Item(k: "硬件 UUID", v: str(hw["platform_UUID"])))
        identity.append(Item(k: "配置 UDID", v: str(hw["provisioning_UDID"])))
        identity.append(Item(k: "SoC 平台标识",
                             v: platformId == "—" ? (chip.isEmpty ? "—" : chip) : "\(platformId)\(targetType.isEmpty ? "" : "（\(targetType)）")",
                             note: "芯片型号代号，换 SoC 会随之变化"))
        identity.append(Item(k: "芯片", v: chip.isEmpty ? info.chip : chip))

        var cpuDesc = "—"
        let parts = cores.replacingOccurrences(of: "proc ", with: "").components(separatedBy: ":")
        if parts.count == 4 {
            let total = Int(parts[0]) ?? 0, p = Int(parts[2]) ?? 0, e = Int(parts[3]) ?? 0
            cpuDesc = total > 0 ? "\(total) 核（\(p) 性能核 + \(e) 能效核）" : "\(info.ncpu) 核"
        } else if info.ncpu > 0 {
            cpuDesc = "\(info.ncpu) 核"
        }
        identity.append(Item(k: "CPU 核心", v: cpuDesc))
        identity.append(Item(k: "GPU", v: gpuModel.isEmpty ? "—" : (gpuCores.isEmpty ? gpuModel : "\(gpuModel) · \(gpuCores) 核")))
        identity.append(Item(k: "统一内存",
                             v: memory.isEmpty ? "\(info.memoryGB) GB" : memory,
                             note: [str(mem["dimm_type"]), str(mem["dimm_manufacturer"])].filter { !$0.isEmpty }.joined(separator: " · ")))
        identity.append(Item(k: "系统固件", v: str(hw["boot_rom_version"])))
        sections.append(Section(id: "identity", title: "整机身份", sub: "机型 · 序列号 · 芯片 · 内存", items: identity))

        // MARK: 二、存储
        var disk: [Item] = []
        var smartLevel = "ok"
        if !ssdSmart.isEmpty && ssdSmart.lowercased() != "verified" { smartLevel = "warn" }
        if ssdModel.isEmpty { smartLevel = "bad" }
        disk.append(Item(k: "SSD 型号", v: ssdModel.isEmpty ? "未读到" : ssdModel, level: ssdModel.isEmpty ? "bad" : "info"))
        disk.append(Item(k: "标称容量", v: ssdSize.isEmpty ? "—" : ssdSize))
        disk.append(Item(k: "SSD 序列号", v: ssdSerial.isEmpty ? "—" : ssdSerial, note: "换过硬盘时该值必然变化"))
        disk.append(Item(k: "固件版本", v: ssdRev.isEmpty ? "—" : ssdRev))
        disk.append(Item(k: "总线协议", v: ssdProtocol.isEmpty ? "—" : ssdProtocol))
        disk.append(Item(k: "SMART 状态", v: ssdSmart.isEmpty ? "未报告" : ssdSmart, level: smartLevel,
                         note: smartLevel == "ok" ? "硬盘自检通过" : "SMART 非 Verified，建议尽快备份并检测"))
        disk.append(Item(k: "TRIM", v: ssdTrim.isEmpty ? "—" : ssdTrim))
        if totalBytes > 0 {
            let totalGB = (totalBytes / 1_000_000_000 * 10).rounded() / 10
            let freeGB = (freeBytes / 1_000_000_000 * 10).rounded() / 10
            let usedPct = Int(((totalBytes - freeBytes) / totalBytes * 100).rounded())
            disk.append(Item(k: "根卷容量", v: "\(totalGB) GB", note: "可用 \(freeGB) GB · 已用 \(usedPct)%"))
        }
        disk.append(Item(k: "累计读写", v: "读 \(Int(DiskWatcher.shared.totalReadGB.rounded())) GB · 写 \(Int(DiskWatcher.shared.totalWriteGB.rounded())) GB",
                         note: "本次开机以来统计"))
        sections.append(Section(id: "storage", title: "存储", sub: "SSD 型号 · 容量 · SMART", items: disk))

        // MARK: 三、电池
        var battery: [Item] = []
        var battLevel = "ok"
        var battTag = "状态正常"
        if healthPct >= 0 {
            if healthPct < 70 { battLevel = "bad"; battTag = "建议更换" }
            else if healthPct < 85 { battLevel = "warn"; battTag = "正常损耗" }
        }
        if cycle > 1000 { battLevel = battLevel == "bad" ? "bad" : "warn"; battTag = "循环偏多" }
        if battSerial.isEmpty && battInfo.isEmpty == false { battLevel = "warn" }
        battery.append(Item(k: "电池序列号", v: battSerial.isEmpty ? "—" : battSerial, note: "与主板配套，换电池会变"))
        battery.append(Item(k: "电池控制器", v: battChip.isEmpty ? "—" : battChip))
        battery.append(Item(k: "电池固件", v: battFw.isEmpty ? "—" : battFw))
        battery.append(Item(k: "循环次数", v: cycle >= 0 ? "\(cycle) 次" : "—",
                            level: cycle > 1000 ? "warn" : "info",
                            note: cycle >= 0 && cycle < 100 ? "接近新机循环数" : ""))
        battery.append(Item(k: "健康度", v: healthPct >= 0 ? "\(healthPct)%" : "—", level: battLevel, note: battTag))
        battery.append(Item(k: "电池状态", v: battState.isEmpty ? "—" : battState,
                            level: battState.lowercased() == "normal" || battState.lowercased() == "good" ? "ok" : "warn"))
        battery.append(Item(k: "设计容量", v: designCap > 0 ? "\(designCap) mAh" : "—"))
        battery.append(Item(k: "当前满充容量", v: fullCap > 0 ? "\(fullCap) mAh" : "—"))
        if socPct >= 0 { battery.append(Item(k: "当前电量", v: "\(socPct)%", note: info.power == "ac" ? "外接电源" : "电池供电")) }
        sections.append(Section(id: "battery", title: "电池", sub: "循环 · 健康度 · 原厂标识", items: battery))

        // MARK: 四、显示屏
        var screen: [Item] = []
        screen.append(Item(k: "面板类型", v: displayType))
        screen.append(Item(k: "分辨率", v: pixelRes.isEmpty ? "—" : pixelRes, note: logicalRes.isEmpty ? "" : "逻辑分辨率 \(logicalRes)"))
        var panelShort = "—"
        if !panelId.isEmpty {
            let seg = panelId.components(separatedBy: "+")
            panelShort = seg.count > 2 ? seg[0] + "…" + seg[1].prefix(8) : String(panelId.prefix(28))
        }
        screen.append(Item(k: "面板 ID", v: panelShort, note: "屏幕唯一标识，走过换屏会变化"))
        screen.append(Item(k: "屏厂 / 产品 ID", v: [vendorId, productId].filter { !$0.isEmpty }.joined(separator: " / ")))
        screen.append(Item(k: "True Tone 原彩显示", v: trueTone ? "支持（校准参数在位）" : "未检测到校准参数",
                           level: trueTone ? "ok" : "warn",
                           note: trueTone ? "屏幕总成带原厂校准，与当前主板匹配" : "若屏幕为原装却读不到，需人工核对"))
        screen.append(Item(k: "自动亮度", v: str(mainDisp["spdisplays_ambient_brightness"]).contains("yes") ? "已开启" : "关闭"))
        if displays.count > 1 {
            screen.append(Item(k: "外接显示器", v: "\(displays.count - 1) 台"))
        }
        sections.append(Section(id: "display", title: "显示屏", sub: "面板 ID · True Tone", items: screen))

        // MARK: 五、摄像头 / 无线
        var io: [Item] = []
        let builtinCam = cams.first { !str($0["_name"]).contains("iPhone") && !str($0["spcamera_model-id"]).hasPrefix("iPhone") }
        if let cam = builtinCam {
            io.append(Item(k: "内置摄像头", v: str(cam["spcamera_model-id"]), level: "ok"))
            io.append(Item(k: "摄像头标识", v: str(cam["spcamera_unique-id"]), note: "换过摄像头会变化"))
        } else {
            io.append(Item(k: "内置摄像头", v: "未检测到", level: "warn"))
        }
        let continuity = cams.filter { str($0["_name"]).contains("iPhone") }
        if !continuity.isEmpty {
            io.append(Item(k: "连续互通相机", v: "\(continuity.count) 台（\(continuity.compactMap { str($0["spcamera_model-id"]) }.joined(separator: ", "))）",
                           note: "手机投送，非本机部件"))
        }
        io.append(Item(k: "Wi-Fi 芯片", v: wifiChipName(wifiCard), level: wifiCard.isEmpty ? "warn" : "ok",
                       note: wifiCard.isEmpty ? "" : wifiCard))
        io.append(Item(k: "Wi-Fi MAC", v: wifiMac.isEmpty ? "—" : wifiMac, note: wifiMac.isEmpty ? "" : "硬件地址，换网卡会变化"))
        io.append(Item(k: "支持标准", v: wifiPhy.isEmpty ? "—" : wifiPhy))
        io.append(Item(k: "国家码 / 固件", v: [wifiCountry, wifiFw].filter { !$0.isEmpty }.joined(separator: " · ")))
        sections.append(Section(id: "io", title: "摄像头与无线", sub: "标识 · 芯片 · MAC", items: io))

        // MARK: 六、安全状态
        var sec: [Item] = []
        let sipOn = sip.contains("enabled")
        sec.append(Item(k: "SIP 系统完整性保护", v: sipOn ? "已启用" : "已关闭",
                        level: sipOn ? "ok" : "warn",
                        note: sipOn ? "" : "关闭状态常见于改机/破解机器，需留意"))
        let ssrOn = ssr.contains("enabled")
        sec.append(Item(k: "签名根卷", v: ssrOn ? "已启用" : "已关闭", level: ssrOn ? "ok" : "warn",
                        note: ssrOn ? "系统卷未被改动" : "系统卷可被改动，存在被篡改风险"))
        let lockOn = activationRaw.contains("enabled")
        let lockKnown = !activationRaw.isEmpty && !activationRaw.contains("unknown")
        sec.append(Item(k: "激活锁",
                        v: lockKnown ? (lockOn ? "已启用" : "未启用") : "无法确定",
                        level: lockOn ? "warn" : (lockKnown ? "ok" : "info"),
                        note: lockOn ? "仍绑定某个 Apple ID，二手购入必须先让卖家在「查找」中移除" : ""))
        let fvOn = fv.contains("On")
        sec.append(Item(k: "FileVault 磁盘加密", v: fvOn ? "已开启" : "未开启",
                        level: fvOn ? "ok" : "info",
                        note: fvOn ? "" : "新机默认未开启，不算异常"))
        let unlockOn = match(#"Effective biometrics for unlock: (\d)"#, in: bio) == "1"
        sec.append(Item(k: "Touch ID", v: unlockOn ? "已录入并生效" : (bio.isEmpty ? "无法读取" : "未录入"),
                        level: unlockOn ? "ok" : "info",
                        note: unlockOn ? "指纹存在 Secure Enclave 中，换主板会失效" : ""))
        sections.append(Section(id: "security", title: "安全状态", sub: "SIP · 激活锁 · 指纹", items: sec))

        // MARK: 七、系统与时间线
        var sys: [Item] = []
        sys.append(Item(k: "系统版本", v: "macOS \(sysVer)（\(build.isEmpty ? "—" : build)）", level: "ok"))
        sys.append(Item(k: "内核版本", v: kernel.isEmpty ? "—" : "Darwin \(kernel)"))
        sys.append(Item(k: "系统安装日期", v: fmtDate(installDate), note: "系统卷写入时间，大致等于装机时间"))
        sys.append(Item(k: "首次开机 / 初始化", v: fmtDate(setupDate), note: "开箱向导完成时间；若比系统安装早很多，说明重装过系统或是旧机"))
        sys.append(Item(k: "本次开机", v: fmtDate(bootDate)))
        if let boot = bootDate {
            let mins = Int(Date().timeIntervalSince(boot) / 60)
            sys.append(Item(k: "已运行", v: mins >= 60 ? "\(mins / 60) 小时 \(mins % 60) 分" : "\(mins) 分"))
        }
        if let install = installDate, let setup = setupDate, setup < install.addingTimeInterval(-86400 * 3) {
            sys.append(Item(k: "时间线核对", v: "首次开机早于系统安装",
                            level: "warn", note: "可能重装过系统，属正常操作，但要留意是否为翻新机"))
        }
        sections.append(Section(id: "system", title: "系统", sub: "版本 · 安装与首次开机", items: sys))

        // MARK: 八、原装性核对
        var check: [Item] = []
        // 机型 ↔ 芯片
        if let expect = CHIP_BY_MODEL[modelId] {
            let ok = expect.contains { chip.contains($0) }
            check.append(Item(k: "机型与芯片匹配", v: ok ? "一致（应为 \(expect.joined(separator: " / "))）" : "不一致（读到 \(chip)）",
                              level: ok ? "ok" : "bad",
                              note: ok ? "" : "机型与芯片不匹配，需重点核查"))
        } else {
            check.append(Item(k: "机型与芯片匹配", v: "机型未收录，需人工核对", level: "info"))
        }
        // 电池循环 ↔ 健康度
        if cycle > 0 && healthPct > 0 {
            if cycle < 50 && healthPct < 90 {
                check.append(Item(k: "电池数据自洽", v: "循环少但健康度偏低", level: "warn",
                                  note: "可能被重置过循环计数，建议进「部件与服务历史」核对电池"))
            } else if cycle > 400 && healthPct >= 99 {
                check.append(Item(k: "电池数据自洽", v: "循环多但健康度接近 100%", level: "warn",
                                  note: "健康度偏高得反常，留意电池是否被换过或数据被重置"))
            } else {
                check.append(Item(k: "电池数据自洽", v: "循环 \(cycle) 次 / 健康度 \(healthPct)%", level: "ok"))
            }
        }
        // 存储
        if !ssdModel.isEmpty {
            let onboard = ssdModel.uppercased().hasPrefix("APPLE SSD")
            check.append(Item(k: "存储是否为原厂", v: onboard ? "Apple 原厂 SSD" : "非 Apple 型号：\(ssdModel)",
                              level: onboard ? "ok" : "warn",
                              note: onboard ? "Apple Silicon 的 SSD 焊在主板，无法更换" : "第三方硬盘，需确认是否为外接或改装"))
        }
        // 内存
        let memVendor = str(mem["dimm_manufacturer"])
        check.append(Item(k: "内存", v: memVendor.isEmpty ? "统一内存（板载）" : "统一内存 · \(memVendor) 颗粒",
                          level: "ok", note: "Apple Silicon 内存封装在 SoC 内，无法更换"))
        // 激活锁与登录
        if lockOn {
            check.append(Item(k: "需要人工确认", v: "激活锁仍启用", level: "warn",
                              note: "必须让卖家在「查找」中移除设备，否则可能被远程锁机"))
        }
        // 换件记录入口
        check.append(Item(k: "部件与服务历史", v: "需在「系统信息」中查看", level: "info",
                          note: "命令行不暴露该数据，点击下方按钮可直接打开"))
        sections.append(Section(id: "check", title: "原装性核对", sub: "软件层能做的不拆机判断", items: check))

        // MARK: 汇总
        let all = sections.flatMap { $0.items }
        let badCount = all.filter { $0.level == "bad" }.count
        let warnCount = all.filter { $0.level == "warn" }.count
        let okCount = all.filter { $0.level == "ok" }.count

        let verdict = badCount > 0 ? "bad" : (warnCount > 0 ? "warn" : "good")
        let title = badCount > 0 ? "发现异常，需要核实" : (warnCount > 0 ? "整体可用，有 \(warnCount) 项需留意" : "未发现异常")
        let desc = badCount > 0
            ? "有 \(badCount) 项严重异常、\(warnCount) 项待留意，建议先核对再付款或收货。"
            : (warnCount > 0
               ? "硬件信息基本自洽，橙色条目建议逐条核对，必要时进「部件与服务历史」确认是否换过件。"
               : "所有可查项均正常，未发现换件或异常迹象。")

        lastSections = sections
        lastTime = Date()

        let timeText = fmtDate(started)
        let sectionsJSON = sections.map { $0.json }.joined(separator: ",")
        let summaryJSON = """
        {"verdict":"\(verdict)","title":"\(jsonEscape(title))","desc":"\(jsonEscape(desc))",\
        "ok":\(okCount),"warn":\(warnCount),"bad":\(badCount),"total":\(all.count),"time":"\(timeText)"}
        """
        lastJSON = "{\"summary\":\(summaryJSON),\"sections\":[\(sectionsJSON)]}"
        lastText = textReport(summary: summaryJSON, sections: sections, time: timeText)
        return lastJSON
    }

    // MARK: 纯文本报告

    private static func textReport(summary: String, sections: [Section], time: String) -> String {
        let info = MachineHolder.shared.machine.info
        var out = ""
        out += "Mac 工具箱 · 整机信息与验机报告\n"
        out += "生成时间：\(time)\n"
        out += "设备：\(info.displayName)（\(info.modelId)）· \(info.chip) · \(info.memoryGB) GB · macOS \(info.macos)\n"
        out += String(repeating: "=", count: 46) + "\n\n"
        for (i, s) in sections.enumerated() {
            out += "\(i + 1). \(s.title)　\(s.sub)\n"
            out += String(repeating: "-", count: 46) + "\n"
            for it in s.items {
                let mark = it.level == "bad" ? "✕" : (it.level == "warn" ? "!" : "·")
                out += "  \(mark) \(it.k)：\(it.v)\n"
                if !it.note.isEmpty { out += "      \(it.note)\n" }
            }
            out += "\n"
        }
        out += String(repeating: "=", count: 46) + "\n"
        out += "说明：本报告全部来自系统只读接口，未拆机、未修改任何设置。\n"
        out += "      软件层无法证明的部件（键盘上盖、风扇、I/O 板等），请以 Apple「部件与服务历史」为准。\n"
        return out
    }

    // MARK: 无线芯片名

    private static func wifiChipName(_ card: String) -> String {
        guard !card.isEmpty else { return "未检测到" }
        let map: [String: String] = [
            "0x4387": "Broadcom BCM4387（Wi-Fi 6）",
            "0x4388": "Broadcom BCM4388（Wi-Fi 6E）",
            "0x4378": "Broadcom BCM4378（Wi-Fi 6）",
            "0x4364": "Broadcom BCM4364（Wi-Fi 5）",
            "0x4353": "Broadcom BCM4353（Wi-Fi 5）",
            "0x43ba": "Broadcom BCM43xx",
        ]
        for (k, v) in map where card.lowercased().contains(k) { return v }
        if card.lowercased().contains("0x14e4") { return "Broadcom 无线网卡" }
        return card
    }

    // MARK: 机型 ↔ 芯片对照（用于换机芯判断）

    private static let CHIP_BY_MODEL: [String: [String]] = [
        "MacBookPro18,1": ["M1 Pro", "M1 Max"],
        "MacBookPro18,2": ["M1 Pro", "M1 Max"],
        "MacBookPro18,3": ["M1 Pro", "M1 Max"],
        "MacBookPro18,4": ["M1 Pro", "M1 Max"],
        "MacBookAir10,1": ["M1"],
        "Mac14,2": ["M2"], "Mac14,15": ["M2"],
        "Mac14,5": ["M2 Pro", "M2 Max"], "Mac14,6": ["M2 Pro", "M2 Max"],
        "Mac14,9": ["M2 Pro", "M2 Max"], "Mac14,10": ["M2 Pro", "M2 Max"],
        "Mac14,7": ["M2"],
        "Mac15,3": ["M3"], "Mac15,6": ["M3 Pro", "M3 Max"],
        "Mac15,7": ["M3 Pro", "M3 Max"], "Mac15,8": ["M3 Pro", "M3 Max"],
        "Mac15,9": ["M3 Max"], "Mac15,10": ["M3 Pro", "M3 Max"], "Mac15,11": ["M3 Max"],
        "Mac15,12": ["M3"], "Mac15,13": ["M3"],
        "Macmini9,1": ["M1"], "Mac14,3": ["M2"], "Mac14,12": ["M2 Pro"],
        "Mac13,1": ["M1 Max"], "Mac13,2": ["M1 Ultra"],
        "Mac14,13": ["M2 Max"], "Mac14,14": ["M2 Ultra"],
        "iMac21,1": ["M1"], "iMac21,2": ["M1"],
        "Mac15,4": ["M3"], "Mac15,5": ["M3"],
    ]

    // MARK: 导出

    /// 把最近一次报告写成文件；返回落盘路径（取消时为空）
    static func export(format: String) -> String {
        guard !lastJSON.isEmpty else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        let stamp = f.string(from: lastTime)
        let isJSON = format.lowercased() == "json"

        var content = lastText
        if isJSON, let data = lastJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let s = String(data: pretty, encoding: .utf8) {
            content = s
        }

        let panel = NSSavePanel()
        panel.title = isJSON ? "导出验机报告（JSON）" : "导出验机报告（文本）"
        panel.nameFieldStringValue = "Mac工具箱-验机报告-\(stamp).\(isJSON ? "json" : "txt")"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return "" }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch {
            return ""
        }
    }
}
