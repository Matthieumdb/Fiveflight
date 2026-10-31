import SwiftUI

// MARK: - Design Tokens
// Professional token-based design system for aviation apps
// Based on industry best practices: 4/8pt grid, semantic colors, Dynamic Type, material elevation

/// Color Tokens - Semantic colors with full light/dark/high-contrast support
enum ColorToken {
    // MARK: Brand
    static let brandPrimary = Color(hex: "007AFF")      // ForeFlight blue
    static let brandSecondary = Color(hex: "0056CC")
    static let brandTertiary = Color(hex: "003D99")

    // MARK: Surfaces (Aviation dark theme - optimized for cockpit)
    static let surfaceBase = Color(hex: "0A0F1A")       // Deep navy base
    static let surfaceElevated = Color(hex: "121A2A")   // Raised panels
    static let surfaceCard = Color(hex: "1A2434")       // Card backgrounds
    static let surfaceHover = Color(hex: "223044")      // Hover/pressed
    static let surfaceSelected = Color(hex: "2A3A50")   // Selected state
    static let surfaceModal = Color(hex: "0E1624")      // Modal/sheet backgrounds

    // MARK: Borders & Dividers
    static let borderSubtle = Color.white.opacity(0.06)
    static let borderDefault = Color.white.opacity(0.10)
    static let borderStrong = Color.white.opacity(0.16)
    static let borderFocus = brandPrimary.opacity(0.5)

    // MARK: Text (Semantic - auto adapts to light/dark)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(.tertiaryLabel)
    static let textQuaternary = Color(.quaternaryLabel)
    static let textInverse = Color.white
    static let textOnBrand = Color.white

    // MARK: Status/Semantic (Aviation standard)
    static let success = Color(hex: "30D158")      // VFR Green
    static let warning = Color(hex: "FFB020")      // Caution Amber
    static let danger = Color(hex: "FF453A")       // IFR/LIFR Red
    static let info = Color(hex: "5AC8FA")         // Info Cyan
    static let critical = Color(hex: "BF5AF2")     // LIFR Purple

    // MARK: Flight Categories (Standard aviation colors)
    static let vfr = Color(hex: "30D158")          // Green
    static let mvfr = Color(hex: "007AFF")         // Blue
    static let ifr = Color(hex: "FF453A")          // Red
    static let lifr = Color(hex: "BF5AF2")         // Purple
    static let unknown = Color(.tertiaryLabel)

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
    static let button = lg        // 16pt
    static let card = lg          // 16pt
    static let cardSmall = md     // 12pt
    static let pill = full        // Capsule
    static let modal = xxl        // 28pt
    static let overlay = lg       // 16pt
}

/// Typography Tokens - Dynamic Type compatible type ramp
enum TypographyToken {
    // Display
    static let displayLarge = Font.system(.largeTitle, design: .rounded).weight(.bold)      // 34pt
    static let displayMedium = Font.system(.title, design: .rounded).weight(.bold)          // 28pt
    static let displaySmall = Font.system(.title2, design: .rounded).weight(.semibold)      // 22pt

    // Headlines
    static let headlineLarge = Font.system(.title3, design: .rounded).weight(.semibold)     // 20pt
    static let headlineMedium = Font.system(.headline, design: .rounded).weight(.semibold)  // 17pt
    static let headlineSmall = Font.system(.subheadline, design: .rounded).weight(.semibold) // 15pt

    // Body
    static let bodyLarge = Font.system(.body, design: .rounded).weight(.medium)             // 17pt
    static let bodyMedium = Font.system(.callout, design: .rounded).weight(.medium)         // 16pt
    static let bodySmall = Font.system(.subheadline, design: .rounded).weight(.regular)     // 15pt
    static let bodyXSmall = Font.system(.footnote, design: .rounded).weight(.regular)       // 13pt

    // Labels
    static let labelLarge = Font.system(.subheadline, design: .rounded).weight(.medium)     // 15pt
    static let labelMedium = Font.system(.footnote, design: .rounded).weight(.medium)       // 13pt
    static let labelSmall = Font.system(.caption, design: .rounded).weight(.medium)         // 12pt
    static let labelXSmall = Font.system(.caption2, design: .rounded).weight(.medium)       // 11pt

    // Monospace (for aviation data)
    static let monoLarge = Font.system(.title3, design: .monospaced).weight(.medium)        // 20pt
    static let monoMedium = Font.system(.callout, design: .monospaced).weight(.medium)      // 16pt
    static let monoSmall = Font.system(.footnote, design: .monospaced).weight(.medium)      // 13pt
    static let monoXSmall = Font.system(.caption, design: .monospaced).weight(.medium)      // 12pt
    static let monoXXSmall = Font.system(.caption2, design: .monospaced).weight(.medium)    // 11pt

    // Numbers
    static let numberLarge = Font.system(.title, design: .monospaced).weight(.bold)         // 28pt
    static let numberMedium = Font.system(.title3, design: .monospaced).weight(.semibold)   // 20pt
    static let numberSmall = Font.system(.body, design: .monospaced).weight(.medium)        // 17pt
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