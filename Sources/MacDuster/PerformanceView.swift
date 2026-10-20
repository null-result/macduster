import SwiftUI
import MacDusterCore

private enum PerformanceTab: String, CaseIterable, Identifiable {
    case processes = "Memoria y procesos"
    case startup = "Inicio"
    case maintenance = "Mantenimiento"
    var id: String { rawValue }
}

struct PerformanceView: View {
    @State private var tab: PerformanceTab = .processes

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(PerformanceTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 480)
            .padding(.horizontal, 24).padding(.bottom, 12)
            switch tab {
            case .processes: ProcessesPane()
            case .startup: StartupPane()
            case .maintenance: MaintenancePane()
            }
        }
    }
}

// MARK: - Memoria y procesos

@MainActor
final class ProcessesModel: ObservableObject {
    @Published var memory = SystemStats.memory()
    @Published var processes: [RunningProcess] = []

    func refresh() async {
        let result = await Task.detached { (SystemStats.memory(), Processes.top()) }.value
        memory = result.0
        processes = result.1
    }

    func quit(_ process: RunningProcess) {
        Processes.quit(pid: process.pid)
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refresh()
        }
    }
}

private struct ProcessesPane: View {
    @StateObject private var model = ProcessesModel()
    @State private var pending: RunningProcess?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                RingGauge(fraction: model.memory.fraction, caption: "memoria")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memoria en uso").font(.headline)
                    Text("\(formatBytes(model.memory.used)) de \(formatBytes(model.memory.total))")
                        .font(.system(size: 22, weight: .bold))
                    Text("Cierra los procesos que más consumen para liberar memoria.").font(.caption).foregroundColor(.dim)
                }
                Spacer()
            }
            .padding(16).glass()
            .padding(.horizontal, 24)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.processes) { process in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(process.name).lineLimit(1)
                                Text("PID \(process.pid) · CPU \(String(format: "%.1f", process.cpu))%").font(.caption).foregroundColor(.dim)
                            }
                            Spacer()
                            Text(formatBytes(process.memory)).monospacedDigit().foregroundColor(.dim)
                            Button("Cerrar") { pending = process }.buttonStyle(.plain)
                                .padding(.horizontal, 10).padding(.vertical, 4).glass(radius: 8)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                }
                .glass()
                .padding(.horizontal, 24).padding(.bottom, 16)
            }
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .alert(item: $pending) { process in
            Alert(title: Text("¿Cerrar \(process.name)?"),
                  message: Text("Se perderán los cambios sin guardar de ese proceso."),
                  primaryButton: .destructive(Text("Cerrar")) { model.quit(process) },
                  secondaryButton: .cancel(Text("Cancelar")))
        }
    }
}

// MARK: - Inicio

@MainActor
final class StartupModel: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var loading = false
    @Published var message: String?

    func load() {
        loading = true
        Task {
            items = await Task.detached { StartupItems.list() }.value
            loading = false
        }
    }

    func set(_ item: StartupItem, enabled: Bool) {
        Task {
            let ok = await Task.detached { StartupItems.setEnabled(item, enabled) }.value
            message = ok ? (enabled ? "Activado: se aplicará en el próximo inicio de sesión." : "Desactivado: \(item.label)")
                         : "No se pudo cambiar \(item.label)."
            load()
        }
    }

    func remove(_ item: StartupItem) {
        Task {
            let ok = await Task.detached { StartupItems.removeLoginItem(item) }.value
            message = ok ? "Quitado: \(item.label)" : "No se pudo quitar \(item.label) (¿falta el permiso de Automatización?)."
            load()
        }
    }
}

private struct StartupPane: View {
    @StateObject private var model = StartupModel()

    private func section(_ title: String, _ kind: StartupItem.Kind) -> some View {
        let items = model.items.filter { $0.kind == kind }
        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).padding(.leading, 4)
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label).lineLimit(1).truncationMode(.middle)
                                    if let program = item.program {
                                        Text(program).font(.caption).foregroundColor(.dim).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                Spacer()
                                if item.canToggle {
                                    Toggle("", isOn: Binding(get: { item.enabled }, set: { model.set(item, enabled: $0) }))
                                        .labelsHidden().toggleStyle(.switch)
                                } else if item.kind == .loginItem {
                                    Button("Quitar") { model.remove(item) }.buttonStyle(.plain)
                                        .padding(.horizontal, 10).padding(.vertical, 4).glass(radius: 8)
                                } else {
                                    Text("Solo lectura").font(.caption).foregroundColor(.dim)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                    .glass()
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.loading && model.items.isEmpty {
                BusyView(text: "Buscando elementos de inicio…")
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        section("Elementos de inicio de sesión", .loginItem)
                        section("Agentes del usuario", .userAgent)
                        section("Agentes de todos los usuarios", .globalAgent)
                        section("Servicios del sistema", .daemon)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 16)
                }
            }
            HStack {
                Text(model.message ?? "Desactiva lo que no necesites al arrancar para acelerar el inicio.")
                    .font(.callout).foregroundColor(.dim)
                Spacer()
                Button { model.load() } label: { Label("Actualizar", systemImage: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundColor(.dim)
            }
            .padding(.horizontal, 24).padding(.vertical, 12).background(Color.sidebarCanvas.opacity(0.6))
        }
        .onAppear { model.load() }
    }
}

// MARK: - Mantenimiento

@MainActor
final class MaintenanceModel: ObservableObject {
    @Published var running: String?
    @Published var results: [String: String] = [:]

    func run(_ task: MaintenanceTask) {
        running = task.id
        Task {
            let result = await Task.detached { task.run() }.value
            results[task.id] = result.ok ? "Hecho" : (result.output.isEmpty ? "Error" : "Error: \(result.output)")
            running = nil
        }
    }
}

private struct MaintenancePane: View {
    @StateObject private var model = MaintenanceModel()

    private func symbol(_ id: String) -> (String, Color) {
        switch id {
        case "purge": return ("memorychip", Color(hex: 0x6FCF6F))
        case "dns": return ("network", Color(hex: 0x3D9BFF))
        case "spotlight": return ("magnifyingglass", Color(hex: 0x8E8CFF))
        case "launchservices": return ("square.grid.2x2", Color(hex: 0xFFB84D))
        case "quicklook": return ("eye", Color(hex: 0x32C8B4))
        case "snapshots": return ("clock.arrow.circlepath", Color(hex: 0xFF7A8A))
        default: return ("arrow.triangle.2.circlepath", Color(hex: 0xB0B6C4))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(MaintenanceTask.all) { task in
                    let (icon, color) = symbol(task.id)
                    HStack(spacing: 12) {
                        BadgeIcon(symbol: icon, color: color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).font(.headline)
                            Text(task.explanation).font(.caption).foregroundColor(.dim)
                            if task.needsAdmin { Text("Requiere contraseña de administrador").font(.caption2).foregroundColor(Color(hex: 0xFFC94D)) }
                            if let result = model.results[task.id] { Text(result).font(.caption).lineLimit(2) }
                        }
                        Spacer()
                        if model.running == task.id { ProgressView().controlSize(.small).colorScheme(.dark) }
                        Button("Ejecutar") { model.run(task) }.buttonStyle(.plain)
                            .padding(.horizontal, 12).padding(.vertical, 5).glass(radius: 8)
                            .disabled(model.running != nil).opacity(model.running != nil ? 0.5 : 1)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            .glass()
            .padding(.horizontal, 24).padding(.bottom, 16)
        }
    }
}
