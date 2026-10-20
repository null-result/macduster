import Foundation

public struct LargeFileQuery {
    public var root: URL
    public var minSize: Int64
    public var unusedForDays: Int
    public var limit: Int

    public init(root: URL, minSize: Int64 = 100 * 1_048_576, unusedForDays: Int = 0, limit: Int = 500) {
        self.root = root
        self.minSize = minSize
        self.unusedForDays = unusedForDays
        self.limit = limit
    }
}

public enum LargeFiles {
    public static func scan(_ query: LargeFileQuery) -> [CleanItem] {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey, .contentAccessDateKey, .contentModificationDateKey]
        guard let en = FileManager.default.enumerator(at: query.root, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                      errorHandler: { _, _ in true }) else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -query.unusedForDays, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        var items: [CleanItem] = []
        for case let url as URL in en {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let size = v.totalFileAllocatedSize.map(Int64.init), size >= query.minSize else { continue }
            let lastUse = v.contentAccessDate ?? v.contentModificationDate ?? Date()
            if query.unusedForDays > 0 && lastUse > cutoff { continue }
            items.append(CleanItem(url: url, size: size, detail: "Último uso: " + formatter.string(from: lastUse),
                                   selectedByDefault: false))
        }
        return Array(items.sorted { $0.size > $1.size }.prefix(query.limit))
    }
}
