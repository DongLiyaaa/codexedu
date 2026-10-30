import SwiftUI

enum IslandTheme: String, CaseIterable {
    case glass = "苹果玻璃", dark = "暗色", white = "白色", cyberpunk = "赛博朋克", gta6 = "GTA6"
    var ink: Color {
        switch self {
        case .white: return Color(white: 0.12)
        case .glass: return .primary
        default: return .white
        }
    }
    var border: Color {
        switch self {
        case .cyberpunk: return Color(red: 0.2, green: 0.9, blue: 0.95)
        case .gta6: return Color(red: 1, green: 0.62, blue: 0.76)
        case .white: return .black.opacity(0.15)
        default: return .white.opacity(0.18)
        }
    }
}

struct ThemeSurface: ViewModifier {
    let theme: IslandTheme
    @ViewBuilder func body(content: Content) -> some View {
        if theme == .glass {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: Capsule())
            } else {
                content.background(.regularMaterial, in: Capsule())
            }
        } else {
            content.background {
                switch theme {
                case .cyberpunk:
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.055, green: 0.06, blue: 0.16), Color(red: 0.24, green: 0.04, blue: 0.3)], startPoint: .leading, endPoint: .trailing))
                case .gta6:
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.27, green: 0.10, blue: 0.39), Color(red: 0.48, green: 0.16, blue: 0.36), Color(red: 0.42, green: 0.20, blue: 0.16)], startPoint: .leading, endPoint: .trailing))
                case .white: Capsule().fill(Color(white: 0.98))
                default: Capsule().fill(Color(white: 0.045))
                }
            }.overlay(Capsule().strokeBorder(theme.border, lineWidth: 0.7))
        }
    }
}
