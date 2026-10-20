import SwiftUI
import MacDusterCore

@MainActor
final class UninstallerModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var loading = false
    @Published var current: InstalledApp?
    @Published var leftovers: [CleanItem] = []
    @Published var selection = Set<URL>()
    @Published var message: String?

    var appItem: CleanItem? {
        current.map { CleanItem(url: $0.url, size: $0.size, detail: "Aplicación") }
    }
    var allItems: [CleanItem] { (appItem.map { [$0] } ?? []) + leftovers }
    var selectedItems: [CleanItem] { allItems.filter { selection.contains($0.url) } }

    func load() {
        guard apps.isEmpty else { return }
        loading = true
        Task {
            apps = await Task.detached { AppUninstaller.listApps() }.value
            loading = false
        }
    }

    func select(_ app: InstalledApp) {
        current = app
        message = nil
        leftovers = []
        selection = [app.url]
        Task {
            let found = await Task.detached { AppUninstaller.findLeftovers(for: app) }.value
            guard current == app else { return }
            leftovers = found
            selection.formUnion(found.map(\.url))
        }
    }

    func uninstall() {
        let items = selectedItems
        Task {
            let report = await Task.detached { FileSystem.remove(items) }.value
            message = summary(report)
            if !report.failures.contains(where: { $0.url == current?.url }), let gone = current {
                apps.removeAll { $0 == gone }
                current = nil
            }
            leftovers = []
            selection = []
        }
    }

    func toggle(_ url: URL) {
        if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
    }
}

struct UninstallerView: View {
    @StateObject private var model = UninstallerModel()
    @State private var query = ""

    private var filtered: [InstalledApp] {
        query.isEmpty ? model.apps : model.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var appList: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.dim)
                TextField("Buscar app", text: $query).textFieldStyle(.plain)
            }
            .padding(8).glass(radius: 10)
            if model.loading {
                BusyView(text: "Cargando apps…")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { app in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 30, height: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name).lineLimit(1)
                                    Text(formatBytes(app.size)).font(.caption).foregroundColor(.dim)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 5).padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(model.current == app ? 0.08 : 0)))
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(app) }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 290)
    }

    private func detail(_ app: InstalledApp) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 24, weight: .bold))
                    Text([app.version.map { "Versión \($0)" }, formatBytes(app.size)].compactMap { $0 }.joined(separator: " · "))
                        .foregroundColor(.dim)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
            if app.isProtected {
                Text("\(app.name) es una app de Apple y no se puede desinstalar.")
                    .foregroundColor(.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.allItems) { item in
                            ItemRow(item: item, isOn: model.selection.contains(item.url)) { model.toggle(item.url) }
                        }
                    }
                    .glass()
                    .padding(.horizontal, 24).padding(.bottom, 16)
                }
                ActionFooter(selectedCount: model.selection.count, selectedBytes: model.selectedItems.reduce(0) { $0 + $1.size },
                             title: "Desinstalar", busy: false, message: model.message) { model.uninstall() }
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            appList
            Divider().background(Color.hairline)
            Group {
                if let app = model.current { detail(app) }
                else {
                    Hero(symbol: "app.badge.checkmark", title: "Desinstalador",
                         subtitle: model.message ?? "Elige una app de la lista para quitarla junto con todos sus restos.",
                         buttonTitle: "Elegir") { if let first = filtered.first { model.select(first) } }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.load() }
    }
}
