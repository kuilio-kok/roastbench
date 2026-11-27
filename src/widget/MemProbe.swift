import Foundation
import Darwin

// MARK: - 内存 / CPU 采样
// 小组件扩展跑在单独的进程里，不能靠主 App 推数据（沙盒 + 无共享容器），
// 所以这里自己算：host_statistics64 为主，sysctl 兜底。
enum MemProbe {
    static var totalBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }

    struct Stats {
        var used: UInt64 = 0        // 与活动监视器口径一致：App 内存 + 联动内存 + 已压缩
        var app: UInt64 = 0
        var wired: UInt64 = 0
        var compressed: UInt64 = 0
        var cached: UInt64 = 0
        var free: UInt64 = 0
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0

        var total: UInt64 { MemProbe.totalBytes }
        var percent: Double { total > 0 ? Double(used) / Double(total) : 0 }
        var available: UInt64 { total > used ? total - used : 0 }
    }

    static func sample() -> Stats {
        var s = Stats()
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var ps = UInt64(pageSize)
        if ps == 0 { ps = 4096 }

        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { p -> kern_return_t in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { q in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, q, &count)
            }
        }

        if kr == KERN_SUCCESS {
            let internalPages = UInt64(info.internal_page_count)
            let purgeable = UInt64(info.purgeable_count)
            s.app = (internalPages > purgeable ? internalPages - purgeable : 0) * ps
            s.wired = UInt64(info.wire_count) * ps
            s.compressed = UInt64(info.compressor_page_count) * ps
            s.cached = (UInt64(info.external_page_count) + purgeable) * ps
            s.free = UInt64(info.free_count + info.speculative_count) * ps
            s.used = s.app + s.wired + s.compressed
        } else {
            // 兜底：只拿到空闲页，用「总量 - 空闲」粗算
            let free = pageCount("vm.page_free_count") + pageCount("vm.page_speculative_count")
            s.free = free * ps
            s.used = s.total > s.free ? s.total - s.free : 0
            s.app = s.used
        }

        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 {
            s.swapUsed = xsw.xsu_used
            s.swapTotal = xsw.xsu_total
        }
        return s
    }

    private static func pageCount(_ name: String) -> UInt64 {
        var v: UInt64 = 0
        var size = MemoryLayout<UInt64>.stride
        if sysctlbyname(name, &v, &size, nil, 0) == 0 { return v }
        var v32: UInt32 = 0
        var s32 = MemoryLayout<UInt32>.stride
        if sysctlbyname(name, &v32, &s32, nil, 0) == 0 { return UInt64(v32) }
        return 0
    }

    /// 采样 0.35 秒算一次 CPU 占用百分比（进程内自己算，不依赖外部工具）
    static func cpuPercent() -> Double {
        func ticks() -> (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)? {
            var cpuCount: natural_t = 0
            var info: processor_info_array_t?
            var infoCount: mach_msg_type_number_t = 0
            let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
            guard kr == KERN_SUCCESS, let info = info else { return nil }
            defer {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                              vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
            }
            var u: UInt32 = 0, s: UInt32 = 0, i: UInt32 = 0, n: UInt32 = 0
            for c in 0..<Int(cpuCount) {
                let base = c * Int(CPU_STATE_MAX)
                u &+= UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
                s &+= UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
                i &+= UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
                n &+= UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            }
            return (u, s, i, n)
        }

        guard let a = ticks() else { return 0 }
        Thread.sleep(forTimeInterval: 0.35)
        guard let b = ticks() else { return 0 }
        let du = Double(b.user &- a.user), ds = Double(b.system &- a.system)
        let di = Double(b.idle &- a.idle), dn = Double(b.nice &- a.nice)
        let busy = du + ds + dn
        let all = busy + di
        return all > 0 ? min(max(busy / all * 100, 0), 100) : 0
    }

    static func gb(_ bytes: UInt64) -> Double { Double(bytes) / 1_000_000_000 }
}
