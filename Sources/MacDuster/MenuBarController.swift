import AppKit
import SwiftUI
import MacDusterCore

/// Icono en la barra de menú: al pulsarlo abre un panel con el estado del Mac.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let model = MenuModel()
    private var suggestions: [CleanupSuggestion] = []
    private let onOpen: () -> Void
    private let onChanged: () -> Void

    init(onOpen: @escaping () -> Void, onChanged: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onChanged = onChanged
        super.init()
        let panel = MenuPanel(model: model,
                              onOpen: { [weak self] in self?.popover.performClose(nil); self?.onOpen() },
                              onEmptyTrash: { [weak self] in self?.emptyTrash() },
                              onFreeMemory: { [weak self] in self?.freeMemory() },
                              onQuit: { NSApp.terminate(nil) })
        popover.contentViewController = NSHostingController(rootView: panel)
        popover.behavior = .transient
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        updateIcon()
    }

    func update(status: DiskStatus, suggestions: [CleanupSuggestion]) {
        self.suggestions = suggestions
        model.disk = status
        model.suggestions = suggestions
        updateIcon()
    }

    private func updateIcon() {
        item.button?.image = Self.icon(alert: !suggestions.isEmpty)
        item.button?.toolTip = suggestions.isEmpty ? "MacDuster" : "MacDuster: tienes limpiezas sugeridas"
    }

    /// Plumero con destellos, como imagen de plantilla; con aviso cambia el destello pequeño por un punto.
    private static func icon(alert: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 3, y: 3))
            handle.line(to: NSPoint(x: 8.8, y: 9.2))
            handle.lineWidth = 1.7
            handle.lineCapStyle = .round
            handle.stroke()

            for (angle, length, width) in [(-30.0, 7.0, 2.1), (30.0, 7.0, 2.1), (0.0, 8.4, 2.4)] as [(CGFloat, CGFloat, CGFloat)] {
                NSGraphicsContext.saveGraphicsState()
                let t = NSAffineTransform()
                t.translateX(by: 9.4, yBy: 9.8)
                t.rotate(byDegrees: -45 - angle)
                t.concat()
                let petal = NSBezierPath()
                petal.move(to: .zero)
                petal.curve(to: NSPoint(x: 0, y: length), controlPoint1: NSPoint(x: width, y: length * 0.25), controlPoint2: NSPoint(x: width * 0.8, y: length * 0.85))
                petal.curve(to: .zero, controlPoint1: NSPoint(x: -width * 0.8, y: length * 0.85), controlPoint2: NSPoint(x: -width, y: length * 0.25))
                petal.fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            func sparkle(_ c: NSPoint, _ r: CGFloat) {
                let k = r * 0.28
                let s = NSBezierPath()
                s.move(to: NSPoint(x: c.x, y: c.y + r))
                s.line(to: NSPoint(x: c.x + k, y: c.y + k)); s.line(to: NSPoint(x: c.x + r, y: c.y))
                s.line(to: NSPoint(x: c.x + k, y: c.y - k)); s.line(to: NSPoint(x: c.x, y: c.y - r))
                s.line(to: NSPoint(x: c.x - k, y: c.y - k)); s.line(to: NSPoint(x: c.x - r, y: c.y))
                s.line(to: NSPoint(x: c.x - k, y: c.y + k)); s.close()
                s.fill()
            }
            sparkle(NSPoint(x: 3.6, y: 14.2), 2.6)
            if alert { NSBezierPath(ovalIn: NSRect(x: 12.4, y: 1.2, width: 4.6, height: 4.6)).fill() } else { sparkle(NSPoint(x: 14.8, y: 4.4), 1.9) }
            return true
        }
        image.isTemplate = true
        return image
    }

    func popoverDidClose(_ notification: Notification) { model.stop() }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.start()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func freeMemory() {
        guard let task = MaintenanceTask.task(id: "purge") else { return }
        Task {
            _ = await Task.detached { task.run() }.value
            onChanged()
        }
    }

    private func emptyTrash() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "¿Vaciar la Papelera?"
        alert.informativeText = "Se borrará definitivamente su contenido (\(formatBytes(model.disk?.trash ?? 0)))."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Vaciar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trash = FileSystem.home.appendingPathComponent(".Trash")
        Task {
            await Task.detached {
                let items = FileSystem.children(of: trash).map { CleanItem(url: $0, size: 0, permanent: true) }
                _ = FileSystem.remove(items)
            }.value
            onChanged()
        }
    }
}
