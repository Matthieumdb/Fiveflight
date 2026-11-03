import SwiftUI
import UIKit

/// ForeFlight-style look: charcoal toolbars and tab bar, ForeFlight blue accent,
/// grouped content lists, small grey uppercase section headers, data "boxes" with label over value.
enum FF {
    static let accent = Color(hex: "2D9CF0")
    static let accentUI = UIColor(red: 0x2D / 255, green: 0x9C / 255, blue: 0xF0 / 255, alpha: 1)
    static let bar = Color(hex: "2A2E33")
    static let barUI = UIColor(red: 0x2A / 255, green: 0x2E / 255, blue: 0x33 / 255, alpha: 1)
    static let barSecondary = Color(hex: "3A3F45")
    static let magenta = Color(hex: "D63AF9")           // active route line / course, as in ForeFlight
    static let label = Color.white.opacity(0.62)

    /// UIKit appearance for every navigation bar, tab bar and segmented control in the app.
    @MainActor
    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = barUI
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 17, weight: .semibold)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
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
        tab.shadowColor = .clear
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(white: 0.62, alpha: 1)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(white: 0.62, alpha: 1)]
            item.selected.iconColor = accentUI
            item.selected.titleTextAttributes = [.foregroundColor: accentUI]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UISegmentedControl.appearance().selectedSegmentTintColor = accentUI
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }
}

/// ForeFlight data box: small grey label over a bold value (map instrument strip, flight summary).
struct FFDataBox: View {
    let label: String
    let value: String
    var valueColor: Color = .white

    var body: some View {
        VStack(spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FF.label)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 17, weight: .bold).monospacedDigit())
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
                if i > 0 { Rectangle().fill(Color.white.opacity(0.12)).frame(width: 0.5, height: 26) }
                FFDataBox(label: item.0, value: item.1)
            }
        }
        .frame(height: 44)
        .background(FF.bar)
    }
}

/// ForeFlight toolbar button: white text/icon on the charcoal bar, blue when active.
struct FFBarButton: View {
    let title: String?
    let icon: String?
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
                if let title { Text(title).font(.system(size: 14, weight: .semibold)) }
            }
            .foregroundStyle(active ? .white : .white.opacity(0.92))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(active ? FF.accent : FF.barSecondary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

/// Small grey uppercase section header used across ForeFlight lists.
struct FFHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
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
