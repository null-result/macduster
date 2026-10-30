import SwiftUI
import MacDusterCore

/// Estado de la pantalla de recuperación. Los eventos del motor llegan desde hilos de fondo
/// y se vuelcan siempre por la cola principal, que conserva el orden.
final class RecoveryModel: ObservableObject {
    enum Phase { case idle, scanning, results }

    @Published var volumes: [DiskVolume] = []
    @Published var selected: DiskVolume?
    @Published var quick = true
    @Published var deep = true
    @Published var phase: Phase = .idle
    @Published var progress = 0.0
    @Published var status = ""
    @Published var error: String?
    @Published var category: FileCategory = .images
    @Published var selection = Set<Int64>()
    @Published var message: String?
    @Published var recovering = false
    @Published private(set) var byCategory: [FileCategory: [RecoverableFile]] = [:]

    private var device: RawDevice?
    private var token = CancelToken()

    var allFiles: [RecoverableFile] { byCategory.values.flatMap { $0 } }
    var selectedFiles: [RecoverableFile] { allFiles.filter { selection.contains($0.id) } }
    var visible: [RecoverableFile] { byCategory[category] ?? [] }
    var foundCount: Int { byCategory.values.reduce(0) { $0 + $1.count } }

    func count(_ c: FileCategory) -> Int { byCategory[c]?.count ?? 0 }
    func bytes(_ c: FileCategory) -> Int64 { (byCategory[c] ?? []).reduce(0) { $0 + $1.size } }

    func loadVolumes() {
        DispatchQueue.global().async {
            let list = DiskCatalog.list()
            DispatchQueue.main.async {
                self.volumes = list
                if let current = self.selected, !list.contains(current) { self.selected = nil }
            }
        }
    }

    func startScan() {
        guard let volume = selected else { return }
        var modes = Set<ScanMode>()
        if quick { modes.insert(.quick) }
        if deep { modes.insert(.deep) }
        guard !modes.isEmpty else { return }

        byCategory = [:]
        selection = []
        message = nil
        error = nil
        progress = 0
        status = "Abriendo \(volume.title)…"
        phase = .scanning
        let token = CancelToken()
        self.token = token

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let device = try RecoveryEngine.open(volume) // puede pedir la contraseña de administrador
                DispatchQueue.main.async { self.device = device }
                RecoveryEngine.scan(device: device, modes: modes, token: token) { event in
                    DispatchQueue.main.async { self.handle(event) }
                }
                DispatchQueue.main.async { self.finishScan() }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.phase = .idle
                }
            }
        }
    }

    private func handle(_ event: ScanEvent) {
        switch event {
        case .phase(let text): status = text
        case .progress(let value): progress = value
        case .found(let batch):
            var map = byCategory
            for file in batch { map[file.category, default: []].append(file) }
            byCategory = map
        }
    }

    private func finishScan() {
        phase = .results
        if let first = FileCategory.allCases.filter({ count($0) > 0 }).max(by: { count($0) < count($1) }) { category = first }
    }

    func cancelScan() { token.cancel() }

    func reset() {
        token.cancel()
        device = nil
        byCategory = [:]
        selection = []
        message = nil
        phase = .idle
    }

    func toggle(_ id: Int64) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    var allVisibleSelected: Bool { !visible.isEmpty && visible.allSatisfy { selection.contains($0.id) } }

    func toggleAllVisible() {
        if allVisibleSelected { visible.forEach { selection.remove($0.id) } } else { visible.forEach { selection.insert($0.id) } }
    }

    func chooseFolderAndRecover() {
        guard let volume = selected, let device else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Recuperar aquí"
        panel.message = "Elige dónde guardar los archivos. Debe ser un disco distinto del que estás recuperando."
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let chosen = selectedFiles
        let total = chosen.reduce(Int64(0)) { $0 + $1.size }
        recovering = true
        message = "Comprobando destino…"
        DispatchQueue.global(qos: .userInitiated).async {
            if RecoveryEngine.destinationConflicts(folder, with: volume) {
                DispatchQueue.main.async {
                    self.message = RecoveryError.destinationOnSource.localizedDescription
                    self.recovering = false
                }
                return
            }
            let report = RecoveryEngine.recover(chosen, from: device, to: folder, token: CancelToken()) { done in
                DispatchQueue.main.async { self.message = "Recuperando… \(formatBytes(done)) de \(formatBytes(total))" }
            }
            DispatchQueue.main.async {
                var text = "Recuperados \(report.recovered) archivos (\(formatBytes(report.bytes)))"
                if !report.failures.isEmpty { text += " · \(report.failures.count) con errores" }
                self.message = text
                self.recovering = false
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
        }
    }
}

struct RecoveryView: View {
    @StateObject private var model = RecoveryModel()
    @Environment(\.accent) private var accent

    var body: some View {
        Group {
            switch model.phase {
            case .idle: setup
            case .scanning: scanning
            case .results: results
            }
        }
        .onAppear { if model.volumes.isEmpty { model.loadVolumes() } }
    }

    // MARK: Elegir disco

    private var setup: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "lifepreserver").font(.system(size: 44, weight: .ultraLight)).foregroundColor(accent)
                Text("Recuperar archivos borrados").font(.system(size: 24, weight: .semibold))
                Text("Elige el disco o la tarjeta donde estaban. Funciona mejor en discos externos, tarjetas SD y memorias USB.")
                    .multilineTextAlignment(.center).foregroundColor(.dim).frame(maxWidth: 480)
            }
            .padding(.top, 8).padding(.bottom, 16)

            HStack {
                Text("DISCOS").font(.system(size: 10, weight: .medium)).kerning(1.2).foregroundColor(.dim)
                Spacer()
                Button { model.loadVolumes() } label: { Label("Actualizar", systemImage: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundColor(.dim).font(.caption)
            }
            .padding(.horizontal, 24).padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.volumes) { volume in
                        VolumeRow(volume: volume, isOn: model.selected == volume) { model.selected = volume }
                    }
                }
                .glass()
                .padding(.horizontal, 24)
            }

            VStack(spacing: 10) {
                HStack(spacing: 18) {
                    Toggle("Escaneo rápido", isOn: $model.quick)
                        .help("Lee el índice del disco: conserva nombres y carpetas (FAT32 y exFAT).")
                    Toggle("Escaneo profundo", isOn: $model.deep)
                        .help("Busca el contenido sector a sector. Más lento; no conserva nombres.")
                }
                .toggleStyle(.checkbox)
                if let selected = model.selected, selected.isWholeDisk || !["MS-DOS FAT32", "ExFAT", "exFAT"].contains(selected.filesystem), model.quick {
                    Text("El escaneo rápido solo está disponible al elegir una partición FAT32 o exFAT; en el resto se usará el profundo.")
                        .font(.caption).foregroundColor(.dim).multilineTextAlignment(.center)
                }
                if let selected = model.selected, !selected.isExternal {
                    Text("En el disco interno del Mac el cifrado y TRIM suelen hacer irrecuperables los archivos borrados.")
                        .font(.caption).foregroundColor(Color(hex: 0xFBBF24)).multilineTextAlignment(.center)
                }
                if let error = model.error {
                    Text(error).font(.caption).foregroundColor(Color(hex: 0xF87171)).multilineTextAlignment(.center)
                }
                CircleButton(title: "Escanear", size: 96, disabled: model.selected == nil || (!model.quick && !model.deep)) { model.startScan() }
            }
            .padding(.vertical, 14).padding(.horizontal, 24)
        }
    }

    // MARK: Escaneando

    private var scanning: some View {
        VStack(spacing: 18) {
            Spacer()
            RingGauge(fraction: model.progress, caption: "escaneado", size: 140)
            Text(model.status).foregroundColor(.dim)
            Text("\(model.foundCount) archivos encontrados").font(.system(size: 18, weight: .semibold)).monospacedDigit()
            HStack(spacing: 10) {
                ForEach(FileCategory.allCases) { c in
                    VStack(spacing: 2) {
                        BadgeIcon(symbol: c.symbol, color: accent, size: 34)
                        Text("\(model.count(c))").font(.caption).monospacedDigit().foregroundColor(.dim)
                    }
                }
            }
            HStack(spacing: 12) {
                Button("Detener y ver lo encontrado") { model.cancelScan() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Resultados

    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.foundCount) archivos · \(model.selected?.title ?? "")").foregroundColor(.dim)
                Spacer()
                Button { model.reset() } label: { Label("Nuevo escaneo", systemImage: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundColor(.dim)
            }
            .padding(.horizontal, 24).padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FileCategory.allCases) { c in
                        CategoryTile(category: c, count: model.count(c), bytes: model.bytes(c), isOn: model.category == c) { model.category = c }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 10)

            if model.visible.isEmpty {
                Text("No se encontró nada en esta categoría.").foregroundColor(.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Check(isOn: model.allVisibleSelected) { model.toggleAllVisible() }
                    Text("Seleccionar todo").foregroundColor(.dim)
                    Spacer()
                }
                .padding(.horizontal, 38).padding(.bottom, 4)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visible) { file in
                            RecoverableRow(file: file, isOn: model.selection.contains(file.id)) { model.toggle(file.id) }
                        }
                    }
                    .glass()
                    .padding(.horizontal, 24).padding(.bottom, 16)
                }
            }

            VStack(spacing: 6) {
                CircleButton(title: "Recuperar", subtitle: formatBytes(model.selectedFiles.reduce(0) { $0 + $1.size }), size: 96,
                             disabled: model.selection.isEmpty || model.recovering) { model.chooseFolderAndRecover() }
                Text(model.message ?? "\(model.selection.count) archivos seleccionados · el escaneo profundo incluye también archivos que no están borrados")
                    .font(.caption).foregroundColor(.dim).multilineTextAlignment(.center)
            }
            .padding(.vertical, 12).padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(Color.sidebarCanvas.opacity(0.6))
            .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
        }
    }
}

private struct VolumeRow: View {
    let volume: DiskVolume
    let isOn: Bool
    let select: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 12) {
            BadgeIcon(symbol: volume.isExternal ? "externaldrive" : "internaldrive", color: accent, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.title).lineLimit(1)
                Text("\(volume.identifier) · \(volume.isWholeDisk ? "Disco completo" : volume.filesystem)")
                    .font(.caption).foregroundColor(.dim).lineLimit(1)
            }
            Spacer()
            Text(formatBytes(volume.size)).monospacedDigit().foregroundColor(.dim)
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20)).foregroundColor(isOn ? accent : Color.white.opacity(0.3))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(isOn ? accent.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }
}

private struct CategoryTile: View {
    let category: FileCategory
    let count: Int
    let bytes: Int64
    let isOn: Bool
    let select: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                BadgeIcon(symbol: category.symbol, color: accent, size: 30)
                Text(category.rawValue).font(.system(size: 12, weight: isOn ? .semibold : .regular))
                Text("\(count) · \(formatBytes(bytes))").font(.system(size: 10)).foregroundColor(.dim).monospacedDigit()
            }
            .frame(width: 112).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(isOn ? 0.08 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isOn ? accent.opacity(0.7) : Color.hairline))
        }
        .buttonStyle(.plain)
        .opacity(count == 0 ? 0.45 : 1)
    }
}

private struct RecoverableRow: View {
    let file: RecoverableFile
    let isOn: Bool
    let toggle: () -> Void

    private var detail: String {
        var parts = [file.source == .quick ? (file.folder.flatMap { $0.isEmpty ? nil : $0 } ?? "Raíz del disco") : "Reconstruido por firma"]
        if file.chance == .low { parts.append("Posiblemente sobrescrito") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Check(isOn: isOn, action: toggle)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.caption)
                    .foregroundColor(file.chance == .low ? Color(hex: 0xFBBF24) : .dim).lineLimit(1)
            }
            Spacer()
            Text(formatBytes(file.size)).monospacedDigit().foregroundColor(.dim)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}
