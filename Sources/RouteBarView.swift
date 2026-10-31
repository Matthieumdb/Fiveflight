import SwiftUI

struct RouteBarView: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    @Binding var waypoints: [Airport]
    @Binding var fromText: String
    @Binding var toText: String
    @Binding var routeError: String?
    @Binding var logged: Bool
    let onMakeRoute: () -> Void
    let onClearRoute: () -> Void

    private var totalNM: Double {
        guard waypoints.count >= 2 else { return 0 }
        return zip(waypoints, waypoints.dropFirst())
            .reduce(0) { $0 + Haversine.nauticalMiles($1.0.coordinate, $1.1.coordinate) }
    }

    var body: some View {
        VStack(spacing: Theme.spacingS) {
            // Input row
            HStack(spacing: Theme.spacingS) {
                RouteField(title: "DE", text: $fromText, onSubmit: onMakeRoute)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                RouteField(title: "À", text: $toText, onSubmit: onMakeRoute)

                Button("Tracer", action: onMakeRoute)
                    .primaryButton()
                    .frame(width: 80)

                if !waypoints.isEmpty {
                    Button(action: onClearRoute) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.textTertiary)
                }
            }

            // Route info or error
            if waypoints.count >= 2 {
                RouteInfoRow(waypoints: waypoints, totalNM: totalNM)
                FlightComputerRow(
                    totalNM: totalNM,
                    cruiseGS: $model.cruiseGS,
                    fuelBurn: $model.fuelBurn,
                    logged: $logged,
                    onLog: { nm, minutes in
                        model.logFlight(from: waypoints.first!.id, to: waypoints.last!.id, nm: nm, eteMinutes: minutes)
                    }
                )
            } else if let routeError {
                Text(routeError)
                    .font(.caption)
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, Theme.spacingM)
        .background(Theme.bgElevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 0.5)
        }
    }
}

struct RouteField: View {
    let title: String
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
            TextField(title, text: $text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .frame(width: 78)
                .onSubmit(onSubmit)
        }
    }
}

struct RouteInfoRow: View {
    let waypoints: [Airport]
    let totalNM: Double

    var body: some View {
        HStack {
            Text("\(waypoints.map(\.id).joined(separator: " → "))  ·  \(Int(totalNM.rounded())) NM")
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .contentShape(Rectangle())
    }
}

struct FlightComputerRow: View {
    let totalNM: Double
    @Binding var cruiseGS: Double
    @Binding var fuelBurn: Double
    @Binding var logged: Bool
    let onLog: (Int, Int) -> Void

    private var hours: Double {
        cruiseGS > 0 ? totalNM / cruiseGS : 0
    }
    private var mins: Int {
        Int((hours * 60).rounded())
    }
    private var ete: String {
        "\(mins / 60)h\(String(format: "%02d", mins % 60))"
    }
    private var fuel: Double {
        hours * fuelBurn
    }

    var body: some View {
        VStack(spacing: Theme.spacingS) {
            HStack {
                LabeledContent("GS", value: "\(Int(cruiseGS)) kt")
                Stepper("", value: $cruiseGS, in: 40...500, step: 5)
                    .labelsHidden()
                    .frame(width: 80)
                Spacer()
                LabeledContent("Conso", value: "\(Int(fuelBurn)) gph")
                Stepper("", value: $fuelBurn, in: 1...100, step: 1)
                    .labelsHidden()
                    .frame(width: 60)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)

            HStack {
                Text("ETE \(ete)  ·  \(String(format: "%.1f", fuel)) gal")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(logged ? "Enregistré" : "Carnet") {
                    onLog(Int(totalNM.rounded()), mins)
                }
                .primaryButton(fill: !logged)
                .disabled(logged)
                .frame(width: 120)
            }
        }
    }
}