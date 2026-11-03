import SwiftUI

// MARK: - Imagery (ForeFlight "Imagery")
//
// A catalogue of weather products grouped by category; each opens full screen with pinch-to-zoom.
// Text products (winds, PIREPs, AIRMET/SIGMET, FIS-B) keep their own screens.
// Images are public NOAA / NWS products.

struct ImageryProduct: Identifiable, Hashable {
    let title: String
    let subtitle: String
    let url: URL
    var id: URL { url }

    init(_ title: String, _ subtitle: String, _ url: String) {
        self.title = title
        self.subtitle = subtitle
        self.url = URL(string: url)!
    }
}

enum ImageryCatalog {
    static let radar: [ImageryProduct] = [
        .init("Radar — Melbourne (KMLB)", "Côte est de Floride", "https://radar.weather.gov/ridge/standard/KMLB_0.gif"),
        .init("Radar — Miami (KAMX)", "Sud de la Floride", "https://radar.weather.gov/ridge/standard/KAMX_0.gif"),
        .init("Radar — Tampa (KTBW)", "Côte ouest", "https://radar.weather.gov/ridge/standard/KTBW_0.gif"),
        .init("Radar — Sud-Est", "Mosaïque régionale", "https://radar.weather.gov/ridge/standard/SOUTHEAST_0.gif"),
        .init("Radar — États-Unis", "Mosaïque nationale", "https://radar.weather.gov/ridge/standard/CONUS_0.gif")
    ]
    static let satellite: [ImageryProduct] = [
        .init("Visible / GeoColor — Sud-Est", "GOES-Est", "https://cdn.star.nesdis.noaa.gov/GOES19/ABI/SECTOR/se/GEOCOLOR/1200x1200.jpg"),
        .init("Infrarouge — Sud-Est", "GOES-Est, canal 13", "https://cdn.star.nesdis.noaa.gov/GOES19/ABI/SECTOR/se/13/1200x1200.jpg"),
        .init("Vapeur d'eau — Sud-Est", "GOES-Est, canal 9", "https://cdn.star.nesdis.noaa.gov/GOES19/ABI/SECTOR/se/09/1200x1200.jpg"),
        .init("GeoColor — États-Unis", "GOES-Est", "https://cdn.star.nesdis.noaa.gov/GOES19/ABI/CONUS/GEOCOLOR/1250x750.jpg")
    ]
    static let prog: [ImageryProduct] = [
        .init("Analyse de surface", "Actuelle", "https://aviationweather.gov/data/products/progs/F000_wpc_sfc.gif"),
        .init("Prévision +6 h", "Fronts et précipitations", "https://aviationweather.gov/data/products/progs/F006_wpc_prog.gif"),
        .init("Prévision +12 h", "Fronts et précipitations", "https://aviationweather.gov/data/products/progs/F012_wpc_prog.gif"),
        .init("Prévision +18 h", "Fronts et précipitations", "https://aviationweather.gov/data/products/progs/F018_wpc_prog.gif"),
        .init("Prévision +24 h", "Fronts et précipitations", "https://aviationweather.gov/data/products/progs/F024_wpc_prog.gif"),
        .init("Prévision +48 h", "Fronts et précipitations", "https://aviationweather.gov/data/products/progs/F048_wpc_prog.gif")
    ]
    static let convective: [ImageryProduct] = [
        .init("Risque orageux — Jour 1", "SPC", "https://www.spc.noaa.gov/products/outlook/day1otlk.gif"),
        .init("Risque orageux — Jour 2", "SPC", "https://www.spc.noaa.gov/products/outlook/day2otlk.gif"),
        .init("Risque orageux — Jour 3", "SPC", "https://www.spc.noaa.gov/products/outlook/day3otlk.gif")
    ]
}

struct ImageryScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var weatherService: WeatherService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    textLink("Météo de la route", "point.topleft.down.to.point.bottomright.curvepath", WeatherOverviewTab())
                    textLink("Vents et températures en altitude", "wind", WindsAloftTab())
                    textLink("PIREPs", "person.wave.2", PIREPsTab())
                    textLink("AIRMET / SIGMET", "exclamationmark.triangle", AIRMETsTab())
                    textLink("Briefing de route", "doc.text.magnifyingglass", RouteBriefingScreen())
                    textLink("FIS-B (ADS-B, sans internet)", "dot.radiowaves.up.forward", FISBWeatherScreen())
                } header: { FFHeader("Textes et briefing") }
                category("Radar", ImageryCatalog.radar)
                category("Satellite", ImageryCatalog.satellite)
                category("Cartes de prévision", ImageryCatalog.prog)
                category("Convection", ImageryCatalog.convective)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Imagerie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(weatherService.isLoading)
                }
            }
            .task {
                if weatherService.windsAloft.isEmpty && weatherService.airsigmets.isEmpty { await refresh() }
            }
        }
    }

    private func textLink<D: View>(_ title: String, _ icon: String, _ destination: D) -> some View {
        NavigationLink {
            destination
                .background(ColorToken.surfaceBase)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            FFIconLabel(title: title, icon: icon)
        }
    }

    private func category(_ title: String, _ products: [ImageryProduct]) -> some View {
        Section {
            ForEach(products) { product in
                NavigationLink { ImageryViewer(product: product) } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: product.url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 64, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(product.title)
                            Text(product.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: { FFHeader(title) }
    }

    private func refresh() async {
        for airport in model.waypoints where airport.id != AppModel.gpsWaypointID {
            async let metar = weatherService.fetchMETAR(for: airport.id)
            async let taf = weatherService.fetchTAF(for: airport.id)
            _ = await (metar, taf)
        }
        async let winds: Void = weatherService.fetchWindsAloft()
        async let pireps: Void = weatherService.fetchPIREPs()
        async let airmets: Void = weatherService.fetchAIRMETs()
        _ = await (winds, pireps, airmets)
    }
}

/// Full-screen weather image on black, pinch to zoom, double tap to reset.
struct ImageryViewer: View {
    let product: ImageryProduct
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var reload = UUID()

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                AsyncImage(url: product.url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .frame(width: geo.size.width * scale)
                    case .failure:
                        ContentUnavailableView("Image indisponible", systemImage: "wifi.slash",
                                               description: Text("Vérifiez la connexion internet."))
                            .frame(width: geo.size.width, height: geo.size.height)
                    default:
                        ProgressView().frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .id(reload)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = min(max(lastScale * $0.magnification, 1), 6) }
                    .onEnded { _ in lastScale = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation { scale = 1; lastScale = 1 }
            }
        }
        .background(Color.black)
        .navigationTitle(product.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { reload = UUID() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }
}
