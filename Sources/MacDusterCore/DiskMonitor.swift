import Foundation

public struct DiskStatus: Equatable {
    public let total: Int64
    public let available: Int64
    public let trash: Int64

    public init(total: Int64, available: Int64, trash: Int64) {
        self.total = total
        self.available = available
        self.trash = trash
    }
}

public enum CleanupSuggestion: Equatable {
    case lowDisk(available: Int64)
    case fullTrash(size: Int64)
}

public struct SuggestionThresholds {
    public var minFreeBytes: Int64 = 10 * 1_073_741_824
    public var minFreeFraction = 0.10
    public var maxTrashBytes: Int64 = 1_073_741_824

    public init() {}
}

public enum DiskMonitor {
    /// Espacio libre (el mismo que muestra el Finder, incluyendo purgable) y tamaño de la Papelera.
    public static func status() -> DiskStatus {
        let values = try? FileSystem.home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return DiskStatus(total: Int64(values?.volumeTotalCapacity ?? 0),
                          available: values?.volumeAvailableCapacityForImportantUsage ?? 0,
                          trash: FileSystem.size(of: FileSystem.home.appendingPathComponent(".Trash")))
    }

    public static func suggestions(for status: DiskStatus, thresholds: SuggestionThresholds = .init()) -> [CleanupSuggestion] {
        var result: [CleanupSuggestion] = []
        if status.total > 0,
           status.available < thresholds.minFreeBytes || Double(status.available) / Double(status.total) < thresholds.minFreeFraction {
            result.append(.lowDisk(available: status.available))
        }
        if status.trash > thresholds.maxTrashBytes { result.append(.fullTrash(size: status.trash)) }
        return result
    }
}
