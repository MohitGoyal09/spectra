import Foundation
import Photos
import MapKit
import Vision
import TidyCore

/// Background pass after a scan: detailed labels with confidence, picture-search vectors and place names
/// for photos that don't have them yet. Fills in an existing index without a full re-scan.
@MainActor @Observable final class Enricher {
    private(set) var running = false
    private(set) var done = 0
    private(set) var total = 0
    @ObservationIgnored private let store: IndexStore
    @ObservationIgnored let clip: ClipStore
    @ObservationIgnored private let placesURL: URL
    @ObservationIgnored private var places: [String: String]
    @ObservationIgnored private let log: PrivacyLog

    /// Place names need Apple Maps, so they are off until the user turns them on (Privacy log screen).
    static var placesAllowed: Bool {
        get { UserDefaults.standard.bool(forKey: "placeNamesAllowed") }
        set { UserDefaults.standard.set(newValue, forKey: "placeNamesAllowed") }
    }

    private enum Config {
        static let imageSide: CGFloat = 320
        static let concurrency = 3
        static let chunk = 24
        static let clusterDegrees = 0.02          // ~2 km: one place lookup per neighbourhood, not per photo
        static let lookupsPerRun = 40
        static let lookupSpacing: Duration = .milliseconds(1200)   // stay under Apple's geocoding rate limit
    }

    init(store: IndexStore, directory: URL, log: PrivacyLog) {
        self.store = store
        self.log = log
        clip = ClipStore(directory: directory)
        placesURL = directory.appendingPathComponent("places.json")
        places = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: placesURL))) ?? [:]
    }

    /// Runs once at a time; safe to call after every scan and on launch.
    func run(onChange: @escaping @MainActor () -> Void) async {
        guard !running else { return }
        running = true
        defer { running = false }
        await ClipModel.warmUp()
        let clip = ClipModel.ready
        let clipOn = clip != nil
        self.clip.remove(self.clip.vectors.keys.filter { store.items[$0] == nil })
        let todo = store.items.values
            .filter { $0.verdict.sensitive == nil && ($0.record.labelScores == nil || (clipOn && self.clip.vectors[$0.record.id] == nil)) }
            .sorted { $0.record.createdAt > $1.record.createdAt }
            .map { ($0.record.id, $0.record.labelScores == nil) }
        total = todo.count; done = 0
        for offset in stride(from: 0, to: todo.count, by: Config.chunk) {
            let chunk = Array(todo[offset..<min(offset + Config.chunk, todo.count)])
            for (id, scores, vector) in await Self.analyze(chunk, clip: clip) {
                if let scores { store.update(id) { $0.record.labelScores = scores } }
                if let vector { self.clip.set(id, vector) }
            }
            done += chunk.count
            if (offset / Config.chunk) % 8 == 7 { store.save(); self.clip.save(); onChange() }
        }
        store.save(); self.clip.save()
        if Self.placesAllowed { await lookUpPlaces() }
        onChange()
    }

    private nonisolated static func analyze(_ items: [(String, Bool)], clip: ClipModel?) async -> [(String, [String: Float]?, [Float]?)] {
        await withTaskGroup(of: (String, [String: Float]?, [Float]?).self) { group in
            var out: [(String, [String: Float]?, [Float]?)] = []
            var next = 0
            func add() {
                guard next < items.count else { return }
                let (id, needLabels) = items[next]; next += 1
                group.addTask {
                    guard let ui = await Gallery.image(id, maxPixel: Config.imageSide), let cg = ui.cgImage else { return (id, nil, nil) }
                    let scores = needLabels ? VisionAnalyzer.scores((try? await ClassifyImageRequest().perform(on: cg)) ?? []) : nil
                    return (id, scores, clip?.embed(cg))
                }
            }
            for _ in 0..<Config.concurrency { add() }
            while let r = await group.next() { out.append(r); add() }
            return out
        }
    }

    // MARK: Places

    /// Town and region for photos with a location. Only with the user's opt-in; Apple Maps receives one rounded point
    /// (~2 km) per area, never a photo, and every lookup is recorded in the privacy log.
    private func lookUpPlaces() async {
        let missing = store.items.values.filter { $0.record.place == nil && $0.verdict.sensitive == nil }.map(\.record.id)
        guard !missing.isEmpty else { return }
        var areaOf: [String: String] = [:]
        var center: [String: CLLocation] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: missing, options: nil).enumerateObjects { a, _, _ in
            guard let c = a.location?.coordinate else { return }
            let lat = (c.latitude / Config.clusterDegrees).rounded() * Config.clusterDegrees
            let lon = (c.longitude / Config.clusterDegrees).rounded() * Config.clusterDegrees
            let key = String(format: "%.2f,%.2f", lat, lon)
            areaOf[a.localIdentifier] = key
            center[key] = CLLocation(latitude: lat, longitude: lon)
        }
        for key in Set(areaOf.values).filter({ places[$0] == nil }).prefix(Config.lookupsPerRun) {
            guard Self.placesAllowed, let loc = center[key], let request = MKReverseGeocodingRequest(location: loc) else { continue }
            log.append(PrivacyEntry(date: .now, task: "place name", model: "Apple Maps", sentText: "Rounded location \(key)"))
            let item = try? await request.mapItems.first
            let a = item?.addressRepresentations
            var seen = Set<String>()
            places[key] = [a?.cityName, a?.cityWithContext, a?.regionName].compactMap { $0 }
                .flatMap { $0.components(separatedBy: ", ") }.filter { seen.insert($0).inserted }.joined(separator: ", ")
            try? await Task.sleep(for: Config.lookupSpacing)
        }
        try? JSONEncoder().encode(places).write(to: placesURL, options: .atomic)
        for (id, key) in areaOf { if let p = places[key], !p.isEmpty { store.update(id) { $0.record.place = p } } }
        store.save()
    }
}
