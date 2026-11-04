import SwiftUI
import UIKit
import CoreText

// MARK: - Design Tokens
// Professional token-based design system for aviation apps
// Based on industry best practices: 4/8pt grid, semantic colors, Dynamic Type, material elevation

/// Color Tokens - "Papier carte" palette: chart paper, chart blue, route magenta. Each token has a day and a night value.
enum ColorToken {
    // MARK: Brand
    static let brandPrimary = Color(day: "B0257E", night: "E36BB9")    // route magenta: actions, selection
    static let brandSecondary = Color(day: "173A6B", night: "8DB4EA")  // chart blue: headings, data
    static let brandTertiary = Color(day: "2F6BB3", night: "5B93D6")   // airspace blue

    // MARK: Surfaces (chart paper by day, blue-black by night)
    static let surfaceBase = Color(day: "F6F4EC", night: "11161D")
    static let surfaceElevated = Color(day: "FFFDF6", night: "18202A")
    static let surfaceCard = Color(day: "FFFDF6", night: "1C2531")
    static let surfaceHover = Color(day: "EBE6D6", night: "243040")
    static let surfaceSelected = Color(day: "E3DCC8", night: "2C3A4D")
    static let surfaceModal = Color(day: "F6F4EC", night: "141A22")

    // MARK: Borders & Dividers
    static let borderSubtle = Color(day: "1D2A3A14", night: "FFFFFF12")
    static let borderDefault = Color(day: "1D2A3A24", night: "FFFFFF1C")
    static let borderStrong = Color(day: "1D2A3A38", night: "FFFFFF2B")
    static let borderFocus = brandPrimary.opacity(0.5)

    // MARK: Text
    static let textPrimary = Color(day: "1D2A3A", night: "ECEFF3")
    static let textSecondary = Color(day: "5F6A76", night: "9AA5B2")
    static let textTertiary = Color(day: "8A8676", night: "6E7987")
    static let textQuaternary = Color(day: "B5B0A0", night: "4A5462")
    static let textInverse = Color.white
    static let textOnBrand = Color.white

    // MARK: Status/Semantic (Aviation standard)
    static let success = Color(day: "1D8A4A", night: "39C673")
    static let warning = Color(day: "C77700", night: "FFB020")
    static let danger = Color(day: "C8322B", night: "FF5A4F")
    static let info = Color(day: "2F6BB3", night: "5AC8FA")
    static let critical = Color(day: "9B2FAE", night: "D070E8")

    // MARK: Flight Categories (Standard aviation colors)
    static let vfr = success
    static let mvfr = Color(day: "2F6BB3", night: "5B9BEB")
    static let ifr = danger
    static let lifr = critical
    static let unknown = textTertiary

    // MARK: Airspace Colors (Matching FAA Sectional Charts)
    static let classA = Color(hex: "8B0000")       // Dark red
    static let classB = Color(hex: "0044FF")       // Blue
    static let classC = Color(hex: "0088FF")       // Light blue
    static let classD = Color(hex: "00AAEE")       // Teal
    static let classE = Color(hex: "AA8800")       // Amber
    static let classG = Color(hex: "555555")       // Gray
    static let classESurface = Color(hex: "00AA66") // Green-teal

    static let moa = Color(hex: "FF6B35")          // Orange
    static let restricted = Color(hex: "CC0000")   // Red
    static let prohibited = Color(hex: "8B0000")   // Dark red
    static let warningArea = Color(hex: "FF8800")  // Orange-red
    static let alertArea = Color(hex: "FFAA00")    // Yellow-orange
    static let cfa = Color(hex: "FFCC00")          // Yellow
    static let tfr = Color(hex: "FF0088")          // Magenta
    static let nationalSecurity = Color(hex: "AA00FF") // Purple

    // MARK: Shadows & Elevation
    static let shadowLow = Color.black.opacity(0.12)
    static let shadowMedium = Color.black.opacity(0.20)
    static let shadowHigh = Color.black.opacity(0.32)
    static let shadowOverlay = Color.black.opacity(0.45)

    // MARK: Materials
    static let materialThin = Material.thin
    static let materialRegular = Material.regular
    static let materialThick = Material.thick
    static let materialUltraThin = Material.ultraThin
    static let materialUltraThick = Material.ultraThick
}

/// Spacing Tokens - 4/8pt Grid System
enum SpacingToken {
    static let space0: CGFloat = 0
    static let space1: CGFloat = 4    // 4pt
    static let space2: CGFloat = 8    // 8pt
    static let space3: CGFloat = 12   // 12pt
    static let space4: CGFloat = 16   // 16pt
    static let space5: CGFloat = 20   // 20pt
    static let space6: CGFloat = 24   // 24pt
    static let space8: CGFloat = 32   // 32pt
    static let space10: CGFloat = 40  // 40pt
    static let space12: CGFloat = 48  // 48pt
    static let space16: CGFloat = 64  // 64pt

    // Semantic spacing
    static let insetSmall = space2    // 8pt
    static let insetMedium = space4   // 16pt
    static let insetLarge = space6    // 24pt
    static let insetXLarge = space8   // 32pt

    static let gapTiny = space1       // 4pt
    static let gapSmall = space2      // 8pt
    static let gapMedium = space3     // 12pt
    static let gapLarge = space4      // 16pt
    static let gapXLarge = space6     // 24pt

    // Component specific
    static let listRowPadding = space3      // 12pt
    static let cardPadding = space4         // 16pt
    static let buttonPadding = space3       // 12pt
    static let sectionSpacing = space6      // 24pt
}

/// Radius Tokens - Consistent corner radius scale
enum RadiusToken {
    static let none: CGFloat = 0
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let full: CGFloat = 9999  // Pill/capsule

    // Semantic
    static let button = full      // pill, as on the chart legend
    static let card = md          // 12pt
    static let cardSmall = md     // 12pt
    static let pill = full        // Capsule
    static let modal = xl         // 20pt
    static let overlay = lg       // 16pt
}

/// Typography Tokens - Barlow for text, Barlow Condensed for titles and figures; all scale with Dynamic Type.
enum TypographyToken {
    private static func barlow(_ weight: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom("Barlow-\(weight)", size: size, relativeTo: style)
    }
    private static func condensed(_ weight: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom("BarlowCondensed-\(weight)", size: size, relativeTo: style)
    }

    // Display
    static let displayLarge = condensed("Bold", 36, .largeTitle)
    static let displayMedium = condensed("Bold", 30, .title)
    static let displaySmall = condensed("SemiBold", 24, .title2)

    // Headlines
    static let headlineLarge = condensed("SemiBold", 22, .title3)
    static let headlineMedium = barlow("SemiBold", 17, .headline)
    static let headlineSmall = barlow("SemiBold", 15, .subheadline)

    // Body
    static let bodyLarge = barlow("Medium", 17, .body)
    static let bodyMedium = barlow("Medium", 16, .callout)
    static let bodySmall = barlow("Regular", 15, .subheadline)
    static let bodyXSmall = barlow("Regular", 13, .footnote)

    // Labels
    static let labelLarge = barlow("Medium", 15, .subheadline)
    static let labelMedium = barlow("Medium", 13, .footnote)
    static let labelSmall = barlow("Medium", 12, .caption)
    static let labelXSmall = barlow("Medium", 11, .caption2)

    // Figures (frequencies, distances, times): condensed with tabular digits
    static let monoLarge = condensed("SemiBold", 22, .title3).monospacedDigit()
    static let monoMedium = condensed("SemiBold", 18, .callout).monospacedDigit()
    // Raw METAR/TAF/NOTAM text keeps a true monospace so columns line up
    static let monoSmall = Font.system(.footnote, design: .monospaced).weight(.medium)
    static let monoXSmall = Font.system(.caption, design: .monospaced).weight(.medium)
    static let monoXXSmall = Font.system(.caption2, design: .monospaced).weight(.medium)

    // Numbers
    static let numberLarge = condensed("Bold", 30, .title).monospacedDigit()
    static let numberMedium = condensed("SemiBold", 22, .title3).monospacedDigit()
    static let numberSmall = condensed("SemiBold", 18, .body).monospacedDigit()

    /// Registers the bundled Barlow faces (Resources/Fonts) once at launch.
    static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Shadow Tokens - Elevation system
enum ShadowToken {
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    static let none = Shadow(color: .clear, radius: 0, x: 0, y: 0)
    static let low = Shadow(color: ColorToken.shadowLow, radius: 4, x: 0, y: 1)
    static let medium = Shadow(color: ColorToken.shadowMedium, radius: 8, x: 0, y: 2)
    static let high = Shadow(color: ColorToken.shadowHigh, radius: 16, x: 0, y: 4)
    static let overlay = Shadow(color: ColorToken.shadowOverlay, radius: 24, x: 0, y: 8)

    // Semantic
    static let card = medium
    static let modal = overlay
    static let floating = high
    static let bottomBar = Shadow(color: ColorToken.shadowHigh, radius: 12, x: 0, y: -4)
}

/// Animation Tokens
enum AnimationToken {
    static let instant = Animation.linear(duration: 0.05)
    static let fast = Animation.snappy(duration: 0.15)
    static let normal = Animation.snappy(duration: 0.25)
    static let slow = Animation.smooth(duration: 0.35)
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let springFast = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let springSlow = Animation.spring(response: 0.5, dampingFraction: 0.9)

    // Semantic
    static let tap = fast
    static let hover = fast
    static let transition = normal
    static let sheet = spring
    static let tabSwitch = springFast
    static let map = springSlow
}

/// Layout Tokens
enum LayoutToken {
    // Touch targets (Apple HIG minimum 44x44)
    static let tapTargetMin: CGFloat = 44
    static let tapTargetComfortable: CGFloat = 52
    static let tapTargetLarge: CGFloat = 60

    // Sidebar
    static let sidebarWidthCompact: CGFloat = 280
    static let sidebarWidthRegular: CGFloat = 320
    static let sidebarWidthWide: CGFloat = 380

    // Bottom bar
    static let bottomBarHeightCompact: CGFloat = 72
    static let bottomBarHeightRegular: CGFloat = 88
    static let bottomBarHeightLarge: CGFloat = 100

    // List
    static let listRowHeightCompact: CGFloat = 44
    static let listRowHeightRegular: CGFloat = 56
    static let listRowHeightLarge: CGFloat = 64

    // Map controls
    static let mapControlSize: CGFloat = 44
    static let mapControlGap: CGFloat = 8

    // Screen edges
    static let screenEdgeInset: CGFloat = 16
    static let screenEdgeInsetLarge: CGFloat = 24
}

// MARK: - Color Extension for Hex Support
extension UIColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        let rgba = hex.count == 8 ? v : (v << 8 | 0xFF)   // RRGGBB or RRGGBBAA
        self.init(red: CGFloat(rgba >> 24 & 0xFF) / 255, green: CGFloat(rgba >> 16 & 0xFF) / 255,
                  blue: CGFloat(rgba >> 8 & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
    }
}

extension Color {
    /// A colour that follows the light (day) / dark (night) appearance.
    init(day: String, night: String) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: night) : UIColor(hex: day) })
    }

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

// MARK: - View Extensions for Easy Token Usage
extension View {
    // Radius
    func cornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius))
    }

    // Shadows
    func shadow(_ shadow: ShadowToken.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - Gradients
extension LinearGradient {
    static var surfaceGradient: LinearGradient {
        LinearGradient(
            colors: [ColorToken.surfaceCard, ColorToken.surfaceHover],
            startPoint: .top, endPoint: .bottom
        )
    }

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [ColorToken.brandPrimary, ColorToken.brandSecondary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static var modalGradient: LinearGradient {
        LinearGradient(
            colors: [ColorToken.surfaceModal, ColorToken.surfaceBase],
            startPoint: .top, endPoint: .bottom
        )
    }

    static var bottomBarGradient: LinearGradient {
        LinearGradient(
            colors: [
                ColorToken.surfaceElevated.opacity(0.95),
                ColorToken.surfaceBase.opacity(0.98)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    static func statusGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.6), color.opacity(0.15)],
            startPoint: .top, endPoint: .bottom
        )
    }
}
