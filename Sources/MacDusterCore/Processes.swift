import AppKit

public struct RunningProcess: Identifiable, Hashable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let memory: Int64
    public let cpu: Double
}

public enum Processes {
    /// Procesos del usuario actual ordenados por memoria residente.
    public static func top(limit: Int = 40) -> [RunningProcess] {
        let result = Shell.run("/bin/ps", ["-axo", "pid=,uid=,rss=,%cpu=,comm="])
        guard result.ok else { return [] }
        let me = Int32(getuid())
        let list = result.output.split(separator: "\n").compactMap { line -> RunningProcess? in
            let f = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard f.count == 5, let pid = Int32(f[0]), Int32(f[1]) == me, let rss = Int64(f[2]), let cpu = Double(f[3]) else { return nil }
            return RunningProcess(pid: pid, name: (String(f[4]) as NSString).lastPathComponent, memory: rss * 1024, cpu: cpu)
        }
        return Array(list.sorted { $0.memory > $1.memory }.prefix(limit))
    }

    /// Cierra una app de forma ordenada, o envía SIGTERM a un proceso que no sea una app.
    @discardableResult
    public static func quit(pid: Int32) -> Bool {
        guard pid > 1, pid != getpid() else { return false }
        if let app = NSRunningApplication(processIdentifier: pid) { return app.terminate() }
        return kill(pid, SIGTERM) == 0
    }
}
