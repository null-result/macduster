import SwiftUI
import MacDusterCore

private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowsNonnumericFormatting = false // "0 KB" en lugar de "Zero KB"
    return f
}()

func formatBytes(_ bytes: Int64) -> String {
    byteFormatter.string(fromByteCount: bytes)
}

/// Fila con casilla, nombre, detalle y tamaño; la lupa abre el Finder.
struct ItemRow: View {
    let item: CleanItem
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Check(isOn: isOn, action: toggle)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if let detail = item.detail { Text(detail).font(.caption).foregroundColor(.dim).lineLimit(1) }
            }
            Spacer()
            Text(formatBytes(item.size)).monospacedDigit().foregroundColor(.dim)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: { Image(systemName: "magnifyingglass").foregroundColor(.dim) }
                .buttonStyle(.plain)
                .help("Mostrar en el Finder")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

/// Pie con el botón circular de acción, el resumen de la selección y confirmación.
struct ActionFooter: View {
    let selectedCount: Int
    let selectedBytes: Int64
    let title: String
    var detail = "Lo no definitivo irá a la Papelera."
    let busy: Bool
    let message: String?
    let action: () -> Void
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 6) {
            CircleButton(title: title, subtitle: formatBytes(selectedBytes), size: 96,
                         disabled: selectedCount == 0 || busy) { confirming = true }
            Text(message ?? "\(selectedCount) elementos seleccionados").font(.caption).foregroundColor(.dim)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.sidebarCanvas.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
        .alert("¿\(title)?", isPresented: $confirming) {
            Button("Cancelar", role: .cancel) {}
            Button(title, role: .destructive, action: action)
        } message: {
            Text("Se procesarán \(selectedCount) elementos (\(formatBytes(selectedBytes))). \(detail)")
        }
    }
}

func summary(_ report: RemovalReport) -> String {
    var text = "Liberados \(formatBytes(report.freed))"
    if !report.failures.isEmpty { text += " · \(report.failures.count) errores (¿falta Acceso total al disco?)" }
    return text
}
