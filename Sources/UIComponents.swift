import SwiftUI

// MARK: - Professional UI Components
// Token-based, accessible, aviation-ready components

// MARK: - Button Styles

/// Primary action button - brand gradient fill
struct PrimaryButtonStyle: ButtonStyle {
    var size: ButtonSize = .regular
    var isLoading: Bool = false

    enum ButtonSize {
        case small, regular, large

        var height: CGFloat {
            switch self {
            case .small: return 36
            case .regular: return 44
            case .large: return 52
            }
        }

        var font: Font {
            switch self {
            case .small: return TypographyToken.labelMedium
            case .regular: return TypographyToken.labelLarge
            case .large: return TypographyToken.headlineSmall
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return SpacingToken.space4
            case .regular: return SpacingToken.space6
            case .large: return SpacingToken.space8
            }
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(ColorToken.textOnBrand)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(
                LinearGradient.brandGradient,
                in: RoundedRectangle(cornerRadius: RadiusToken.button)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusToken.button)
                    .stroke(ColorToken.borderFocus.opacity(configuration.isPressed ? 0.5 : 0), lineWidth: 2)
            )
            .shadow(
                configuration.isPressed ? ShadowToken.low : ShadowToken.medium
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isLoading ? 0.7 : 1.0)
            .animation(AnimationToken.tap, value: configuration.isPressed)
            .animation(AnimationToken.fast, value: isLoading)
    }
}

/// Secondary button - outline style
struct SecondaryButtonStyle: ButtonStyle {
    var size: PrimaryButtonStyle.ButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(ColorToken.textPrimary)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.button))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusToken.button)
                    .stroke(configuration.isPressed ? ColorToken.brandPrimary : ColorToken.borderDefault, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(AnimationToken.tap, value: configuration.isPressed)
    }
}

/// Tertiary button - ghost/text style
struct TertiaryButtonStyle: ButtonStyle {
    var size: PrimaryButtonStyle.ButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(configuration.isPressed ? ColorToken.brandSecondary : ColorToken.brandPrimary)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(
                configuration.isPressed ? ColorToken.brandPrimary.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: RadiusToken.button)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(AnimationToken.tap, value: configuration.isPressed)
    }
}

/// Destructive button - red outline/fill
struct DestructiveButtonStyle: ButtonStyle {
    var filled: Bool = false
    var size: PrimaryButtonStyle.ButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(filled ? ColorToken.textOnBrand : ColorToken.danger)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(
                filled ? ColorToken.danger : ColorToken.danger.opacity(configuration.isPressed ? 0.1 : 0),
                in: RoundedRectangle(cornerRadius: RadiusToken.button)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusToken.button)
                    .stroke(filled ? Color.clear : ColorToken.danger, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(AnimationToken.tap, value: configuration.isPressed)
    }
}

/// Icon button - square/circular
struct IconButtonStyle: ButtonStyle {
    var size: IconSize = .regular
    var selected: Bool = false
    var variant: IconVariant = .material

    enum IconSize {
        case small, regular, large

        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .regular: return 44
            case .large: return 52
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 16
            case .regular: return 20
            case .large: return 24
            }
        }
    }

    enum IconVariant {
        case material      // Material background
        case glass         // Ultra thin material
        case solid         // Solid surface
        case plain         // No background
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.iconSize, weight: .medium))
            .foregroundStyle(foregroundColor)
            .frame(width: size.dimension, height: size.dimension)
            .background(backgroundView)
            .overlay(overlayView)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(AnimationToken.tap, value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        if selected { return ColorToken.textOnBrand }
        switch variant {
        case .plain: return ColorToken.textSecondary
        default: return ColorToken.textPrimary
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch variant {
        case .material:
            RoundedRectangle(cornerRadius: RadiusToken.md)
                .fill(selected ? AnyShapeStyle(LinearGradient.brandGradient) : AnyShapeStyle(ColorToken.materialRegular))
        case .glass:
            Circle().fill(ColorToken.materialUltraThin)
        case .solid:
            RoundedRectangle(cornerRadius: RadiusToken.md)
                .fill(selected ? ColorToken.brandPrimary : ColorToken.surfaceCard)
        case .plain:
            Color.clear
        }
    }

    @ViewBuilder
    private var overlayView: some View {
        if variant != .plain && !selected {
            RoundedRectangle(cornerRadius: variant == .glass ? RadiusToken.full : RadiusToken.md)
                .stroke(ColorToken.borderDefault, lineWidth: 0.5)
        }
    }
}

/// Pill button - for segmented controls, bottom bar
struct PillButtonStyle: ButtonStyle {
    var selected: Bool = false
    var size: PillSize = .regular

    enum PillSize {
        case small, regular, large

        var height: CGFloat {
            switch self {
            case .small: return 28
            case .regular: return 36
            case .large: return 44
            }
        }

        var font: Font {
            switch self {
            case .small: return TypographyToken.labelSmall
            case .regular: return TypographyToken.labelMedium
            case .large: return TypographyToken.labelLarge
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return SpacingToken.space3
            case .regular: return SpacingToken.space4
            case .large: return SpacingToken.space5
            }
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(selected ? ColorToken.textOnBrand : ColorToken.textSecondary)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(
                selected ? AnyShapeStyle(LinearGradient.brandGradient) : AnyShapeStyle(Color.clear),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Color.clear : ColorToken.borderDefault, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(AnimationToken.tabSwitch, value: selected)
            .animation(AnimationToken.tap, value: configuration.isPressed)
    }
}

/// Map overlay button - circular, for map controls
struct MapControlButtonStyle: ButtonStyle {
    var selected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(selected ? ColorToken.textOnBrand : ColorToken.textPrimary)
            .frame(width: LayoutToken.mapControlSize, height: LayoutToken.mapControlSize)
            .background(
                selected ? AnyShapeStyle(LinearGradient.brandGradient) : AnyShapeStyle(ColorToken.materialRegular),
                in: Circle()
            )
            .overlay(
                Circle()
                    .stroke(selected ? Color.clear : ColorToken.borderDefault, lineWidth: 0.5)
            )
            .shadow(selected ? ShadowToken.medium : ShadowToken.low)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(AnimationToken.tap, value: configuration.isPressed)
            .animation(AnimationToken.fast, value: selected)
    }
}

// MARK: - Card Styles

/// Standard elevated card
struct CardStyle: ViewModifier {
    var padding: CGFloat = SpacingToken.cardPadding
    var shadow: ShadowToken.Shadow = ShadowToken.card
    var background: Color = ColorToken.surfaceCard

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background, in: RoundedRectangle(cornerRadius: RadiusToken.card))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusToken.card)
                    .stroke(ColorToken.borderDefault, lineWidth: 0.5)
            )
            .shadow(shadow)
    }
}

/// Compact card for lists
struct CompactCardStyle: ViewModifier {
    var padding: CGFloat = SpacingToken.space3

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.cardSmall))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusToken.cardSmall)
                    .stroke(ColorToken.borderSubtle, lineWidth: 0.5)
            )
    }
}

/// Selected/active card
struct SelectedCardStyle: ViewModifier {
    var padding: CGFloat = SpacingToken.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(ColorToken.surfaceSelected, in: RoundedRectangle(cornerRadius: RadiusToken.card))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusToken.card)
                    .stroke(ColorToken.brandPrimary.opacity(0.5), lineWidth: 1.5)
            )
            .shadow(ShadowToken.medium)
    }
}

/// Glass/frosted card
struct GlassCardStyle: ViewModifier {
    var padding: CGFloat = SpacingToken.cardPadding
    var material: Material = ColorToken.materialRegular

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(material, in: RoundedRectangle(cornerRadius: RadiusToken.card))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusToken.card)
                    .stroke(ColorToken.borderDefault, lineWidth: 0.5)
            )
    }
}

/// Modal/sheet card
struct ModalCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(SpacingToken.insetLarge)
            .background(ColorToken.surfaceModal, in: RoundedRectangle(cornerRadius: RadiusToken.modal))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusToken.modal)
                    .stroke(ColorToken.borderDefault, lineWidth: 0.5)
            )
            .shadow(ShadowToken.modal)
    }
}

// MARK: - List Row Styles

/// Standard list row
struct ListRowStyle: ViewModifier {
    var height: CGFloat = LayoutToken.listRowHeightRegular

    func body(content: Content) -> some View {
        content
            .frame(minHeight: height)
            .padding(.horizontal, SpacingToken.insetMedium)
            .padding(.vertical, SpacingToken.space2)
            .background(ColorToken.surfaceCard)
            .contentShape(Rectangle())
    }
}

/// Section header style
struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(TypographyToken.labelSmall)
            .foregroundStyle(ColorToken.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, SpacingToken.insetMedium)
            .padding(.top, SpacingToken.space4)
            .padding(.bottom, SpacingToken.space1)
    }
}

// MARK: - Badge/Tag Styles

struct StatusBadgeStyle: ViewModifier {
    var color: Color
    var size: BadgeSize = .regular

    enum BadgeSize {
        case small, regular, large

        var font: Font {
            switch self {
            case .small: return TypographyToken.labelXSmall
            case .regular: return TypographyToken.labelSmall
            case .large: return TypographyToken.labelMedium
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return SpacingToken.space2
            case .regular: return SpacingToken.space3
            case .large: return SpacingToken.space4
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small: return SpacingToken.space0
            case .regular: return SpacingToken.space1
            case .large: return SpacingToken.space2
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .font(size.font)
            .foregroundStyle(ColorToken.textOnBrand)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(color, in: Capsule())
    }
}

struct CategoryDotStyle: ViewModifier {
    var color: Color
    var size: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }
}

// MARK: - Text Field Styles

struct AviationTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(TypographyToken.bodyMedium)
            .foregroundStyle(ColorToken.textPrimary)
            .padding(.horizontal, SpacingToken.space4)
            .padding(.vertical, SpacingToken.space3)
            .background(ColorToken.surfaceElevated, in: RoundedRectangle(cornerRadius: RadiusToken.md))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusToken.md)
                    .stroke(ColorToken.borderDefault, lineWidth: 1)
            )
    }
}

struct SearchFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: SpacingToken.space2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ColorToken.textTertiary)
            configuration
                .font(TypographyToken.bodyMedium)
                .foregroundStyle(ColorToken.textPrimary)
        }
        .padding(.horizontal, SpacingToken.space4)
        .padding(.vertical, SpacingToken.space3)
        .background(ColorToken.surfaceElevated, in: RoundedRectangle(cornerRadius: RadiusToken.pill))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusToken.pill)
                .stroke(ColorToken.borderDefault, lineWidth: 1)
        )
    }
}

// MARK: - Toggle Styles

struct AviationToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .font(TypographyToken.bodyMedium)
                .foregroundStyle(ColorToken.textPrimary)
            Spacer()
            RoundedRectangle(cornerRadius: RadiusToken.full)
                .fill(configuration.isOn ? ColorToken.brandPrimary : ColorToken.borderDefault)
                .frame(width: 52, height: 30)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 26, height: 26)
                        .shadow(ShadowToken.low)
                        .offset(x: configuration.isOn ? 11 : -11)
                        .animation(AnimationToken.springFast, value: configuration.isOn)
                )
                .onTapGesture {
                    withAnimation(AnimationToken.springFast) {
                        configuration.isOn.toggle()
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(AnimationToken.springFast) {
                configuration.isOn.toggle()
            }
        }
    }
}

// MARK: - Progress/Loading Styles

struct AviationProgressViewStyle: ProgressViewStyle {
    var color: Color = ColorToken.brandPrimary
    var lineWidth: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: configuration.fractionCompleted ?? 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(AnimationToken.normal, value: configuration.fractionCompleted)
        }
    }
}

// MARK: - Divider Style

struct AviationDivider: View {
    var color: Color = ColorToken.borderSubtle
    var thickness: CGFloat = 0.5

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: thickness)
    }
}

// MARK: - View Extensions for Easy Usage

extension View {
    // Buttons
    func primaryButton(size: PrimaryButtonStyle.ButtonSize = .regular, isLoading: Bool = false) -> some View {
        buttonStyle(PrimaryButtonStyle(size: size, isLoading: isLoading))
    }

    func secondaryButton(size: PrimaryButtonStyle.ButtonSize = .regular) -> some View {
        buttonStyle(SecondaryButtonStyle(size: size))
    }

    func tertiaryButton(size: PrimaryButtonStyle.ButtonSize = .regular) -> some View {
        buttonStyle(TertiaryButtonStyle(size: size))
    }

    func destructiveButton(filled: Bool = false, size: PrimaryButtonStyle.ButtonSize = .regular) -> some View {
        buttonStyle(DestructiveButtonStyle(filled: filled, size: size))
    }

    func iconButton(
        size: IconButtonStyle.IconSize = .regular,
        selected: Bool = false,
        variant: IconButtonStyle.IconVariant = .material
    ) -> some View {
        buttonStyle(IconButtonStyle(size: size, selected: selected, variant: variant))
    }

    func pillButton(selected: Bool = false, size: PillButtonStyle.PillSize = .regular) -> some View {
        buttonStyle(PillButtonStyle(selected: selected, size: size))
    }

    func mapControlButton(selected: Bool = false) -> some View {
        buttonStyle(MapControlButtonStyle(selected: selected))
    }

    // Cards
    func card(
        padding: CGFloat = SpacingToken.cardPadding,
        shadow: ShadowToken.Shadow = ShadowToken.card,
        background: Color = ColorToken.surfaceCard
    ) -> some View {
        modifier(CardStyle(padding: padding, shadow: shadow, background: background))
    }

    func compactCard(padding: CGFloat = SpacingToken.space3) -> some View {
        modifier(CompactCardStyle(padding: padding))
    }

    func selectedCard(padding: CGFloat = SpacingToken.cardPadding) -> some View {
        modifier(SelectedCardStyle(padding: padding))
    }

    func glassCard(padding: CGFloat = SpacingToken.cardPadding, material: Material = ColorToken.materialRegular) -> some View {
        modifier(GlassCardStyle(padding: padding, material: material))
    }

    func modalCard() -> some View {
        modifier(ModalCardStyle())
    }

    // List
    func listRow(height: CGFloat = LayoutToken.listRowHeightRegular) -> some View {
        modifier(ListRowStyle(height: height))
    }

    func sectionHeader() -> some View {
        modifier(SectionHeaderStyle())
    }

    // Badges
    func statusBadge(_ color: Color, size: StatusBadgeStyle.BadgeSize = .regular) -> some View {
        modifier(StatusBadgeStyle(color: color, size: size))
    }

    func categoryDot(_ color: Color, size: CGFloat = 8) -> some View {
        modifier(CategoryDotStyle(color: color, size: size))
    }

    // Text Fields
    func aviationTextField() -> some View {
        textFieldStyle(AviationTextFieldStyle())
    }

    func searchField() -> some View {
        textFieldStyle(SearchFieldStyle())
    }

    // Toggles
    func aviationToggle() -> some View {
        toggleStyle(AviationToggleStyle())
    }

    // Progress
    func aviationProgress(color: Color = ColorToken.brandPrimary, lineWidth: CGFloat = 3) -> some View {
        progressViewStyle(AviationProgressViewStyle(color: color, lineWidth: lineWidth))
    }
}

// MARK: - Previews

#Preview("Buttons") {
    VStack(spacing: SpacingToken.space4) {
        Button("Primary") {}.primaryButton()
        Button("Primary Large") {}.primaryButton(size: .large)
        Button("Primary Small") {}.primaryButton(size: .small)

        Divider()

        Button("Secondary") {}.secondaryButton()
        Button("Tertiary") {}.tertiaryButton()
        Button("Destructive") {}.destructiveButton()
        Button("Destructive Filled") {}.destructiveButton(filled: true)

        Divider()

        HStack(spacing: SpacingToken.space3) {
            Button(action: {}) { Image(systemName: "plus") }.iconButton()
            Button(action: {}) { Image(systemName: "minus") }.iconButton(selected: true)
            Button(action: {}) { Image(systemName: "gear") }.iconButton(variant: .glass)
            Button(action: {}) { Image(systemName: "map") }.iconButton(variant: .solid)
        }

        Divider()

        HStack(spacing: SpacingToken.space2) {
            Button("Map") {}.pillButton()
            Button("Flights") {}.pillButton(selected: true)
            Button("Weather") {}.pillButton()
        }

        Divider()

        HStack(spacing: SpacingToken.space3) {
            Button(action: {}) { Image(systemName: "location.fill") }.mapControlButton()
            Button(action: {}) { Image(systemName: "layers") }.mapControlButton(selected: true)
            Button(action: {}) { Image(systemName: "plus") }.mapControlButton()
        }
    }
    .padding()
    .background(ColorToken.surfaceBase)
}

#Preview("Cards") {
    VStack(spacing: SpacingToken.space4) {
        Text("Standard Card").card()
        Text("Compact Card").compactCard()
        Text("Selected Card").selectedCard()
        Text("Glass Card").glassCard()
    }
    .padding()
    .background(ColorToken.surfaceBase)
}

#Preview("Badges") {
    HStack(spacing: SpacingToken.space3) {
        Text("VFR").statusBadge(ColorToken.vfr)
        Text("MVFR").statusBadge(ColorToken.mvfr)
        Text("IFR").statusBadge(ColorToken.ifr)
        Text("LIFR").statusBadge(ColorToken.lifr)
    }
    .padding()
    .background(ColorToken.surfaceBase)
}