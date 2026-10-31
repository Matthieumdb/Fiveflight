import SwiftUI

struct LayerControlsView: View {
    @Binding var showSectional: Bool
    @Binding var showWeather: Bool
    let onRecenter: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(spacing: Theme.mapControlGap) {
            LayerToggleButton(
                isOn: $showSectional,
                systemImage: "map.fill",
                label: "Carte VFR"
            )
            LayerToggleButton(
                isOn: $showWeather,
                systemImage: "cloud.rain.fill",
                label: "Météo radar"
            )

            Button(action: onRecenter) {
                Image(systemName: "location.fill")
            }
            .iconButton()
            .accessibilityLabel("Recentrer")

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
            }
            .iconButton()
            .accessibilityLabel("Rechercher")
        }
    }
}

struct LayerToggleButton: View {
    @Binding var isOn: Bool
    let systemImage: String
    let label: String

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isOn.toggle() }
        } label: {
            Image(systemName: systemImage)
        }
        .iconButton(selected: isOn)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}