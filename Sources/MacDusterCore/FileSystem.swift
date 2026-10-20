import Foundation

public struct CleanItem: Identifiable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let size: Int64
    public let detail: String?
    public let permanent: Bool
    public let selectedByDefault: Bool

    public init(url: URL, size: Int64, detail: String? = nil, permanent: Bool = false, selectedByDefault: Bool = true) {
        self.url = url
        self.name = url.lastPathComponent
        self.size = size
        self.detail = detail
        self.permanent = permanent
        self.selectedByDefault = selectedByDefault
    }
}

public struct RemovalReport {
    public var freed: Int64 = 0
    public var failures: [(url: URL, reason: String)] = []
}

public enum FileSystem {
    public static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Tamaño en disco de un archivo o carpeta (sin seguir enlaces simbólicos).
    public static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        func fileSize(_ u: URL) -> Int64 {
            guard let v = try? u.resourceValues(forKeys: keys), v.isRegularFile == true else { return 0 }
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard isDir.boolValue else { return fileSize(url) }
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in en { total += fileSize(u) }
        return total
    }

    public static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    /// Solo se permite borrar dentro del home del usuario o de /Applications.
    public static func isSafeToRemove(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        return (path.hasPrefix(homePath + "/") && path.count > homePath.count + 1)
            || (path.hasPrefix("/Applications/") && path.count > "/Applications/".count)
    }

    /// Mueve a la papelera, o borra definitivamente si `permanent` es true.
    public static func remove(_ items: [CleanItem]) -> RemovalReport {
        var report = RemovalReport()
        let fm = FileManager.default
        for item in items {
            guard isSafeToRemove(item.url) else {
                report.failures.append((item.url, "Ruta protegida"))
                continue
            }
            do {
                if item.permanent {
                    try fm.removeItem(at: item.url)
                } else {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                }
                report.freed += item.size
            } catch {
                report.failures.append((item.url, error.localizedDescription))
            }
        }
        return report
    }
}
