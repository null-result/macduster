import Foundation
import UserNotifications
import MacDusterCore

enum Preferences {
    static var notificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }
}

/// Comprueba periódicamente el disco y la Papelera, y avisa con una notificación (con enfriamiento).
@MainActor
final class SpaceMonitor {
    var onUpdate: ((DiskStatus, [CleanupSuggestion]) -> Void)?
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        Task {
            let status = await Task.detached { DiskMonitor.status() }.value
            let suggestions = DiskMonitor.suggestions(for: status)
            onUpdate?(status, suggestions)
            if Preferences.notificationsEnabled { suggestions.forEach(Notifier.notify) }
        }
    }
}

enum Notifier {
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(_ suggestion: CleanupSuggestion) {
        guard available else { return }
        let key: String, cooldown: TimeInterval, title: String, body: String
        switch suggestion {
        case .lowDisk(let free):
            (key, cooldown) = ("lowDisk", 12 * 3600)
            title = "Queda poco espacio en el disco"
            body = "Solo quedan \(formatBytes(free)) libres. Abre MacDuster para liberar espacio."
        case .fullTrash(let size):
            (key, cooldown) = ("fullTrash", 24 * 3600)
            title = "La Papelera está muy llena"
            body = "Ocupa \(formatBytes(size)). Vacíala para recuperar espacio."
        }
        let defaults = UserDefaults.standard, stamp = "lastNotified.\(key)"
        if let last = defaults.object(forKey: stamp) as? Date, Date().timeIntervalSince(last) < cooldown { return }
        defaults.set(Date(), forKey: stamp)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }
}
