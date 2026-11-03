import SwiftUI
import UIKit

/// App chrome in the "Papier carte" style: paper toolbars and tab bar, magenta actions,
/// grouped content lists, small uppercase section headers, data "boxes" with label over value.
enum FF {
    static let accent = ColorToken.brandPrimary
    static let accentUI = UIColor(ColorToken.brandPrimary)
    static let bar = ColorToken.surfaceElevated
    static let barUI = UIColor(ColorToken.surfaceElevated)
    static let barSecondary = ColorToken.surfaceHover
    static let magenta = ColorToken.brandPrimary         // active route line / course
    static let label = ColorToken.textSecondary

    /// UIKit appearance for every navigation bar, tab bar and segmented control in the app.
    @MainActor
    static func applyAppearance() {
        TypographyToken.registerFonts()
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = barUI
        nav.shadowColor = UIColor(ColorToken.borderDefault)
        let title = UIColor(ColorToken.brandSecondary)
        nav.titleTextAttributes = [.foregroundColor: title,
                                   .font: UIFont(name: "BarlowCondensed-Bold", size: 19) ?? .systemFont(ofSize: 17, weight: .semibold)]
        nav.largeTitleTextAttributes = [.foregroundColor: title,
                                        .font: UIFont(name: "BarlowCondensed-Bold", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.foregroundColor: accentUI]
        nav.buttonAppearance = button
        nav.doneButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = accentUI

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = barUI
        tab.shadowColor = UIColor(ColorToken.borderDefault)
        let idle = UIColor(ColorToken.textSecondary)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = idle
            item.normal.titleTextAttributes = [.foregroundColor: idle]
            item.selected.iconColor = accentUI
            item.selected.titleTextAttributes = [.foregroundColor: accentUI]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Lists sit on chart paper instead of the system grey.
        UICollectionView.appearance().backgroundColor = UIColor(ColorToken.surfaceBase)
        UITableView.appearance().backgroundColor = UIColor(ColorToken.surfaceBase)

        UISegmentedControl.appearance().selectedSegmentTintColor = accentUI
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }
}

/// ForeFlight data box: small grey label over a bold value (map instrument strip, flight summary).
struct FFDataBox: View {
    let label: String
    let value: String
    var valueColor: Color = ColorToken.brandSecondary

    var body: some View {
        VStack(spacing: 1) {
            Text(label.uppercased())
                .font(.custom("BarlowCondensed-SemiBold", size: 11, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(FF.label)
                .lineLimit(1)
            Text(value)
                .font(.custom("BarlowCondensed-SemiBold", size: 19, relativeTo: .headline).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A row of data boxes on the charcoal bar, separated by thin dividers.
struct FFDataStrip: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                // Fixed height: a bare Rectangle is greedy and used to stretch the strip to fill the screen.
                if i > 0 { Rectangle().fill(ColorToken.borderDefault).frame(width: 0.5, height: 26) }
                FFDataBox(label: item.0, value: item.1)
            }
        }
        .frame(height: 44)
        .background(FF.bar)
    }
}

/// Toolbar button: ink on paper, white on magenta when active.
struct FFBarButton: View {
    let title: String?
    let icon: String?
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
                if let title { Text(title).font(.custom("Barlow-SemiBold", size: 14, relativeTo: .subheadline)) }
            }
            .foregroundStyle(active ? ColorToken.textOnBrand : ColorToken.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(active ? FF.accent : FF.barSecondary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// The one section header used across lists: small condensed caps in chart blue.
struct FFHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.custom("BarlowCondensed-SemiBold", size: 13, relativeTo: .footnote))
            .tracking(0.8)
            .foregroundStyle(ColorToken.brandSecondary)
    }
}

extension Date {
    /// "1435Z", as ForeFlight shows times in navlogs.
    var zulu: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d%02dZ", c.hour ?? 0, c.minute ?? 0)
    }
}

/// "1:05" style durations.
func ffDuration(_ minutes: Double) -> String {
    guard minutes > 0, minutes.isFinite else { return "—" }
    let m = Int(minutes.rounded())
    return String(format: "%d:%02d", m / 60, m % 60)
}
