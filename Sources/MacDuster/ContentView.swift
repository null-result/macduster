import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case cleanup = "Limpieza"
    case uninstaller = "Desinstalador"
    case largeFiles = "Archivos grandes"
    case recovery = "Recuperación"
    case performance = "Rendimiento"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cleanup: return "sparkles"
        case .uninstaller: return "app.badge.checkmark"
        case .largeFiles: return "externaldrive.badge.minus"
        case .recovery: return "lifepreserver"
        case .performance: return "speedometer"
        }
    }
}

struct ContentView: View {
    @State private var module: Module = .cleanup

    var body: some View {
        ZStack {
            ModuleBackground(module: module)
            HStack(spacing: 0) {
                sidebar
                Group {
                    switch module {
                    case .cleanup: CleanupView()
                    case .uninstaller: UninstallerView()
                    case .largeFiles: LargeFilesView()
                    case .recovery: RecoveryView()
                    case .performance: PerformanceView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 28)
            }
        }
        .environment(\.accent, module.accent)
        .tint(module.accent)
        .preferredColorScheme(.dark)
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text("Mac").font(.system(size: 24, weight: .light)).kerning(0.2)
                Text("Duster").font(.system(size: 24, weight: .bold)).kerning(0.2).foregroundColor(module.accent)
            }
            Text("TU MAC COMO NUEVO").font(.system(size: 9.5, weight: .medium)).kerning(1.4).foregroundColor(.dim)
        }
        .padding(.horizontal, 10).padding(.bottom, 20)
        .animation(.easeInOut(duration: 0.3), value: module)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            brand
            ForEach(Module.allCases) { m in
                Button { module = m } label: {
                    HStack(spacing: 10) {
                        BadgeIcon(symbol: m.symbol, color: m.accent, size: 28)
                        Text(m.rawValue).font(.system(size: 13, weight: module == m ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(module == m ? 0.07 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 44)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(Color.sidebarCanvas.opacity(0.9))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.hairline).frame(width: 1) }
    }
}
