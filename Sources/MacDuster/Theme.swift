import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
    static let dim = Color.white.opacity(0.55)
    static let hairline = Color.white.opacity(0.08)
    static let surface = Color.white.opacity(0.045)
    static let canvas = Color(hex: 0x141416)
    static let sidebarCanvas = Color(hex: 0x0F0F11)
}

private struct AccentKey: EnvironmentKey { static let defaultValue = Color(hex: 0x2DD4BF) }

extension EnvironmentValues {
    /// Color de acento del módulo activo.
    var accent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

extension Module {
    /// Único color vivo de cada módulo; el resto de la interfaz es neutro.
    var accent: Color {
        switch self {
        case .cleanup: return Color(hex: 0x2DD4BF)
        case .uninstaller: return Color(hex: 0xF472B6)
        case .largeFiles: return Color(hex: 0x60A5FA)
        case .recovery: return Color(hex: 0xA78BFA)
        case .performance: return Color(hex: 0xFBBF24)
        }
    }
}

/// Lienzo grafito con un resplandor muy tenue del color del módulo.
struct ModuleBackground: View {
    let module: Module

    var body: some View {
        ZStack {
            Color.canvas
            ForEach(Module.allCases) { m in
                RadialGradient(colors: [m.accent.opacity(0.14), .clear], center: .topTrailing, startRadius: 0, endRadius: 560)
                    .opacity(m == module ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: module)
        .ignoresSafeArea()
    }
}

extension View {
    /// Tarjeta sobria: superficie translúcida y filo fino.
    func glass(radius: CGFloat = 14) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.hairline))
    }
}

/// Botón circular con anillo del color de acento.
struct CircleButton: View {
    let title: String
    var subtitle: String?
    var size: CGFloat = 112
    var disabled = false
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(accent.opacity(hover ? 0.22 : 0.12))
                Circle().strokeBorder(accent.opacity(0.85), lineWidth: 1.5)
                VStack(spacing: 2) {
                    Text(title).font(.system(size: size * 0.17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    if let subtitle { Text(subtitle).font(.system(size: size * 0.11)).foregroundColor(.dim).lineLimit(1) }
                }
                .padding(.horizontal, 8)
            }
            .frame(width: size, height: size)
            .scaleEffect(hover ? 1.04 : 1)
            .shadow(color: accent.opacity(hover ? 0.35 : 0.18), radius: 18)
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .opacity(disabled ? 0.35 : 1)
        .disabled(disabled)
    }
}

/// Pantalla de inicio de un módulo: icono grande, texto y botón circular.
struct Hero: View {
    let symbol: String
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().strokeBorder(Color.hairline, lineWidth: 1).frame(width: 200, height: 200)
                Circle().fill(Color.surface).frame(width: 150, height: 150)
                Circle().strokeBorder(accent.opacity(0.25), lineWidth: 1).frame(width: 150, height: 150)
                Image(systemName: symbol).font(.system(size: 64, weight: .ultraLight)).foregroundColor(accent)
            }
            Text(title).font(.system(size: 26, weight: .semibold))
            Text(subtitle).multilineTextAlignment(.center).foregroundColor(.dim).frame(maxWidth: 420)
            CircleButton(title: buttonTitle, action: action).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct BusyView: View {
    let text: String
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(1.4).colorScheme(.dark)
            Text(text).foregroundColor(.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Check: View {
    let isOn: Bool
    let action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(isOn ? accent : Color.white.opacity(0.3))
        }
        .buttonStyle(.plain)
    }
}

/// Icono tintado sobre baldosa suave, para categorías y tareas.
struct BadgeIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.opacity(0.14)))
    }
}

struct RingGauge: View {
    let fraction: Double
    let caption: String
    var size: CGFloat = 120

    @Environment(\.accent) private var accent
    private var color: Color { fraction > 0.85 ? Color(hex: 0xF87171) : (fraction > 0.7 ? Color(hex: 0xFBBF24) : accent) }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.07), lineWidth: 8)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            VStack(spacing: 0) {
                Text("\(Int(fraction * 100)) %").font(.system(size: size * 0.22, weight: .bold))
                Text(caption).font(.caption).foregroundColor(.dim)
            }
        }
        .frame(width: size, height: size)
    }
}
