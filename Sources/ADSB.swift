import Foundation
import Network
import CoreLocation
import MapKit

/// One ADS-B target from a GDL 90 Traffic Report.
struct TrafficTarget: Identifiable, Equatable {
    let id: UInt32            // ICAO address
    var callsign: String
    var coordinate: CLLocationCoordinate2D
    var altitudeFt: Int
    var trackDeg: Int
    var speedKt: Int
    var verticalFpm: Int
    var updated: Date

    static func == (a: TrafficTarget, b: TrafficTarget) -> Bool {
        a.id == b.id && a.updated == b.updated
    }
}

/// Attitude from the receiver's AHRS (Stratux 0x4C or ForeFlight 0x65 message), degrees.
struct AHRSAttitude: Equatable {
    var roll: Double
    var pitch: Double
    var heading: Double?
    var slipSkid: Double?
    var gLoad: Double?
    var updated: Date
}

/// GDL 90 decoder (Stratux, Sentry, SkyEcho, GDL 39…): framing, CRC, and the messages we use.
enum GDL90 {
    enum Message {
        case heartbeat(gpsValid: Bool)
        case ownship(TrafficTarget)
        case traffic(TrafficTarget)
        case ahrs(AHRSAttitude)
        /// FIS-B uplink: the 432-byte UAT payload after the 3-byte time of reception.
        case uplink([UInt8])
    }

    /// Splits a datagram into messages: 0x7E-delimited frames, 0x7D escapes, CRC-16 checked.
    static func decode(_ datagram: Data) -> [Message] {
        var out: [Message] = []
        var frame: [UInt8] = []
        var inFrame = false, escape = false
        for byte in datagram {
            if byte == 0x7E {
                if inFrame, frame.count >= 3, let m = message(frame) { out.append(m) }
                frame = []; inFrame = true; escape = false
                continue
            }
            guard inFrame else { continue }
            if byte == 0x7D { escape = true; continue }
            frame.append(escape ? byte ^ 0x20 : byte)
            escape = false
        }
        return out
    }

    private static let crcTable: [UInt16] = (0..<256).map { i in
        var crc = UInt16(i) << 8
        for _ in 0..<8 { crc = (crc << 1) ^ ((crc & 0x8000) != 0 ? 0x1021 : 0) }
        return crc
    }

    static func crc(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        bytes.reduce(UInt16(0)) { crc, b in crcTable[Int(crc >> 8)] ^ (crc << 8) ^ UInt16(b) }
    }

    private static func message(_ frame: [UInt8]) -> Message? {
        let body = frame.dropLast(2)
        let received = UInt16(frame[frame.count - 2]) | UInt16(frame[frame.count - 1]) << 8
        guard crc(body) == received, let id = body.first else { return nil }
        let p = Array(body)
        switch id {
        case 0x00 where p.count >= 3: return .heartbeat(gpsValid: p[1] & 0x80 != 0)
        case 0x0A where p.count >= 28: return report(p).map { .ownship($0) }
        case 0x14 where p.count >= 28: return report(p).map { .traffic($0) }
        case 0x07 where p.count >= 436: return .uplink(Array(p[4..<436]))
        case 0x4C where p.count >= 16 && p[1] == 0x45 && p[2] == 0x01: return stratuxAHRS(p).map { .ahrs($0) }
        case 0x65 where p.count >= 8 && p[1] == 0x01: return foreFlightAHRS(p).map { .ahrs($0) }
        default: return nil
        }
    }

    /// Big-endian signed 16-bit value at `i`, nil when 0x7FFF (invalid).
    private static func int16(_ p: [UInt8], _ i: Int) -> Int? {
        let v = Int(p[i]) << 8 | Int(p[i + 1])
        if v == 0x7FFF { return nil }
        return v & 0x8000 != 0 ? v - 0x10000 : v
    }

    /// Stratux AHRS report: 0x4C 0x45 0x01 version, then roll, pitch, heading, slip, turn rate, G (×0.1).
    static func stratuxAHRS(_ p: [UInt8]) -> AHRSAttitude? {
        guard let roll = int16(p, 4), let pitch = int16(p, 6) else { return nil }
        return AHRSAttitude(roll: Double(roll) / 10, pitch: Double(pitch) / 10,
                            heading: int16(p, 8).map { Double($0) / 10 },
                            slipSkid: int16(p, 10).map { Double($0) / 10 },
                            gLoad: int16(p, 14).map { Double($0) / 10 }, updated: .now)
    }

    /// ForeFlight AHRS message: 0x65 0x01, roll, pitch (×0.1°), heading (bit 15 = magnetic).
    static func foreFlightAHRS(_ p: [UInt8]) -> AHRSAttitude? {
        guard let roll = int16(p, 2), let pitch = int16(p, 4) else { return nil }
        let raw = Int(p[6]) << 8 | Int(p[7])
        let heading: Double? = raw == 0xFFFF ? nil : Double(raw & 0x7FFF) / 10
        return AHRSAttitude(roll: Double(roll) / 10, pitch: Double(pitch) / 10, heading: heading,
                            slipSkid: nil, gLoad: nil, updated: .now)
    }

    /// Ownship / Traffic Report layout (GDL 90 ICD §3.5.1).
    static func report(_ p: [UInt8]) -> TrafficTarget? {
        func int24(_ i: Int) -> Int {
            let v = Int(p[i]) << 16 | Int(p[i + 1]) << 8 | Int(p[i + 2])
            return v & 0x800000 != 0 ? v - 0x1000000 : v
        }
        let address = UInt32(p[2]) << 16 | UInt32(p[3]) << 8 | UInt32(p[4])
        let lat = Double(int24(5)) * 180 / 8_388_608
        let lon = Double(int24(8)) * 180 / 8_388_608
        guard lat != 0 || lon != 0 else { return nil }
        let altRaw = Int(p[11]) << 4 | Int(p[12]) >> 4
        let speed = Int(p[14]) << 4 | Int(p[15]) >> 4
        var vv = (Int(p[15]) & 0x0F) << 8 | Int(p[16])
        if vv & 0x800 != 0 { vv -= 0x1000 }
        let callsign = String(bytes: p[19..<27], encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        return TrafficTarget(id: address, callsign: callsign,
                             coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                             altitudeFt: altRaw == 0xFFF ? 0 : altRaw * 25 - 1000,
                             trackDeg: Int(Double(p[17]) * 360 / 256),
                             speedKt: speed == 0xFFF ? 0 : speed,
                             verticalFpm: vv == 0x800 ? 0 : vv * 64,
                             updated: .now)
    }
}

/// Listens for GDL 90 on UDP 4000 (the standard port; join the receiver's Wi-Fi first).
@MainActor
final class ADSBReceiver: ObservableObject {
    static let shared = ADSBReceiver()

    @Published private(set) var traffic: [TrafficTarget] = []
    @Published private(set) var ownship: TrafficTarget?
    @Published private(set) var lastHeartbeat: Date?
    /// Latest attitude from the receiver's AHRS, if it has one.
    @Published private(set) var ahrs: AHRSAttitude?
    @Published private(set) var running = false

    private var listener: NWListener?
    private var byID: [UInt32: TrafficTarget] = [:]

    var connected: Bool { lastHeartbeat.map { Date.now.timeIntervalSince($0) < 5 } ?? false }

    func start() {
        guard listener == nil, let l = try? NWListener(using: .udp, on: 4000) else { return }
        l.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global(qos: .userInitiated))
            Self.receive(on: connection, owner: self)
        }
        l.start(queue: .global(qos: .userInitiated))
        listener = l
        running = true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        running = false
        byID = [:]; traffic = []; ownship = nil; ahrs = nil
    }

    nonisolated private static func receive(on connection: NWConnection, owner: ADSBReceiver?) {
        connection.receiveMessage { data, _, _, error in
            if let data {
                let messages = GDL90.decode(data)
                Task { @MainActor in owner?.handle(messages) }
            }
            if error == nil { receive(on: connection, owner: owner) }
        }
    }

    private func handle(_ messages: [GDL90.Message]) {
        for m in messages {
            switch m {
            case .heartbeat: lastHeartbeat = .now
            case .ownship(let t): ownship = t
            case .traffic(let t): byID[t.id] = t
            case .ahrs(let a): ahrs = a
            case .uplink(let payload): FISBStore.shared.ingest(payload)
            }
        }
        byID = byID.filter { Date.now.timeIntervalSince($0.value.updated) < 30 }   // drop stale targets
        traffic = byID.values.sorted { $0.id < $1.id }
    }
}

/// Map marker for a traffic target.
final class TrafficAnnotation: NSObject, MKAnnotation {
    let target: TrafficTarget
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { target.callsign.isEmpty ? String(format: "%06X", target.id) : target.callsign }
    var subtitle: String? {
        String(format: "%05d ft · %d kt%@", target.altitudeFt, target.speedKt,
               target.verticalFpm > 300 ? " ↑" : target.verticalFpm < -300 ? " ↓" : "")
    }
    init(_ t: TrafficTarget) { target = t; coordinate = t.coordinate }
}
