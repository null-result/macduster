import SwiftUI
import MacDusterCore

@MainActor
final class LargeFilesModel: ObservableObject {
    @Published var root = FileSystem.home
    @Published var minSizeMB = 100.0
    @Published var unusedDays = 0
    @Published var items: [CleanItem] = []
    @Published var selection = Set<URL>()
    @Published var scanning = false
    @Published var hasScanned = false
    @Published var message: String?

    var selectedItems: [CleanItem] { items.filter { selection.contains($0.url) } }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url { root = url }
    }

    func scan() {
        let query = LargeFileQuery(root: root, minSize: Int64(minSizeMB * 1_048_576), unusedForDays: unusedDays)
        scanning = true
        selection = []
        message = nil
        Task {
            items = await Task.detached { LargeFiles.scan(query) }.value
            scanning = false
            hasScanned = true
        }
    }

    func clean() {
        let chosen = selectedItems
        Task {
            let report = await Task.detached { FileSystem.remove(chosen) }.value
            message = summary(report)
            let failed = Set(report.failures.map(\.url))
            items.removeAll { chosen.contains($0) && !failed.contains($0.url) }
            selection = []
        }
    }

    func toggle(_ url: URL) {
        if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
    }
}

struct LargeFilesView: View {
    @StateObject private var model = LargeFilesModel()

    private var filters: some View {
        HStack(spacing: 10) {
            Button { model.chooseFolder() } label: {
                Label(model.root.lastPathComponent, systemImage: "folder").lineLimit(1)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 6).glass(radius: 9)
            .help(model.root.path)
            Picker("Tamaño mínimo", selection: $model.minSizeMB) {
                Text("50 MB").tag(50.0); Text("100 MB").tag(100.0); Text("500 MB").tag(500.0); Text("1 GB").tag(1024.0)
            }.frame(width: 190)
            Picker("Sin usar", selection: $model.unusedDays) {
                Text("Cualquiera").tag(0); Text("30 días").tag(30); Text("90 días").tag(90); Text("1 año").tag(365)
            }.frame(width: 180)
            Spacer()
        }
        .padding(.horizontal, 24).padding(.bottom, 12)
    }

    var body: some View {
        VStack(spacing: 0) {
            filters
            if model.scanning {
                BusyView(text: "Buscando…")
            } else if !model.hasScanned {
                Hero(symbol: "externaldrive.badge.minus", title: "Archivos grandes y antiguos",
                     subtitle: "Encuentra los archivos que más ocupan o que llevas tiempo sin usar.",
                     buttonTitle: "Buscar") { model.scan() }
            } else {
                HStack {
                    Text("\(model.items.count) archivos · \(formatBytes(model.items.reduce(0) { $0 + $1.size }))").foregroundColor(.dim)
                    Spacer()
                    Button { model.scan() } label: { Label("Volver a buscar", systemImage: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundColor(.dim)
                }
                .padding(.horizontal, 24).padding(.bottom, 8)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.items) { item in
                            ItemRow(item: item, isOn: model.selection.contains(item.url)) { model.toggle(item.url) }
                        }
                    }
                    .glass()
                    .padding(.horizontal, 24).padding(.bottom, 16)
                }
                ActionFooter(selectedCount: model.selection.count, selectedBytes: model.selectedItems.reduce(0) { $0 + $1.size },
                             title: "Eliminar", detail: "Irán a la Papelera.", busy: model.scanning, message: model.message) { model.clean() }
            }
        }
    }
}
