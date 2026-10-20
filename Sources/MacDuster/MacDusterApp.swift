import SwiftUI
import UserNotifications
import MacDusterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private var window: NSWindow?
    private var menuBar: MenuBarController?
    private let monitor = SpaceMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let background = CommandLine.arguments.contains("--background")

        // Una sola instancia: si ya hay otra, la traemos al frente y salimos.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            if !background { NSWorkspace.shared.open(Bundle.main.bundleURL) }
            NSApp.terminate(nil)
            return
        }

        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        Notifier.requestAuthorization()
        LaunchAtLogin.refreshIfNeeded()

        let controller = MenuBarController(onOpen: { [weak self] in self?.showMainWindow() },
                                           onChanged: { [weak self] in self?.monitor.refresh() })
        menuBar = controller
        monitor.onUpdate = { status, suggestions in controller.update(status: status, suggestions: suggestions) }
        monitor.start()

        if !background { showMainWindow() }
    }

    func showMainWindow() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: ContentView().frame(minWidth: 820, minHeight: 520)))
            w.title = "MacDuster"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.setContentSize(NSSize(width: 960, height: 620))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Al cerrar la ventana la app sigue en la barra de menú, sin icono en el Dock.
    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.showMainWindow() }
        completionHandler()
    }
}

@main
struct MacDusterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
