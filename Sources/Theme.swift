import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// Premium dark "glass cockpit" design system — one source of truth for the app's look.
enum Theme {
    // Surfaces (deep navy, not pure black)
    static let bg         = Color(.sRGB, red: 0.043, green: 0.071, blue: 0.125)   // #0B121F
    static let bgElevated = Color(.sRGB, red: 0.082, green: 0.118, blue: 0.188)   // #152030
    static let surface    = Color(.sRGB, red: 0.106, green: 0.149, blue: 0.231)   // #1B263B
    static let surface2   = Color(.sRGB, red: 0.141, green: 0.196, blue: 0.290)   // #24324A
    static let stroke     = Color.white.opacity(0.08)

    // Brand
    static let accent     = Color(.sRGB, red: 0.18, green: 0.63, blue: 1.0)       // #2EA1FF
    static let accentDeep = Color(.sRGB, red: 0.04, green: 0.32, blue: 0.78)      // #0A51C7
    static let amber      = Color(.sRGB, red: 1.0, green: 0.69, blue: 0.13)       // #FFB020

    // Text
    static let textPrimary   = Color(.sRGB, red: 0.95, green: 0.97, blue: 1.0)
    static let textSecondary = Color(.sRGB, red: 0.62, green: 0.69, blue: 0.80)
    static let textTertiary  = Color(.sRGB, red: 0.40, green: 0.47, blue: 0.58)

    // Flight categories (standard aviation colours)
    static func category(_ cat: String?) -> Color {
        switch cat {
        case "VFR":  return Color(.sRGB, red: 0.19, green: 0.82, blue: 0.35)
        case "MVFR": return accent
        case "IFR":  return Color(.sRGB, red: 1.0, green: 0.27, blue: 0.23)
        case "LIFR": return Color(.sRGB, red: 0.75, green: 0.35, blue: 0.95)
        default:     return textTertiary
        }
    }

    // Layout
    static let corner: CGFloat = 16
    static let cornerSmall: CGFloat = 11
    static let tapTarget: CGFloat = 44
    static let mapControlGap: CGFloat = 8
    static let pad: CGFloat = 16

    // Gradients
    static var background: LinearGradient {
        LinearGradient(colors: [bg, Color(.sRGB, red: 0.027, green: 0.047, blue: 0.09)],
                       startPoint: .top, endPoint: .bottom)
    }
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func headerGradient(_ tint: Color) -> LinearGradient {
        LinearGradient(colors: [tint.opacity(0.55), surface], startPoint: .top, endPoint: .bottom)
    }
}

/// A raised card surface used across the app.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.corner
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.stroke))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

extension View {
    func card(radius: CGFloat = Theme.corner) -> some View { modifier(CardBackground(radius: radius)) }
}
