import SwiftUI
import CoreLocation

// MARK: - Flight Plan Screen

struct FlightPlanScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var routingEngine: RoutingEngine
    @EnvironmentObject private var airspaceManager: AirspaceDataManager
    @EnvironmentObject private var store: AirportStore
    @State private var showFlightPlanSheet = false
    @State private var showSavedPlans = false

    private var exportPoints: [FlightExport.Point] {
        model.waypoints.map { FlightExport.Point(name: $0.id, coordinate: $0.coordinate) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.waypoints.isEmpty {
                    ContentUnavailableView {
                        Label("No Flight Plan", systemImage: "list.bullet.clipboard")
                    } description: {
                        Text("Add waypoints from the map or search to create a flight plan")
                    } actions: {
                        Button("Search Airports") {
                            showFlightPlanSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FlightPlanContent()
                }
            }
            .background(ColorToken.surfaceBase)
            .navigationTitle("Plan de vol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !model.waypoints.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Enregistrer ce plan", systemImage: "square.and.arrow.down") { model.savePlan() }
                            .disabled(model.waypoints.count < 2)
                        Button("Plans enregistrés", systemImage: "folder") { showSavedPlans = true }
                        if model.waypoints.count >= 2 {
                            let name = model.waypoints.map(\.id).joined(separator: "-")
                            if let gpx = FlightExport.gpx(name: name, route: exportPoints, track: model.track) {
                                ShareLink("Exporter en GPX", item: gpx)
                            }
                            if let kml = FlightExport.kml(name: name, route: exportPoints, track: model.track) {
                                ShareLink("Exporter en KML", item: kml)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFlightPlanSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showSavedPlans) { SavedPlansSheet() }
            .sheet(isPresented: $showFlightPlanSheet) {
                SearchSheet(nearest: store.nearest(to: model.userLocation ?? AppModel.homeCoordinate, limit: 20), onSelect: { airport in
                    model.addWaypoint(airport)
                })
            }
        }
    }
}

private struct FlightPlanContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var routingEngine: RoutingEngine
    @EnvironmentObject private var airspaceManager: AirspaceDataManager

    var body: some View {
        List {
            // Waypoints section
            Section {
                ForEach(Array(model.waypoints.enumerated()), id: \.element.id) { index, airport in
                    FlightPlanWaypointRow(index: index, airport: airport, totalCount: model.waypoints.count)
                }
                .onDelete { model.waypoints.remove(atOffsets: $0) }
                .onMove { model.waypoints.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Waypoints")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                    .textCase(.uppercase)
            }

            // Route summary
            if model.waypoints.count >= 2 {
                Section {
                    NavigationLink { RouteBriefingScreen() } label: {
                        Label("Briefing de route (météo, NOTAM, TFR)", systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink { VFRFlightPlanFilingScreen() } label: {
                        Label("Plan de vol VFR · dépôt Leidos", systemImage: "paperplane")
                    }
                }

                Section {
                    RouteSummaryRow(title: "Distance", value: String(format: "%.0f NM", model.totalDistanceNM), icon: "point.topleft.down.curvedto.point.bottomright.forward")
                    RouteSummaryRow(title: "Time", value: model.formattedTotalTime, icon: "clock")
                    RouteSummaryRow(title: "Fuel", value: String(format: "%.1f gal", model.totalFuelGallons), icon: "fuelpump")
                    RouteSummaryRow(title: "Mode", value: routingEngine.currentMode.rawValue, icon: routingEngine.currentMode.icon)
                } header: {
                    Text("Route Summary")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                }

                Section {
                    VerticalProfileView(path: model.routePath, cruiseAlt: model.cruiseAlt,
                                        airspaces: airspaceManager.allAirspaces)
                } header: {
                    Text("Profil vertical")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                }

                if !model.navlog.isEmpty {
                    Section {
                        ForEach(model.navlog) { NavLogRow(leg: $0) }
                    } header: {
                        Text("Navlog (vents prévus à \(model.cruiseAlt) ft)")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .textCase(.uppercase)
                    }
                }

                // Performance section
                Section {
                    Stepper(value: $model.cruiseAlt, in: 500...17500, step: 500) {
                        HStack {
                            Image(systemName: "altitude")
                                .foregroundStyle(ColorToken.brandPrimary)
                                .frame(width: 24)
                            Text("Cruise Altitude")
                            Spacer()
                            Text("\(model.cruiseAlt) ft")
                                .font(TypographyToken.monoMedium)
                                .foregroundStyle(ColorToken.textPrimary)
                        }
                    }
                    Stepper(value: $model.cruiseGS, in: 40...500, step: 5) {
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundStyle(ColorToken.brandPrimary)
                                .frame(width: 24)
                            Text("Vitesse propre (TAS)")
                            Spacer()
                            Text("\(Int(model.cruiseGS)) kt")
                                .font(TypographyToken.monoMedium)
                                .foregroundStyle(ColorToken.textPrimary)
                        }
                    }
                    Stepper(value: $model.fuelBurn, in: 1...100, step: 1) {
                        HStack {
                            Image(systemName: "fuelpump")
                                .foregroundStyle(ColorToken.brandPrimary)
                                .frame(width: 24)
                            Text("Fuel Burn")
                            Spacer()
                            Text("\(Int(model.fuelBurn)) gal/h")
                                .font(TypographyToken.monoMedium)
                                .foregroundStyle(ColorToken.textPrimary)
                        }
                    }
                    Stepper(value: $model.reserveMin, in: 0...120, step: 5) {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundStyle(ColorToken.brandPrimary)
                                .frame(width: 24)
                            Text("Reserve")
                            Spacer()
                            Text("\(Int(model.reserveMin)) min")
                                .font(TypographyToken.monoMedium)
                                .foregroundStyle(ColorToken.textPrimary)
                        }
                    }
                    Stepper(value: $model.fuelOnBoard, in: 0...300, step: 1) {
                        HStack {
                            Image(systemName: "drop.fill")
                                .foregroundStyle(ColorToken.brandPrimary)
                                .frame(width: 24)
                            Text("Carburant au départ")
                            Spacer()
                            Text(model.fuelOnBoard > 0 ? "\(Int(model.fuelOnBoard)) gal" : "—")
                                .font(TypographyToken.monoMedium)
                                .foregroundStyle(ColorToken.textPrimary)
                        }
                    }
                } header: {
                    Text("Performance")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                }

                // Actions
                Section {
                    Button {
                        model.logFlight(
                            from: model.waypoints.first!.id,
                            to: model.waypoints.last!.id,
                            nm: Int(model.totalDistanceNM.rounded()),
                            eteMinutes: Int(model.totalTimeMinutes.rounded())
                        )
                    } label: {
                        Label("Log Flight", systemImage: "book.fill")
                            .font(TypographyToken.bodyMedium)
                            .foregroundStyle(ColorToken.brandPrimary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Button(role: .destructive) {
                        model.waypoints.removeAll()
                    } label: {
                        Label("Clear Flight Plan", systemImage: "trash")
                            .font(TypographyToken.bodyMedium)
                            .foregroundStyle(ColorToken.danger)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ColorToken.surfaceBase)
    }
}

private struct RouteSummaryRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ColorToken.brandPrimary)
                .frame(width: 28)
            Text(title)
                .font(TypographyToken.bodyMedium)
                .foregroundStyle(ColorToken.textSecondary)
            Spacer()
            Text(value)
                .font(TypographyToken.monoMedium)
                .foregroundStyle(ColorToken.textPrimary)
        }
        .padding(.vertical, SpacingToken.space1)
    }
}

private struct FlightPlanWaypointRow: View {
    let index: Int
    let airport: Airport
    let totalCount: Int

    var body: some View {
        HStack {
            Text("\(index + 1)")
                .font(TypographyToken.monoMedium)
                .foregroundStyle(ColorToken.brandPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(airport.id)
                    .font(TypographyToken.bodyMedium)
                    .foregroundStyle(ColorToken.textPrimary)
                Text(airport.name)
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if index < totalCount - 1 {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ColorToken.textTertiary)
            }
        }
        .padding(.vertical, SpacingToken.space1)
    }
}
/// One navlog line: leg, magnetic heading, wind, ground speed, time and fuel.
private struct NavLogRow: View {
    let leg: NavLogLeg

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space1) {
            HStack {
                Text("\(leg.from) → \(leg.to)")
                    .font(TypographyToken.bodyMedium)
                Spacer()
                Text(String(format: "%.0f NM", leg.distanceNM))
                    .font(TypographyToken.monoMedium)
            }
            HStack(spacing: SpacingToken.space3) {
                Text(String(format: "Cap %03d°M", leg.magneticHeading))
                Text(String(format: "Rte %03d°V", leg.trueCourse))
                if let dir = leg.windDirection, let spd = leg.windSpeed {
                    Text(String(format: "Vent %03d/%d", dir, spd))
                }
            }
            .font(TypographyToken.monoXSmall)
            .foregroundStyle(ColorToken.textSecondary)
            HStack(spacing: SpacingToken.space3) {
                Text(String(format: "GS %.0f kt", leg.groundSpeed))
                Text("\(Int(leg.minutes.rounded())) min")
                Text(String(format: "%.1f gal", leg.fuelGallons))
            }
            .font(TypographyToken.monoXSmall)
            .foregroundStyle(ColorToken.textTertiary)
        }
        .padding(.vertical, SpacingToken.space1)
    }
}

/// Saved plans: tap to load, swipe to delete.
private struct SavedPlansSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.savedPlans.isEmpty {
                    Text("Aucun plan enregistré. Menu ⋯ > « Enregistrer ce plan ».").foregroundStyle(ColorToken.textTertiary)
                }
                ForEach(model.savedPlans) { plan in
                    Button(plan.name) {
                        model.waypoints = plan.points ?? plan.waypointIDs.compactMap { model.resolveWaypoint($0, store: store) }
                        dismiss()
                    }
                }
                .onDelete { model.savedPlans.remove(atOffsets: $0) }
            }
            .navigationTitle("Plans enregistrés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
    }
}
