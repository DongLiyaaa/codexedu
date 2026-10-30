import SwiftUI
import AppKit

enum IslandTheme: String, CaseIterable {
    case glass = "苹果玻璃", dark = "暗色", white = "白色", cyberpunk = "赛博朋克", gta6 = "GTA6"
    case gemini = "Gemini", openai = "OpenAI", claude = "Claude", deepseek = "DeepSeek"
    var ink: Color {
        switch self {
        case .white: return Color(white: 0.12)
        case .claude: return Color(red: 0.25, green: 0.19, blue: 0.16)
        case .openai: return Color(red: 0.08, green: 0.24, blue: 0.20)
        case .glass: return .primary
        default: return .white
        }
    }
    var border: Color {
        switch self {
        case .cyberpunk: return Color(red: 0.2, green: 0.9, blue: 0.95)
        case .gta6: return Color(red: 1, green: 0.62, blue: 0.76)
        case .gemini: return Color(red: 0.64, green: 0.63, blue: 1)
        case .deepseek: return Color(red: 0.44, green: 0.68, blue: 1)
        case .claude: return Color(red: 0.75, green: 0.47, blue: 0.35).opacity(0.6)
        case .openai: return Color(red: 0.20, green: 0.47, blue: 0.37).opacity(0.4)
        case .white: return .black.opacity(0.15)
        default: return .white.opacity(0.18)
        }
    }
    var colors: [Color] {
        switch self {
        case .gemini: return [Color(red: 0.12, green: 0.23, blue: 0.51), Color(red: 0.34, green: 0.19, blue: 0.53), Color(red: 0.49, green: 0.19, blue: 0.38)]
        case .openai: return [Color(red: 0.91, green: 0.96, blue: 0.93), Color(red: 0.80, green: 0.91, blue: 0.85)]
        case .claude: return [Color(red: 0.98, green: 0.95, blue: 0.90), Color(red: 0.93, green: 0.85, blue: 0.77)]
        case .deepseek: return [Color(red: 0.08, green: 0.20, blue: 0.48), Color(red: 0.20, green: 0.36, blue: 0.76)]
        case .cyberpunk: return [Color(red: 0.055, green: 0.06, blue: 0.16), Color(red: 0.24, green: 0.04, blue: 0.3)]
        case .gta6: return [Color(red: 0.27, green: 0.10, blue: 0.39), Color(red: 0.48, green: 0.16, blue: 0.36), Color(red: 0.42, green: 0.20, blue: 0.16)]
        case .white: return [Color(white: 0.98), Color(white: 0.98)]
        default: return [Color(white: 0.045), Color(white: 0.045)]
        }
    }
}

// A transparent utility panel needs behind-window sampling, not an opaque hosting backdrop.
private struct DesktopGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ThemeSurface: ViewModifier {
    let theme: IslandTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if theme == .glass {
            if reduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.15), lineWidth: 0.7))
            } else if #available(macOS 26.0, *) {
                content.glassEffect(.clear, in: Capsule())
                    .background { DesktopGlass().clipShape(Capsule()) }
            } else {
                content.background { DesktopGlass().clipShape(Capsule()) }
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.6))
            }
        } else {
            content.background {
                Capsule().fill(LinearGradient(colors: theme.colors, startPoint: .leading, endPoint: .trailing))
            }.overlay(Capsule().strokeBorder(theme.border, lineWidth: 0.7))
        }
    }
}
