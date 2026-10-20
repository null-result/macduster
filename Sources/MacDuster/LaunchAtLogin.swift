import Foundation

/// Inicio al arrancar sesión mediante un LaunchAgent (SMAppService requiere macOS 13).
enum LaunchAtLogin {
    private static let label = "dev.local.macduster.login"
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static let legacyLabel = "dev.local.dolores.login"

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func setEnabled(_ enabled: Bool) {
        guard enabled else { try? FileManager.default.removeItem(at: plistURL); return }
        guard let executable = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--background"],
            "RunAtLoad": true,
        ]
        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        (plist as NSDictionary).write(to: plistURL, atomically: true)
    }

    /// Si la app se movió de sitio, reescribe el agente con la ruta actual.
    static func refreshIfNeeded() {
        let legacy = plistURL.deletingLastPathComponent().appendingPathComponent("\(legacyLabel).plist")
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.removeItem(at: legacy)
            setEnabled(true)
        }
        guard isEnabled, let executable = Bundle.main.executablePath,
              let current = NSDictionary(contentsOf: plistURL)?["ProgramArguments"] as? [String],
              current.first != executable else { return }
        setEnabled(true)
    }
}
