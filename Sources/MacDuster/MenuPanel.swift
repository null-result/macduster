import SwiftUI
import CoreWLAN
import MacDusterCore

/// Datos en vivo del panel de la barra de menú; solo muestrea mientras está abierto.
@MainActor
final class MenuModel: ObservableObject {
    @Published var disk: DiskStatus?
    @Published var suggestions: [CleanupSuggestion] = []
    @Published var memory = SystemStats.memory()
    @Published var cpu = 0.0
    @Published var cpuTemperature: Double?
    @Published var down = 0.0
    @Published var up = 0.0
    @Published var battery: BatteryStatus?
    @Published var wifi: String?
    enum SpeedState: Equatable { case idle, running, done(SpeedTestResult), failed }
    @Published var speedTest = SpeedState.idle
    @Published var launchAtLogin = LaunchAtLogin.isEnabled
    @Published var notifications = Preferences.notificationsEnabled

    private var cpuSampler = CPUSampler()
    private var networkSampler = NetworkSampler()
    private var timer: Timer?

    func start() {
        launchAtLogin = LaunchAtLogin.isEnabled
        notifications = Preferences.notificationsEnabled
        _ = cpuSampler.usage()
        _ = networkSampler.speed()
        sample()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in Task { @MainActor in self.sample() } }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func runSpeedTest() {
        guard speedTest != .running else { return }
        speedTest = .running
        Task {
            let result = await Task.detached { SpeedTest.run() }.value
            speedTest = result.map { .done($0) } ?? .failed
        }
    }

    private func sample() {
        memory = SystemStats.memory()
        cpu = cpuSampler.usage()
        cpuTemperature = Temperature.cpu()
        (down, up) = networkSampler.speed()
        battery = SystemStats.battery()
        if let interface = CWWiFiClient.shared().interface(), interface.powerOn() {
            let rate = Int(interface.transmitRate())
            let name = interface.ssid()
            wifi = [name, rate > 0 ? "\(rate) Mbps" : nil].compactMap { $0 }.joined(separator: " · ")
            if wifi?.isEmpty == true { wifi = "Wi-Fi" }
        } else {
            wifi = nil
        }
    }
}

private func speedText(_ bytesPerSecond: Double) -> String { formatBytes(Int64(bytesPerSecond)) + "/s" }

struct MenuPanel: View {
    @ObservedObject var model: MenuModel
    let onOpen: () -> Void
    let onEmptyTrash: () -> Void
    let onFreeMemory: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            ForEach(Array(model.suggestions.enumerated()), id: \.offset) { _, s in banner(s) }
            diskCard
            HStack(spacing: 10) { memoryTile; cpuTile }
            HStack(spacing: 10) { networkTile; batteryTile }
            speedCard
            HStack(alignment: .bottom, spacing: 10) {
                panelButton("Abrir MacDuster", symbol: "arrow.up.forward.app", prominent: true, action: onOpen)
                VStack(spacing: 6) {
                    HStack {
                        Text("RAM usada").font(.caption).foregroundColor(.dim)
                        Spacer()
                        Text("\(Int(model.memory.fraction * 100)) %").font(.caption).fontWeight(.semibold).monospacedDigit()
                    }
                    bar(model.memory.fraction, color: Color(hex: 0xA78BFA))
                    panelButton("Liberar RAM", symbol: "memorychip", action: onFreeMemory)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(Color.canvas)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Text("MacDuster").font(.system(size: 14, weight: .semibold)).kerning(0.3)
            Spacer()
            Menu {
                Toggle("Iniciar al arrancar el Mac", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { LaunchAtLogin.setEnabled($0); model.launchAtLogin = LaunchAtLogin.isEnabled }))
                Toggle("Avisarme de limpiezas", isOn: Binding(
                    get: { model.notifications },
                    set: { Preferences.notificationsEnabled = $0; model.notifications = $0 }))
                Divider()
                Button("Salir de MacDuster", action: onQuit)
            } label: { Image(systemName: "ellipsis.circle").foregroundColor(.dim) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 2)
    }

    private func banner(_ suggestion: CleanupSuggestion) -> some View {
        let text: String
        switch suggestion {
        case .lowDisk: text = "Queda poco espacio: conviene limpiar"
        case .fullTrash: text = "La Papelera está muy llena"
        }
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Color(hex: 0xFBBF24))
            Text(text).font(.caption)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0xFBBF24, opacity: 0.12)))
    }

    private var diskCard: some View {
        let accent = Color(hex: 0x2DD4BF)
        let total = model.disk?.total ?? 0, free = model.disk?.available ?? 0
        let used = Double(total - free) / Double(max(total, 1))
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                RingGauge(fraction: used, caption: "usado", size: 76).environment(\.accent, accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Disco").font(.caption).foregroundColor(.dim)
                    Text(model.disk == nil ? "Calculando…" : "\(formatBytes(free)) libres").font(.system(size: 18, weight: .semibold))
                    if total > 0 { Text("de \(formatBytes(total))").font(.caption).foregroundColor(.dim) }
                }
                Spacer()
            }
            Divider().background(Color.hairline)
            HStack {
                Image(systemName: "trash").foregroundColor(.dim)
                Text("Papelera").font(.callout)
                Spacer()
                Text(formatBytes(model.disk?.trash ?? 0)).monospacedDigit().foregroundColor(.dim)
                Button("Vaciar…", action: onEmptyTrash)
                    .buttonStyle(.plain).font(.callout).foregroundColor(accent)
                    .disabled((model.disk?.trash ?? 0) == 0)
            }
        }
        .padding(14).glass()
    }

    private func bar(_ fraction: Double, color: Color) -> some View {
        GeometryReader { g in
            Capsule().fill(Color.white.opacity(0.07))
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: g.size.width * min(max(fraction, 0), 1))
                        .animation(.easeOut(duration: 0.4), value: fraction)
                }
        }
        .frame(height: 3)
    }

    private var memoryTile: some View {
        let c = Color(hex: 0xA78BFA)
        return metricTile("Memoria", symbol: "memorychip", color: c, value: "\(Int(model.memory.fraction * 100)) %",
                          detail: "\(formatBytes(model.memory.used)) de \(formatBytes(model.memory.total))", fraction: model.memory.fraction)
    }

    private var cpuTile: some View {
        metricTile("Procesador", symbol: "cpu", color: Color(hex: 0xFBBF24), value: "\(Int(model.cpu * 100)) %",
                   detail: model.cpuTemperature.map { "\(Int($0.rounded())) °C" } ?? "en uso", fraction: model.cpu)
    }

    private func metricTile(_ title: String, symbol: String, color: Color, value: String, detail: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundColor(color).font(.system(size: 11, weight: .semibold))
                Text(title).font(.caption).foregroundColor(.dim)
            }
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            Text(detail).font(.caption2).foregroundColor(.dim).lineLimit(1)
            bar(fraction, color: color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private var networkTile: some View {
        let c = Color(hex: 0x60A5FA)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wifi").foregroundColor(c).font(.system(size: 11, weight: .semibold))
                Text("Red").font(.caption).foregroundColor(.dim)
            }
            Label(speedText(model.down), systemImage: "arrow.down").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            Label(speedText(model.up), systemImage: "arrow.up").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            Text(model.wifi ?? "Sin Wi-Fi").font(.caption2).foregroundColor(.dim).lineLimit(1).truncationMode(.tail)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    @ViewBuilder private var batteryTile: some View {
        let c = Color(hex: 0x4ADE80)
        if let b = model.battery {
            metricTile("Batería", symbol: b.charging ? "battery.100.bolt" : "battery.75", color: c, value: "\(b.level) %",
                       detail: b.charging ? "Cargando" : (b.pluggedIn ? "Conectada" : "Con batería"), fraction: Double(b.level) / 100)
        } else {
            metricTile("Alimentación", symbol: "powerplug", color: c, value: "Red eléctrica", detail: "Sin batería", fraction: 1)
        }
    }

    private func mbps(_ bitsPerSecond: Double) -> String {
        let m = bitsPerSecond / 1_000_000
        return m >= 100 ? String(format: "%.0f", m) : String(format: "%.1f", m)
    }

    private func speedValue(_ title: String, symbol: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundColor(color)
                Text(title).font(.caption).foregroundColor(.dim)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                Text(unit).font(.caption).foregroundColor(.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speedCard: some View {
        let accent = Color(hex: 0x60A5FA)
        return VStack(spacing: 12) {
            HStack {
                Image(systemName: "speedometer").foregroundColor(accent).font(.system(size: 11, weight: .semibold))
                Text("Velocidad de conexión").font(.caption).foregroundColor(.dim)
                Spacer()
                if model.speedTest != .running {
                    Button(model.speedTest == .idle ? "Probar" : "Repetir") { model.runSpeedTest() }
                        .buttonStyle(.plain).font(.callout).foregroundColor(accent)
                }
            }
            switch model.speedTest {
            case .idle:
                Text("Mide la descarga, la subida y la agilidad de tu conexión.").font(.caption).foregroundColor(.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .running:
SpeedTestAnimation(accent: accent)
            case .failed:
                Text("No se pudo medir. Comprueba tu conexión.").font(.caption).foregroundColor(Color(hex: 0xF87171))
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .done(let r):
                HStack(spacing: 10) {
                    speedValue("Descarga", symbol: "arrow.down", value: mbps(r.download), unit: "Mbps", color: accent)
                    speedValue("Subida", symbol: "arrow.up", value: mbps(r.upload), unit: "Mbps", color: Color(hex: 0xF472B6))
                    if let rpm = r.responsiveness {
                        speedValue("Respuesta", symbol: "bolt.fill", value: "\(rpm)", unit: "RPM", color: Color(hex: 0xFBBF24))
                    }
                }
            }
        }
        .padding(14).glass()
    }

    private func panelButton(_ title: String, symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let accent = Color(hex: 0x2DD4BF)
        return Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(prominent ? accent.opacity(0.18) : Color.surface))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(prominent ? accent.opacity(0.6) : Color.hairline))
                .foregroundColor(prominent ? accent : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// Anillo giratorio y ecualizador mientras se mide la conexión.
struct SpeedTestAnimation: View {
    let accent: Color
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 4)
                Circle().trim(from: 0, to: 0.3)
                    .stroke(AngularGradient(colors: [accent.opacity(0), accent], center: .center, startAngle: .degrees(0), endAngle: .degrees(108)),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 13, weight: .semibold)).foregroundColor(accent)
                    .scaleEffect(pulse ? 1.12 : 0.9)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 8) {
                Text("Midiendo tu conexión…").font(.callout)
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(0..<24, id: \.self) { i in
                            Capsule().fill(accent.opacity(0.35 + 0.65 * abs(sin(t * 2.4 + Double(i) * 0.45))))
                                .frame(width: 4, height: 4 + 16 * abs(sin(t * 3.1 + Double(i) * 0.55)))
                        }
                    }
                    .frame(height: 20)
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
