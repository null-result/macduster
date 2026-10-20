import Foundation

public struct CleanCategory: Identifiable {
    public enum Granularity { case children, whole }

    public let id: String
    public let title: String
    public let symbol: String
    public let explanation: String
    public let roots: [URL]
    public let granularity: Granularity
    public let permanent: Bool
    public let selectedByDefault: Bool
}

public struct CategoryResult: Identifiable {
    public var id: String { category.id }
    public let category: CleanCategory
    public let items: [CleanItem]
    public var total: Int64 { items.reduce(0) { $0 + $1.size } }

    public init(category: CleanCategory, items: [CleanItem]) {
        self.category = category
        self.items = items
    }
}

public enum SystemCleaner {
    private static var h: URL { FileSystem.home }

    public static var categories: [CleanCategory] {
        [
            CleanCategory(id: "caches", title: "Cachés de usuario", symbol: "internaldrive",
                          explanation: "Archivos temporales de las apps; se regeneran solos.",
                          roots: [h.appendingPathComponent("Library/Caches")], granularity: .children,
                          permanent: false, selectedByDefault: true),
            CleanCategory(id: "logs", title: "Registros (logs)", symbol: "doc.text",
                          explanation: "Registros de actividad de apps y del sistema.",
                          roots: [h.appendingPathComponent("Library/Logs")], granularity: .children,
                          permanent: false, selectedByDefault: true),
            CleanCategory(id: "xcode", title: "Restos de Xcode", symbol: "hammer",
                          explanation: "DerivedData, soportes de dispositivo y cachés del simulador.",
                          roots: [h.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                                  h.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"),
                                  h.appendingPathComponent("Library/Developer/CoreSimulator/Caches")],
                          granularity: .children, permanent: false, selectedByDefault: true),
            CleanCategory(id: "devcaches", title: "Cachés de desarrollo", symbol: "terminal",
                          explanation: "npm, Gradle y registro de Cargo.",
                          roots: [h.appendingPathComponent(".npm/_cacache"),
                                  h.appendingPathComponent(".gradle/caches"),
                                  h.appendingPathComponent(".cargo/registry/cache")],
                          granularity: .whole, permanent: false, selectedByDefault: true),
            CleanCategory(id: "mail", title: "Adjuntos de Mail", symbol: "envelope",
                          explanation: "Copias locales de adjuntos descargados (requiere Acceso total al disco).",
                          roots: [h.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")],
                          granularity: .children, permanent: false, selectedByDefault: true),
            CleanCategory(id: "backups", title: "Copias de iOS", symbol: "iphone",
                          explanation: "Copias de seguridad locales de iPhone/iPad. Revísalas antes de borrar.",
                          roots: [h.appendingPathComponent("Library/Application Support/MobileSync/Backup")],
                          granularity: .children, permanent: false, selectedByDefault: false),
            CleanCategory(id: "trash", title: "Papelera", symbol: "trash",
                          explanation: "Vaciar la papelera es definitivo.",
                          roots: [h.appendingPathComponent(".Trash")], granularity: .children,
                          permanent: true, selectedByDefault: true),
        ]
    }

    public static func scan(_ category: CleanCategory) -> CategoryResult {
        let urls: [URL]
        switch category.granularity {
        case .children: urls = category.roots.flatMap { FileSystem.children(of: $0) }
        case .whole: urls = category.roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        let items = urls.compactMap { url -> CleanItem? in
            let size = FileSystem.size(of: url)
            guard size > 0 else { return nil }
            return CleanItem(url: url, size: size, detail: url.deletingLastPathComponent().lastPathComponent,
                             permanent: category.permanent, selectedByDefault: category.selectedByDefault)
        }
        return CategoryResult(category: category, items: items.sorted { $0.size > $1.size })
    }
}
