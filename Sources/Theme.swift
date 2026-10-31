import SwiftUI

// MARK: - Color Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Theme (Glass Cockpit Design System)

/// Premium dark "glass cockpit" design system — one source of truth for the app's look.
enum Theme {
    // MARK: Colors

    // Surfaces (deep navy, not pure black)
    static let bg             = Color(hex: "0B121F")
    static let bgElevated     = Color(hex: "152030")
    static let surface        = Color(hex: "1B263B")
    static let surface2       = Color(hex: "24324A")
    static let stroke         = Color.white.opacity(0.08)
    static let strokeStrong   = Color.white.opacity(0.15)

    // Brand
    static let accent         = Color(hex: "2EA1FF")
    static let accentDeep     = Color(hex: "0A51C7")
    static let amber          = Color(hex: "FFB020")
    static let red            = Color(hex: "FF4444")
    static let green          = Color(hex: "30D158")
    static let orange         = Color(hex: "FF9F0A")
    static let purple         = Color(hex: "BF5AF2")

    // Semantic colors (adapt to light/dark automatically)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    static let textTertiary   = Color(.tertiaryLabel)
    static let textQuaternary = Color(.quaternaryLabel)

    // Background materials
    static let bgMaterial     = Material.regular
    static let bgMaterialThin = Material.thin
    static let bgMaterialUltraThin = Material.ultraThin

    // MARK: Flight Categories (standard aviation colours)
    static func category(_ cat: String?) -> Color {
        switch cat {
        case "VFR":  return Color(hex: "30D158")
        case "MVFR": return accent
        case "IFR":  return Color(hex: "FF453A")
        case "LIFR": return Color(hex: "BF5AF2")
        default:     return textTertiary
        }
    }

    // MARK: Layout
    static let corner: CGFloat         = 16
    static let cornerSmall: CGFloat    = 11
    static let cornerLarge: CGFloat    = 24
    static let tapTarget: CGFloat      = 44
    static let mapControlGap: CGFloat  = 8
    static let pad: CGFloat            = 16
    static let padSmall: CGFloat       = 8
    static let padLarge: CGFloat       = 24
    static let listRowHeight: CGFloat  = 64

    // MARK: Spacing Scale
    static let spacingXS: CGFloat  = 4
    static let spacingS: CGFloat   = 8
    static let spacingM: CGFloat   = 12
    static let spacingL: CGFloat   = 16
    static let spacingXL: CGFloat  = 24
    static let spacingXXL: CGFloat = 32

    // MARK: Gradients
    static var background: LinearGradient {
        LinearGradient(
            colors: [bg, Color(hex: "070C15")],
            startPoint: .top, endPoint: .bottom
        )
    }
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func headerGradient(_ tint: Color) -> LinearGradient {
        LinearGradient(colors: [tint.opacity(0.55), surface], startPoint: .top, endPoint: .bottom)
    }
    static var surfaceGradient: LinearGradient {
        LinearGradient(colors: [surface, surface2], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - View Modifiers

/// A raised card surface used across the app.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.corner
    var material: Material = .regular
    func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.stroke))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

/// Compact card for lists and rows
struct CompactCardBackground: ViewModifier {
    var radius: CGFloat = Theme.cornerSmall
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.stroke))
    }
}

/// Primary action button style
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: Theme.tapTarget)
            .foregroundStyle(fill ? .white : Theme.accent)
            .background(
                fill ? Theme.accentGradient : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: Theme.corner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner)
                    .stroke(fill ? Color.clear : Theme.accent, lineWidth: fill ? 0 : 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.1), value: configuration.isPressed)
    }
}

/// Secondary button style
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .frame(height: Theme.tapTarget)
            .foregroundStyle(Theme.textPrimary)
            .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.strokeStrong))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.1), value: configuration.isPressed)
    }
}

/// Icon button style for map controls
struct IconButtonStyle: ButtonStyle {
    var selected: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .frame(width: Theme.tapTarget, height: Theme.tapTarget)
            .foregroundStyle(selected ? .white : Theme.textSecondary)
            .background(
                selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.bgMaterial),
                in: RoundedRectangle(cornerRadius: Theme.corner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner)
                    .stroke(selected ? Color.clear : Theme.strokeStrong)
            )
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    func card(radius: CGFloat = Theme.corner, material: Material = .regular) -> some View {
        modifier(CardBackground(radius: radius, material: material))
    }

    func compactCard(radius: CGFloat = Theme.cornerSmall) -> some View {
        modifier(CompactCardBackground(radius: radius))
    }

    func primaryButton(fill: Bool = true) -> some View {
        buttonStyle(PrimaryButtonStyle(fill: fill))
    }

    func secondaryButton() -> some View {
        buttonStyle(SecondaryButtonStyle())
    }

    func iconButton(selected: Bool = false) -> some View {
        buttonStyle(IconButtonStyle(selected: selected))
    }
}

// MARK: - Standard Alert Helper

extension View {
    func alert(_ title: String, item: Binding<(any Error)?>, actions: (any Error) -> () -> Void) -> some View {
        alert(title, isPresented: .constant(item.wrappedValue != nil), presenting: item.wrappedValue) { error in
            Button("OK") { item.wrappedValue = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
    }
}

// MARK: - Animation Helpers

extension Animation {
    static let snappyUI = Animation.snappy(duration: 0.25)
    static let smoothUI = Animation.smooth(duration: 0.35)
    static let springUI = Animation.spring(response: 0.4, dampingFraction: 0.85)
}

// MARK: - Accessibility Helpers

extension View {
    func tappableArea(_ size: CGFloat = Theme.tapTarget) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}