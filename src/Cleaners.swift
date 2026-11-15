import AppKit
import Foundation
import Darwin

// MARK: - 路径安全守门（磁盘清理的唯一放行口）
/// 所有磁盘清理相关的扫描 / 删除都必须先过这里：
/// 命中黑名单、不在用户目录内、指向家目录本身、任意层级的 .git —— 一律拒绝。
enum SafePath {
    /// 危险根目录：整棵子树都不许扫、不许删
    static let bannedRoots: [String] = [
        "/System", "/Library", "/bin", "/sbin", "/usr", "/private",
        "/Applications", "/Volumes", "/cores", "/dev", "/etc", "/var", "/tmp",
    ]
    /// 用户目录内的敏感目录（凭据 / 容器 / 配置）
    static func bannedInHome() -> [String] {
        let h = NSHomeDirectory()
        return [
            h + "/.ssh", h + "/.aws", h + "/.gnupg", h + "/.config",
            h + "/Library/Containers", h + "/Library/Keychains",
            h + "/Library/Mobile Documents",
        ]
    }

    /// 家目录本身也不允许被整体清理
    static func isBanned(_ path: String) -> Bool {
        let p = (path as NSString).standardizingPath
        if p.isEmpty || p == "/" { return true }
        for b in bannedRoots {
            if p == b || p.hasPrefix(b + "/") { return true }
        }
        for b in bannedInHome() {
            if p == b || p.hasPrefix(b + "/") { return true }
        }
        // 任意层级的 .git（含 .git 本身与其内部文件）
        if p.split(separator: "/").contains(".git") { return true }
        let home = NSHomeDirectory()
        if p == home { return true }
        // 只允许用户目录之内
        if !p.hasPrefix(home + "/") { return true }
        // 家目录下一级目录（如 ~/Downloads）允许，但家目录本身已排除
        return false
    }

    /// 扫描 / 删除前的统一放行校验
    static func allowed(_ path: String) -> Bool { !isBanned(path) }
}

// MARK: - 内存统计
enum MemStats {
    struct Snap {
        var total: UInt64 = 0
        var used: UInt64 = 0
        var available: UInt64 = 0
        var cached: UInt64 = 0
        var compressed: UInt64 = 0
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
        var level: Int = 1
        var text: String = "正常"
    }

    private static func swapUsage() -> (UInt64, UInt64) {
        // 用 xsw_usage 结构体直接读，避免字符串解析在部分系统上取到空串
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let r = sysctlbyname("vm.swapusage", &xsw, &size, nil, 0)
        guard r == 0 else { return (0, 0) }
        return (UInt64(xsw.xsu_total), UInt64(xsw.xsu_used))
    }

    static func snapshot() -> Snap {
        var s = Snap()
        s.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }
        var page: vm_size_t = 0
        host_page_size(host, &page)
        let pg = UInt64(page)

        if kr == KERN_SUCCESS, pg > 0 {
            let free = UInt64(stats.free_count) * pg
            let inactive = UInt64(stats.inactive_count) * pg
            let speculative = UInt64(stats.speculative_count) * pg
            let purgeable = UInt64(stats.purgeable_count) * pg
            let wired = UInt64(stats.wire_count) * pg
            let compressed = UInt64(stats.compressor_page_count) * pg
            let internalPages = UInt64(stats.internal_page_count) * pg
            let appMem = internalPages > purgeable ? internalPages - purgeable : 0
            s.compressed = compressed
            s.cached = inactive + speculative + purgeable
            // 可用 = 空闲 + 非活跃 + 可清除 + 可回收（与「活动监视器」口径接近）
            var avail = free + inactive + speculative + purgeable
            if avail > s.total { avail = s.total }
            s.available = avail
            s.used = s.total > avail ? s.total - avail : 0
            _ = appMem
            _ = wired
        }

        let (st, su) = swapUsage()
        s.swapTotal = st
        s.swapUsed = su

        var lvl: Int32 = 0
        var sz = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &lvl, &sz, nil, 0) == 0 {
            s.level = Int(lvl)
        }
        switch s.level {
        case 0, 1: s.text = "正常"
        case 2: s.text = "偏高"
        case 4: s.text = "紧张"
        default: s.text = "正常"
        }

        // 可用比例过低或 Swap 明显占用时，把压力档位如实上调，避免"看着正常其实很紧"
        if s.total > 0 {
            let ratio = Double(s.available) / Double(s.total)
            if ratio < 0.10, s.text == "正常" { s.text = "偏高" }
            if s.swapUsed > 2 * 1024 * 1024 * 1024 { s.text = "紧张" }
        }
        return s
    }

    static func json() -> String {
        let s = snapshot()
        let pct = s.total > 0 ? Double(s.used) / Double(s.total) * 100 : 0
        let dict: [String: Any] = [
            "ok": true,
            "mem": [
                "total": s.total,
                "used": s.used,
                "available": s.available,
                "cached": s.cached,
                "compressed": s.compressed,
                "swapUsed": s.swapUsed,
                "swapTotal": s.swapTotal,
                "pressure": s.text,
                "pressureLevel": s.level,
                "percent": (pct * 10).rounded() / 10,
            ],
        ]
        return JSON.enc(dict)
    }
}

// MARK: - JSON 小工具
enum JSON {
    static func enc(_ obj: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let s = String(data: d, encoding: .utf8) else { return "{\"ok\":false}" }
        return s
    }
}

// MARK: - 内存清理（轻度）
/// 只做本进程 / 用户态无害动作：绝不 kill 任何进程，绝不提权。
enum MemCleaner {
    static func light() -> String {
        let before = MemStats.snapshot()
        let t0 = Date()
        var steps: [[String: Any]] = []

        // 1) 归还本 App 各 malloc zone 的可回收内存（公开 API，无副作用）
        let relieved = malloc_zone_pressure_relief(nil, 0)
        steps.append([
            "name": "释放本 App 可回收内存",
            "status": "done",
            "detail": String(format: "malloc_zone_pressure_relief 归还 %.1f MB", Double(relieved) / 1048576.0),
        ])

        // 2) 清掉本 App 的 URL 缓存
        URLCache.shared.removeAllCachedResponses()
        steps.append(["name": "清理本 App 网络缓存", "status": "done", "detail": "URLCache 已清空"])

        // 3) 排空自动释放池（回收临时对象）
        autoreleasepool { }
        steps.append(["name": "回收本 App 临时对象", "status": "done", "detail": "自动释放池已排空"])

        // 4) 系统级 purge：需要管理员权限，按红线直接跳过，绝不弹密码框
        steps.append([
            "name": "系统级内存回收（purge）",
            "status": "skipped",
            "detail": "该项需系统权限，已跳过",
        ])
        steps.append([
            "name": "关闭其它进程以腾内存",
            "status": "skipped",
            "detail": "轻度模式不关闭任何程序，已跳过",
        ])

        let after = MemStats.snapshot()
        let elapsed = Date().timeIntervalSince(t0)
        let freed = before.used > after.used ? before.used - after.used : 0

        var dict: [String: Any] = [
            "ok": true,
            "mode": "light",
            "freed": freed,
            "elapsed": (elapsed * 100).rounded() / 100,
            "killed": 0,
            "steps": steps,
            "before": snapshotDict(before),
            "after": snapshotDict(after),
        ]
        dict["note"] = "macOS 会动态调整内存占用，释放量仅供参考；本模式未关闭任何程序。"
        return JSON.enc(dict)
    }

    private static func snapshotDict(_ s: MemStats.Snap) -> [String: Any] {
        var d: [String: Any] = [
            "used": s.used,
            "available": s.available,
            "swapUsed": s.swapUsed,
            "pressure": s.text,
        ]
        d["total"] = s.total
        return d
    }
}

// MARK: - 用户级 App 枚举 / 优雅退出
enum AppList {
    /// 无论什么模式都不许碰的 bundle id（系统外壳、窗口服务、本 App）
    static let bannedBundles: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.SystemUIServer",
        "com.apple.loginwindow", "com.apple.WindowServer", "com.apple.WindowManager",
        "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.backgroundtaskmanagement.agent", "com.apple.SoftwareUpdateNotification",
        "com.apple.universalaccessAuthWarn", "com.apple.SecurityAgent",
        "cn.wangchuanhe.roastbench",
    ]
    static let bannedNames: Set<String> = [
        "Finder", "访达", "Dock", "WindowServer", "loginwindow", "SystemUIServer",
        "Control Center", "控制中心", "Notification Center", "通知中心",
        "Mac 工具箱", "Mac工具箱",
    ]

    private static func rssByPid() -> [Int32: UInt64] {
        let out = shell("/bin/ps", ["-axo", "pid=,rss="])
        var map: [Int32: UInt64] = [:]
        for line in out.components(separatedBy: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            if cols.count >= 2, let pid = Int32(cols[0]), let kb = UInt64(cols[1]) {
                map[pid] = kb * 1024
            }
        }
        return map
    }

    private static func iconPNG(_ app: NSRunningApplication) -> String {
        guard let icon = app.icon else { return "" }
        let size: CGFloat = 40
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return "" }
        return png.base64EncodedString()
    }

    /// 当前运行中的「常规用户 App」——有 bundle id、Dock 里能看到、非系统目录、非黑名单
    static func candidates() -> [NSRunningApplication] {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        var list: [NSRunningApplication] = []
        for app in NSWorkspace.shared.runningApplications {
            if app.isTerminated { continue }
            if app.processIdentifier == selfPid { continue }
            guard app.activationPolicy == .regular else { continue }
            guard let bid = app.bundleIdentifier, !bid.isEmpty else { continue }
            if bannedBundles.contains(bid) { continue }
            if let name = app.localizedName, bannedNames.contains(name) { continue }
            // 系统自带 App（Finder、Dock 等）一律不碰
            if let path = app.bundleURL?.path, path.hasPrefix("/System/") { continue }
            list.append(app)
        }
        return list
    }

    static func json() -> String {
        let rss = rssByPid()
        var arr: [[String: Any]] = []
        for app in candidates() {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            var item: [String: Any] = [
                "pid": Int(pid),
                "name": app.localizedName ?? "未知",
                "bundle": app.bundleIdentifier ?? "",
                "mem": rss[pid] ?? 0,
            ]
            let ic = iconPNG(app)
            if !ic.isEmpty { item["icon"] = ic }
            arr.append(item)
        }
        arr.sort { (a, b) -> Bool in
            let am = a["mem"] as? UInt64 ?? 0
            let bm = b["mem"] as? UInt64 ?? 0
            return am > bm
        }
        return JSON.enc(["ok": true, "apps": arr, "count": arr.count, "selfPid": Int(ProcessInfo.processInfo.processIdentifier)])
    }

    /// 优雅退出：terminate → 等 5 秒 → 仍未退出才 forceTerminate，并标注强制项
    static func quit(pids: [Int32]) -> String {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        var results: [[String: Any]] = []
        let started = Date()

        for pid in pids {
            if pid == selfPid {
                results.append(["pid": Int(pid), "name": "Mac 工具箱", "closed": false, "forced": false, "reason": "拒绝关闭本 App"])
                continue
            }
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                results.append(["pid": Int(pid), "name": "PID \(pid)", "closed": false, "forced": false, "reason": "进程已不存在"])
                continue
            }
            let bid = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? "PID \(pid)"
            // 二次校验：黑名单 / 系统 App 一律不动
            if bid.isEmpty || bannedBundles.contains(bid) || bannedNames.contains(name)
                || (app.bundleURL?.path.hasPrefix("/System/") ?? false) {
                results.append(["pid": Int(pid), "name": name, "closed": false, "forced": false, "reason": "受保护进程，已拒绝"])
                continue
            }
            if app.isTerminated {
                results.append(["pid": Int(pid), "name": name, "closed": true, "forced": false, "reason": "已退出"])
                continue
            }
            app.terminate()
            var waited = 0.0
            while waited < 5.0 {
                usleep(150_000)
                waited += 0.15
                if app.isTerminated { break }
            }
            var forced = false
            if !app.isTerminated {
                app.forceTerminate()
                forced = true
                var w2 = 0.0
                while w2 < 2.0 {
                    usleep(150_000)
                    w2 += 0.15
                    if app.isTerminated { break }
                }
            }
            let closed = app.isTerminated
            var reason = closed ? (forced ? "超时未退出，已强制结束" : "已优雅退出") : "未退出（可能被系统保护或有未保存提示）"
            if !closed && !forced { reason = "未退出（可能被系统保护）" }
            results.append(["pid": Int(pid), "name": name, "closed": closed, "forced": forced, "reason": reason])
        }

        let closedCount = results.filter { ($0["closed"] as? Bool) == true }.count
        let forcedCount = results.filter { ($0["forced"] as? Bool) == true }.count
        return JSON.enc([
            "ok": true,
            "mode": "quit",
            "closed": closedCount,
            "forced": forcedCount,
            "requested": pids.count,
            "elapsed": (Date().timeIntervalSince(started) * 100).rounded() / 100,
            "apps": results,
        ])
    }
}

// MARK: - 磁盘垃圾扫描 / 移入废纸篓
enum DiskScanner {
    /// 本 App 自己的缓存，扫描时跳过（运行中清理自身缓存没有意义且可能干扰界面）
    static let selfCachePath = NSHomeDirectory() + "/Library/Caches/cn.wangchuanhe.roastbench"

    private struct CatDef {
        let id: String
        let name: String
        let desc: String
        let level: String      // safe / careful / confirm
        let kind: String       // children / bigfiles / tmpfiles
        let roots: [String]
    }

    private static func defs() -> [CatDef] {
        let h = NSHomeDirectory()
        return [
            CatDef(id: "caches", name: "用户缓存", desc: "~/Library/Caches：各 App 的缓存数据，删后会自动重建",
                   level: "safe", kind: "children", roots: [h + "/Library/Caches"]),
            CatDef(id: "logs", name: "应用日志", desc: "~/Library/Logs：应用与系统组件写的日志（不含崩溃报告）",
                   level: "safe", kind: "children", roots: [h + "/Library/Logs"]),
            CatDef(id: "crash", name: "崩溃报告", desc: "~/Library/Logs/DiagnosticReports：历史崩溃与诊断记录",
                   level: "careful", kind: "children", roots: [h + "/Library/Logs/DiagnosticReports"]),
            CatDef(id: "trash", name: "废纸篓", desc: "~/.Trash：已经在废纸篓里的文件",
                   level: "careful", kind: "children", roots: [h + "/.Trash"]),
            CatDef(id: "derived", name: "Xcode 派生数据", desc: "~/Library/Developer/Xcode/DerivedData：编译中间产物，删后重新编译自动生成",
                   level: "safe", kind: "children", roots: [h + "/Library/Developer/Xcode/DerivedData"]),
            CatDef(id: "simcaches", name: "模拟器缓存", desc: "~/Library/Developer/CoreSimulator/Caches：模拟器运行缓存",
                   level: "safe", kind: "children", roots: [h + "/Library/Developer/CoreSimulator/Caches"]),
            CatDef(id: "tmp", name: "通用临时文件", desc: "家目录下的 .tmp / .crdownload 等未完成下载与临时文件",
                   level: "careful", kind: "tmpfiles", roots: [h]),
            CatDef(id: "backup", name: "旧 iOS 备份", desc: "~/Library/Application Support/MobileSync/Backup：iOS 设备本地备份",
                   level: "confirm", kind: "children", roots: [h + "/Library/Application Support/MobileSync/Backup"]),
            CatDef(id: "bigfile", name: "下载与桌面大文件", desc: "~/Downloads、~/Desktop 中大于 100MB 的文件",
                   level: "confirm", kind: "bigfiles", roots: [h + "/Downloads", h + "/Desktop"]),
        ]
    }

    private static let fileKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey,
    ]

    /// 递归统计一个路径占用的字节数与文件数（不跟随符号链接，命中黑名单的子树直接跳过）
    static func measure(_ url: URL) -> (bytes: UInt64, files: Int) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return (0, 0) }
        if !isDir.boolValue {
            guard let v = try? url.resourceValues(forKeys: Set(fileKeys)) else { return (0, 0) }
            if v.isSymbolicLink == true { return (0, 0) }
            let b = v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0
            return (UInt64(max(0, b)), 1)
        }
        var bytes: UInt64 = 0
        var files = 0
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: fileKeys,
                                     options: [], errorHandler: { _, _ in true }) else { return (0, 0) }
        for case let f as URL in en {
            if SafePath.isBanned(f.path) {
                en.skipDescendants()
                continue
            }
            if f.path.hasPrefix(selfCachePath) { continue }
            guard let v = try? f.resourceValues(forKeys: Set(fileKeys)) else { continue }
            if v.isSymbolicLink == true { continue }
            if v.isRegularFile == true {
                bytes += UInt64(max(0, v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0))
                files += 1
            }
        }
        return (bytes, files)
    }

    private static func itemJSON(path: String, bytes: UInt64, files: Int, mtime: Date?, kind: String) -> [String: Any] {
        var d: [String: Any] = [
            "path": path,
            "name": (path as NSString).lastPathComponent,
            "bytes": bytes,
            "files": files,
            "kind": kind,
        ]
        if let m = mtime { d["mtime"] = Int(m.timeIntervalSince1970) }
        return d
    }

    /// 扫描（全程只读）。progress 回调为 0~100 的进度与当前路径描述
    static func scan(progress: @escaping (Double, String) -> Void) -> String {
        let fm = FileManager.default
        let list = defs()
        var out: [[String: Any]] = []
        let totalSteps = max(1, list.count)

        for (idx, def) in list.enumerated() {
            progress(Double(idx) / Double(totalSteps) * 100.0, def.name)

            var items: [[String: Any]] = []
            var bytes: UInt64 = 0
            var files = 0

            switch def.kind {
            case "children":
                for root in def.roots where fm.fileExists(atPath: root) {
                    let children = (try? fm.contentsOfDirectory(atPath: root)) ?? []
                    for child in children {
                        let full = root + "/" + child
                        if SafePath.isBanned(full) { continue }
                        if full == selfCachePath || full.hasPrefix(selfCachePath) { continue }
                        // 日志类不重复统计崩溃报告（单独一类）
                        if def.id == "logs" && child == "DiagnosticReports" { continue }
                        let url = URL(fileURLWithPath: full)
                        let (b, f) = measure(url)
                        guard b > 0 || f > 0 else { continue }
                        var isDirFlag: ObjCBool = false
                        _ = fm.fileExists(atPath: full, isDirectory: &isDirFlag)
                        let mt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                        items.append(itemJSON(path: full, bytes: b, files: f, mtime: mt, kind: isDirFlag.boolValue ? "dir" : "file"))
                        bytes += b
                        files += f
                    }
                }

            case "bigfiles":
                let threshold: UInt64 = 100 * 1024 * 1024
                for root in def.roots {
                    guard fm.fileExists(atPath: root) else { continue }
                    guard let en = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: fileKeys,
                                                 options: [], errorHandler: { _, _ in true }) else { continue }
                    var depthGuard = 0
                    for case let f as URL in en {
                        depthGuard += 1
                        if depthGuard > 60000 { break }
                        if SafePath.isBanned(f.path) { en.skipDescendants(); continue }
                        guard let v = try? f.resourceValues(forKeys: Set(fileKeys)) else { continue }
                        if v.isSymbolicLink == true { continue }
                        guard v.isRegularFile == true else { continue }
                        let b = UInt64(max(0, v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0))
                        guard b >= threshold else { continue }
                        items.append(itemJSON(path: f.path, bytes: b, files: 1,
                                              mtime: v.contentModificationDate, kind: "file"))
                        bytes += b
                        files += 1
                    }
                }
                items.sort { ($0["bytes"] as? UInt64 ?? 0) > ($1["bytes"] as? UInt64 ?? 0) }
                if items.count > 200 { items = Array(items.prefix(200)) }

            case "tmpfiles":
                let exts: Set<String> = ["tmp", "temp", "crdownload", "download", "part", "partial"]
                for root in def.roots {
                    guard let children = try? fm.contentsOfDirectory(atPath: root) else { continue }
                    for child in children {
                        let full = root + "/" + child
                        let ext = (child as NSString).pathExtension.lowercased()
                        guard exts.contains(ext) else { continue }
                        if SafePath.isBanned(full) { continue }
                        let url = URL(fileURLWithPath: full)
                        let (b, f) = measure(url)
                        guard b > 0 || f > 0 else { continue }
                        let mt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                        items.append(itemJSON(path: full, bytes: b, files: f, mtime: mt, kind: "file"))
                        bytes += b
                        files += f
                    }
                }

            default:
                break
            }

            // 明细按体积倒序，最多 120 条
            items.sort { ($0["bytes"] as? UInt64 ?? 0) > ($1["bytes"] as? UInt64 ?? 0) }
            let truncated = items.count > 120
            if truncated { items = Array(items.prefix(120)) }

            let levelText: String
            switch def.level {
            case "safe": levelText = "安全"
            case "careful": levelText = "需留意"
            default: levelText = "需你确认"
            }

            out.append([
                "id": def.id,
                "name": def.name,
                "desc": def.desc,
                "level": def.level,
                "levelText": levelText,
                "bytes": bytes,
                "files": files,
                "items": items,
                "truncated": truncated,
                "exists": !items.isEmpty,
            ])
            progress(Double(idx + 1) / Double(totalSteps) * 100.0, def.name)
        }

        let totalBytes = out.reduce(UInt64(0)) { $0 + (($1["bytes"] as? UInt64) ?? 0) }
        return JSON.enc([
            "ok": true,
            "scannedAt": Int(Date().timeIntervalSince1970),
            "totalBytes": totalBytes,
            "cats": out,
        ])
    }

    /// 移入废纸篓（绝不用 rm / 永久删除）
    static func trash(paths: [String]) -> String {
        let fm = FileManager.default
        var done: [[String: Any]] = []
        var failed: [[String: Any]] = []
        var freed: UInt64 = 0

        for path in paths {
            let std = (path as NSString).standardizingPath
            if SafePath.isBanned(std) {
                failed.append(["path": path, "reason": "命中安全黑名单，已拒绝"])
                continue
            }
            guard fm.fileExists(atPath: std) else {
                failed.append(["path": path, "reason": "文件已不存在"])
                continue
            }
            let url = URL(fileURLWithPath: std)
            let (bytes, _) = measure(url)
            var resulting: NSURL?
            do {
                try fm.trashItem(at: url, resultingItemURL: &resulting)
                done.append(["path": std, "bytes": bytes])
                freed += bytes
            } catch {
                failed.append(["path": std, "reason": (error as NSError).localizedDescription])
            }
        }

        return JSON.enc([
            "ok": true,
            "deleted": done,
            "failed": failed,
            "successCount": done.count,
            "failedCount": failed.count,
            "freed": freed,
        ])
    }
}
