import Foundation
import IOKit.ps

public struct MemoryStatus {
    public let total: Int64
    public let used: Int64
    public var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public enum SystemStats {
    /// Memoria usada como la muestra el Monitor de Actividad: apps + cableada + comprimida.
    public static func memory() -> MemoryStatus {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemoryStatus(total: total, used: 0) }
        let page = Int64(getpagesize())
        let pages = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
            + Int64(stats.wire_count) + Int64(stats.compressor_page_count)
        return MemoryStatus(total: total, used: max(0, pages) * page)
    }
}

public struct BatteryStatus: Equatable {
    public let level: Int
    public let charging: Bool
    public let pluggedIn: Bool
}

extension SystemStats {
    /// Estado de la batería, o nil si el Mac no tiene (sobremesa).
    public static func battery() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return BatteryStatus(level: current * 100 / max,
                                 charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                 pluggedIn: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

/// Uso de CPU entre dos muestras (0...1).
public struct CPUSampler {
    private var previous: [UInt32]?

    public init() {}

    public mutating func usage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3] // user, system, idle, nice
        defer { previous = ticks }
        guard let before = previous else { return 0 }
        let delta = zip(ticks, before).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        return total > 0 ? (total - delta[2]) / total : 0
    }
}

/// Velocidad de red (bytes/s) sumando las interfaces físicas activas (Wi-Fi, Ethernet…).
public struct NetworkSampler {
    private var previous: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var lastDate: Date?

    public init() {}

    public mutating func speed() -> (down: Double, up: Double) {
        let now = Date()
        var current: [String: (rx: UInt32, tx: UInt32)] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0 {
            var cursor = list
            while let entry = cursor?.pointee {
                defer { cursor = entry.ifa_next }
                let flags = Int32(entry.ifa_flags)
                guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                      flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                      let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else { continue }
                let name = String(cString: entry.ifa_name)
                if name.hasPrefix("en") { current[name] = (data.ifi_ibytes, data.ifi_obytes) }
            }
            freeifaddrs(list)
        }
        defer { previous = current; lastDate = now }
        guard let last = lastDate else { return (0, 0) }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return (0, 0) }
        var down = 0.0, up = 0.0
        for (name, c) in current {
            guard let p = previous[name] else { continue }
            down += Double(c.rx &- p.rx)
            up += Double(c.tx &- p.tx)
        }
        return (down / dt, up / dt)
    }
}
