import Foundation

public struct InstalledApp: Identifiable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let version: String?
    public let size: Int64

    /// Las apps de Apple vienen con el sistema y no se pueden desinstalar.
    public var isProtected: Bool { bundleID?.hasPrefix("com.apple.") ?? false }
}

public enum AppUninstaller {
    private static let applicationFolders: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileSystem.home.appendingPathComponent("Applications"),
    ]

    /// Subcarpetas de ~/Library donde las apps dejan sus restos.
    private static let leftoverFolders = [
        "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
        "Logs", "Saved Application State", "LaunchAgents", "WebKit", "HTTPStorages", "Cookies",
        "Application Scripts",
    ]

    public static func listApps() -> [InstalledApp] {
        applicationFolders.flatMap { folder in
            FileSystem.children(of: folder).filter { $0.pathExtension == "app" }
        }
        .map { url in
            let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            return InstalledApp(url: url, name: name, bundleID: info?["CFBundleIdentifier"] as? String,
                                version: info?["CFBundleShortVersionString"] as? String,
                                size: FileSystem.size(of: url))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Busca restos del app por bundle ID (contiene) o por nombre exacto en carpetas típicas.
    public static func findLeftovers(for app: InstalledApp) -> [CleanItem] {
        let library = FileSystem.home.appendingPathComponent("Library")
        let bundleID = app.bundleID?.lowercased()
        let names: Set<String> = [app.name.lowercased(), app.url.deletingPathExtension().lastPathComponent.lowercased()]
        var found: [CleanItem] = []
        for folder in leftoverFolders {
            for url in FileSystem.children(of: library.appendingPathComponent(folder)) {
                let file = url.lastPathComponent.lowercased()
                let stem = (file as NSString).deletingPathExtension
                let byID = bundleID.map { file.contains($0) } ?? false
                let byName = names.contains(file) || names.contains(stem)
                guard byID || byName else { continue }
                found.append(CleanItem(url: url, size: FileSystem.size(of: url),
                                       detail: "Library/" + folder, selectedByDefault: true))
            }
        }
        return found.sorted { $0.size > $1.size }
    }
}
