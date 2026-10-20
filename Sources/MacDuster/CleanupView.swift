import SwiftUI
import MacDusterCore

@MainActor
final class CleanupModel: ObservableObject {
    @Published var results: [CategoryResult] = []
    @Published var selection = Set<URL>()
    @Published var scanning = false
    @Published var message: String?

    var selectedItems: [CleanItem] { results.flatMap(\.items).filter { selection.contains($0.url) } }

    func scan() {
        scanning = true
        results = []
        selection = []
        message = nil
        Task {
            for category in SystemCleaner.categories {
                let result = await Task.detached { SystemCleaner.scan(category) }.value
                results.append(result)
                if category.selectedByDefault { selection.formUnion(result.items.map(\.url)) }
            }
            scanning = false
        }
    }

    func clean() {
        let items = selectedItems
        scanning = true
        Task {
            let report = await Task.detached { FileSystem.remove(items) }.value
            message = summary(report)
            scanning = false
            let kept = report.failures.map(\.url)
            results = results.map { r in
                CategoryResult(category: r.category, items: r.items.filter { !items.contains($0) || kept.contains($0.url) })
            }
            selection.subtract(items.map(\.url).filter { !kept.contains($0) })
        }
    }

    func setAll(_ result: CategoryResult, on: Bool) {
        let urls = result.items.map(\.url)
        if on { selection.formUnion(urls) } else { selection.subtract(urls) }
    }

    func toggle(_ url: URL) {
        if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
    }
}

struct CleanupView: View {
    @StateObject private var model = CleanupModel()
    @State private var expanded = Set<String>()

    private func color(_ id: String) -> Color {
        switch id {
        case "caches": return Color(hex: 0x32C8B4)
        case "logs": return Color(hex: 0x8E8CFF)
        case "xcode": return Color(hex: 0x3D9BFF)
        case "devcaches": return Color(hex: 0x6FCF6F)
        case "mail": return Color(hex: 0xFFB84D)
        case "backups": return Color(hex: 0xFF7A8A)
        default: return Color(hex: 0xB0B6C4)
        }
    }

    private func card(_ result: CategoryResult) -> some View {
        let allOn = !result.items.isEmpty && result.items.allSatisfy { model.selection.contains($0.url) }
        let isOpen = expanded.contains(result.id)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Check(isOn: allOn) { model.setAll(result, on: !allOn) }
                BadgeIcon(symbol: result.category.symbol, color: color(result.id))
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.category.title).font(.headline)
                    Text(result.category.explanation).font(.caption).foregroundColor(.dim).lineLimit(2)
                }
                Spacer()
                Text(formatBytes(result.total)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Image(systemName: isOpen ? "chevron.up" : "chevron.down").foregroundColor(.dim)
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { expanded.remove(result.id) } else { expanded.insert(result.id) }
                }
            }
            if isOpen {
                Divider().background(Color.hairline)
                ForEach(result.items) { item in
                    ItemRow(item: item, isOn: model.selection.contains(item.url)) { model.toggle(item.url) }
                }
            }
        }
        .glass()
    }

    var body: some View {
        if model.results.isEmpty && !model.scanning {
            Hero(symbol: "sparkles", title: "Limpieza del sistema",
                 subtitle: "Busca cachés, logs, restos de desarrollo y más para recuperar espacio.",
                 buttonTitle: "Analizar") { model.scan() }
        } else if model.results.isEmpty {
            BusyView(text: "Analizando…")
        } else {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatBytes(model.results.reduce(0) { $0 + $1.total }))
                            .font(.system(size: 34, weight: .semibold))
                        Text("se pueden eliminar de forma segura").foregroundColor(.dim)
                    }
                    Spacer()
                    if model.scanning { ProgressView().scaleEffect(0.7).colorScheme(.dark) }
                    Button { model.scan() } label: { Label("Volver a analizar", systemImage: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundColor(.dim).disabled(model.scanning)
                }
                .padding(.horizontal, 24).padding(.bottom, 12)
                ScrollView {
                    LazyVStack(spacing: 10) { ForEach(model.results) { card($0) } }
                        .padding(.horizontal, 24).padding(.bottom, 16)
                }
                ActionFooter(selectedCount: model.selection.count, selectedBytes: model.selectedItems.reduce(0) { $0 + $1.size },
                             title: "Limpiar", busy: model.scanning, message: model.message) { model.clean() }
            }
        }
    }
}
