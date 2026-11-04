import SwiftUI

/// Older aliases kept for existing views; every value comes from ColorToken ("Papier carte").
enum Theme {
    // Surfaces (deep navy, not pure black)
    static let bg         = ColorToken.surfaceBase
    static let bgElevated = ColorToken.surfaceElevated
    static let surface    = ColorToken.surfaceCard
    static let surface2   = ColorToken.surfaceHover
    static let stroke     = ColorToken.borderSubtle

    // Brand
    static let accent     = ColorToken.brandPrimary
    static let accentDeep = ColorToken.brandSecondary
    static let amber      = ColorToken.warning

    // Text
    static let textPrimary   = ColorToken.textPrimary
    static let textSecondary = ColorToken.textSecondary
    static let textTertiary  = ColorToken.textTertiary

    // Flight categories (standard aviation colours)
    static func category(_ cat: String?) -> Color {
        switch cat {
        case "VFR":  return ColorToken.vfr
        case "MVFR": return ColorToken.mvfr
        case "IFR":  return ColorToken.ifr
        case "LIFR": return ColorToken.lifr
        default:     return textTertiary
        }
    }

    // Layout
    static let corner: CGFloat = 12
    static let cornerSmall: CGFloat = 8
    static let tapTarget: CGFloat = 44
    static let mapControlGap: CGFloat = 8
    static let pad: CGFloat = 16

    // Gradients
    static var background: LinearGradient {
        LinearGradient(colors: [bg, bg],
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
            .shadow(color: ColorToken.shadowLow, radius: 3, y: 1)
    }
}

extension View {
    func card(radius: CGFloat = Theme.corner) -> some View { modifier(CardBackground(radius: radius)) }
}
