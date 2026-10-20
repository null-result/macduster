import Foundation

public struct StartupItem: Identifiable, Hashable {
    public enum Kind: String { case loginItem, userAgent, globalAgent, daemon }

    public var id: String { kind.rawValue + ":" + label }
    public let kind: Kind
    public let label: String
    public let program: String?
    public let path: String
    public var enabled: Bool

    /// Los agentes se pueden activar/desactivar; los login items solo quitar; los daemons son de solo lectura.
    public var canToggle: Bool { kind == .userAgent || kind == .globalAgent }
}

public enum StartupItems {
    private static var domain: String { "gui/\(getuid())" }

    public static func list() -> [StartupItem] {
        let disabled = disabledLabels()
        let folders: [(URL, StartupItem.Kind)] = [
            (FileSystem.home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
        ]
        var items = loginItems()
        for (folder, kind) in folders {
            for url in FileSystem.children(of: folder) where url.pathExtension == "plist" {
                guard let plist = NSDictionary(contentsOf: url), let label = plist["Label"] as? String else { continue }
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                items.append(StartupItem(kind: kind, label: label, program: program, path: url.path,
                                         enabled: !disabled.contains(label)))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Activa o desactiva un agente de lanzamiento (reversible, vía launchctl).
    public static func setEnabled(_ item: StartupItem, _ enabled: Bool) -> Bool {
        guard item.canToggle else { return false }
        let target = "\(domain)/\(item.label)"
        if enabled {
            let ok = Shell.run("/bin/launchctl", ["enable", target]).ok
            _ = Shell.run("/bin/launchctl", ["bootstrap", domain, item.path])
            return ok
        }
        let ok = Shell.run("/bin/launchctl", ["disable", target]).ok
        _ = Shell.run("/bin/launchctl", ["bootout", target])
        return ok
    }

    /// Quita un elemento de inicio de sesión (requiere permiso de Automatización sobre System Events).
    public static func removeLoginItem(_ item: StartupItem) -> Bool {
        guard item.kind == .loginItem else { return false }
        let name = item.label.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return Shell.run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to delete login item \"\(name)\""]).ok
    }

    private static func loginItems() -> [StartupItem] {
        func query(_ property: String) -> [String] {
            let r = Shell.run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to get the \(property) of every login item"])
            guard r.ok, !r.output.isEmpty else { return [] }
            return r.output.components(separatedBy: ", ")
        }
        let names = query("name"), paths = query("path")
        return names.enumerated().map { index, name in
            StartupItem(kind: .loginItem, label: name, program: index < paths.count ? paths[index] : nil,
                        path: index < paths.count ? paths[index] : "", enabled: true)
        }
    }

    /// `launchctl print-disabled` devuelve líneas como `"com.foo" => true` (true/disabled = desactivado).
    private static func disabledLabels() -> Set<String> {
        let r = Shell.run("/bin/launchctl", ["print-disabled", domain])
        var result = Set<String>()
        for line in r.output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value == "true" || value == "disabled" else { continue }
            result.insert(parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")))
        }
        return result
    }
}
