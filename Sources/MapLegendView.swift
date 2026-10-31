import SwiftUI

struct MapLegendView: View {
    let categories: [String: String]

    private let categoryOrder = ["VFR", "MVFR", "IFR", "LIFR"]

    var body: some View {
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                ForEach(categoryOrder, id: \.self) { cat in
                    HStack(spacing: Theme.spacingS) {
                        Circle()
                            .fill(Theme.category(cat))
                            .frame(width: 9, height: 9)
                        Text(cat)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(Theme.spacingM)
            .background(Theme.bgMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerSmall).stroke(Theme.stroke))
            .padding(Theme.pad)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}