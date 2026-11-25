import SwiftUI
import Photos
import TidyCore

/// Point i of n on a unit sphere (Fibonacci lattice): an even spread with no poles bunching.
func fibonacciSpherePoint(_ i: Int, of n: Int) -> SIMD3<Double> {
    let y = 1 - (Double(i) + 0.5) / Double(n) * 2
    let r = (1 - y * y).squareRoot()
    let theta = Double(i) * .pi * (3 - 5.0.squareRoot())
    return SIMD3(cos(theta) * r, y, sin(theta) * r)
}

/// Rotates a point about the Y axis, then tilts it toward the viewer.
func projectOnGlobe(_ p: SIMD3<Double>, spin: Double, tilt: Double = -0.35) -> SIMD3<Double> {
    let x = p.x * cos(spin) + p.z * sin(spin)
    let z = -p.x * sin(spin) + p.z * cos(spin)
    return SIMD3(x, p.y * cos(tilt) - z * sin(tilt), p.y * sin(tilt) + z * cos(tilt))
}

/// Ease-out position on a quadratic curve from `a` to `b` that bows upward, for photos streaming to a folder.
func streamPoint(from a: CGPoint, to b: CGPoint, t raw: Double, bow: CGFloat) -> CGPoint {
    let t = 1 - pow(1 - min(max(raw, 0), 1), 3)
    let c = CGPoint(x: (a.x + b.x) / 2 + bow, y: min(a.y, b.y) - 80)
    let u = 1 - t
    return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
}

/// State for the scan moment: a dense globe of the user's photos that wears away as each photo streams to its folder.
/// Drawn in one Canvas so hundreds of tiles stay smooth.
@MainActor @Observable final class ScanStage {
    struct Tile { var image: CGImage?; let point: SIMD3<Double>; var gone = false; var appearDelay: Double = 0 }
    struct Flight { let tile: Int; let folder: Int; let start: Date; let from: CGPoint; let bow: CGFloat }

    static let tileCount = 360
    static let flightTime: TimeInterval = 0.95
    private(set) var tiles: [Tile] = []
    private(set) var flights: [Flight] = []
    private(set) var strips: [[CGImage]] = []          // per folder, newest last
    private(set) var confettiStart: Date?
    /// When the globe last re-formed (tiles grow in from zero, staggered).
    private(set) var formedAt: Date?
    /// True once the globe shows what was kept rather than what is being sorted.
    private(set) var kept = false
    @ObservationIgnored var globeFrame: CGRect = .zero
    @ObservationIgnored var folderFrames: [Int: CGRect] = [:]
    @ObservationIgnored private var consumed = 0
    @ObservationIgnored private var order: [Int] = []

    init(folders: Int) { strips = Array(repeating: [], count: folders) }

    func load(ids: [String]) async {
        kept = false
        consumed = 0
        flights = []
        build(ids)
    }

    /// Re-forms the globe from the photos that stay (real photos), tiles growing in from the centre outward.
    func reform(ids: [String]) {
        kept = true
        flights = []
        build(ids)
    }

    /// Fills folder covers from the existing index (used when nothing new is sorted).
    func fillStrips(_ idsByFolder: [Int: [String]]) {
        for (folder, ids) in idsByFolder where strips.indices.contains(folder) && strips[folder].isEmpty {
            requestImages(Array(ids.prefix(3))) { [weak self] img in self?.strips[folder].append(img) }
        }
    }

    private func build(_ ids: [String]) {
        let n = min(Self.tileCount, max(ids.count, 1))
        tiles = (0..<n).map { i in
            let p = fibonacciSpherePoint(i, of: n)
            return Tile(image: nil, point: p, appearDelay: (1 - abs(p.y)) * 0.25 + Double(i % 7) * 0.02)
        }
        order = Array(tiles.indices).shuffled()
        formedAt = Date()
        guard !ids.isEmpty else { return }
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic; o.resizeMode = .fast; o.isNetworkAccessAllowed = true   // fastFormat gives nothing for uncached new photos
        let wanted = Array(ids.prefix(n))
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: wanted, options: nil)
        assets.enumerateObjects { asset, i, _ in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 48, height: 48), contentMode: .aspectFill, options: o) { img, _ in
                guard let cg = img?.cgImage else { return }
                Task { @MainActor in if i < self.tiles.count { self.tiles[i].image = cg } }
            }
        }
    }

    private func requestImages(_ ids: [String], each: @escaping @MainActor (CGImage) -> Void) {
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic; o.resizeMode = .fast; o.isNetworkAccessAllowed = true   // fastFormat gives nothing for uncached new photos
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 80, height: 80), contentMode: .aspectFill, options: o) { img, _ in
                guard let cg = img?.cgImage else { return }
                Task { @MainActor in each(cg) }
            }
        }
    }

    /// Consume new scan events: remove globe tiles in proportion to progress and launch a staggered stream toward the folders.
    func consume(events: [(id: String, bucket: Bucket)], done: Int, total: Int, folderOf: (Bucket) -> Int, reduceMotion: Bool) {
        guard consumed < events.count, !tiles.isEmpty else { return }
        let fresh = events[consumed...]
        consumed = events.count
        let targetGone = total == 0 ? 0 : Int((Double(done) / Double(total) * Double(tiles.count)).rounded())
        var budget = max(0, targetGone - tiles.filter(\.gone).count)
        let now = Date()
        for (k, e) in fresh.enumerated() {
            let folder = folderOf(e.bucket)
            guard budget > 0, let tile = order.first(where: { !tiles[$0].gone }) else { continue }
            budget -= 1
            tiles[tile].gone = true
            if reduceMotion { landed(tile: tile, folder: folder); continue }
            let p = projectOnGlobe(tiles[tile].point, spin: spin(at: now))
            let r = globeFrame.width / 2 - 8
            let from = CGPoint(x: globeFrame.midX + p.x * r, y: globeFrame.midY + p.y * r)
            flights.append(Flight(tile: tile, folder: folder, start: now.addingTimeInterval(Double(k) * 0.035), from: from,
                                  bow: CGFloat.random(in: -60...60)))
        }
        if budget > 0 {   // catch up without animation when far behind
            for tile in order where !tiles[tile].gone && budget > 0 { tiles[tile].gone = true; budget -= 1 }
        }
    }

    /// Called every frame: moves finished flights into their folder strip.
    func settle(at now: Date) {
        let (done, flying) = flights.reduce(into: ([Flight](), [Flight]())) { acc, f in
            now.timeIntervalSince(f.start) >= Self.flightTime ? acc.0.append(f) : acc.1.append(f)
        }
        guard !done.isEmpty else { return }
        flights = flying
        for f in done { landed(tile: f.tile, folder: f.folder) }
    }

    private func landed(tile: Int, folder: Int) {
        guard strips.indices.contains(folder), let img = tiles[tile].image else { return }
        strips[folder].append(img)
        if strips[folder].count > 12 { strips[folder].removeFirst() }
    }

    func celebrate() { if confettiStart == nil { confettiStart = Date() } }

    func spin(at date: Date) -> Double { date.timeIntervalSinceReferenceDate * 0.3 }
}

/// Full-screen drawing layer: the globe, the stream of photos, and the finish confetti.
struct ScanCanvas: View {
    let stage: ScanStage
    var spinning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion && stage.flights.isEmpty)) { ctx in
            Canvas { g, _ in
                let now = ctx.date
                let spin = (reduceMotion || !spinning) ? 0.6 : stage.spin(at: now)
                drawGlobe(&g, spin: spin, now: now)
                drawFlights(&g, now: now)
                drawConfetti(&g, now: now)
            }
            .onChange(of: ctx.date) { _, d in stage.settle(at: d) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawGlobe(_ g: inout GraphicsContext, spin: Double, now: Date) {
        let f = stage.globeFrame
        guard f.width > 0 else { return }
        let r = f.width / 2 - 8
        let size: CGFloat = max(10, r * 0.15)
        let projected = stage.tiles.indices.compactMap { i -> (Int, SIMD3<Double>)? in
            stage.tiles[i].gone ? nil : (i, projectOnGlobe(stage.tiles[i].point, spin: spin))
        }.sorted { $0.1.z < $1.1.z }
        for (i, p) in projected {
            let depth = (p.z + 1) / 2
            let grow = reduceMotion ? 1 : min(1, max(0, (now.timeIntervalSince(stage.formedAt ?? .distantPast) - stage.tiles[i].appearDelay) / 0.45))
            guard grow > 0 else { continue }
            let s = size * (0.6 + 0.4 * depth) * (1 - pow(1 - grow, 3))
            let rect = CGRect(x: f.midX + p.x * r - s / 2, y: f.midY + p.y * r - s / 2, width: s, height: s)
            g.opacity = 0.35 + 0.65 * depth
            draw(&g, stage.tiles[i].image, in: rect)
        }
        g.opacity = 1
    }

    private func drawFlights(_ g: inout GraphicsContext, now: Date) {
        for f in stage.flights {
            let t = now.timeIntervalSince(f.start) / ScanStage.flightTime
            guard t >= 0, let target = stage.folderFrames[f.folder] else { continue }
            let to = CGPoint(x: target.minX + 26, y: target.midY + 10)
            let p = streamPoint(from: f.from, to: to, t: t, bow: f.bow)
            let s: CGFloat = 26 - 8 * CGFloat(min(t, 1))
            draw(&g, stage.tiles[f.tile].image, in: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s))
        }
    }

    private func drawConfetti(_ g: inout GraphicsContext, now: Date) {
        guard let start = stage.confettiStart, !reduceMotion else { return }
        let t = now.timeIntervalSince(start)
        guard t < 2.2 else { return }
        let f = stage.globeFrame
        for i in 0..<70 {
            let a = Double(i) * 2.399
            let speed = 160 + Double(i % 7) * 30
            let x = f.midX + cos(a) * speed * t
            let y = f.midY + sin(a) * speed * t * 0.7 + 260 * t * t
            g.opacity = max(0, 1 - t / 2.2)
            g.fill(Path(roundedRect: CGRect(x: x, y: y, width: 6, height: 9), cornerRadius: 1.5),
                   with: .color(Palette.glow[i % 4]))
        }
        g.opacity = 1
    }

    private func draw(_ g: inout GraphicsContext, _ image: CGImage?, in rect: CGRect) {
        let path = Path(roundedRect: rect, cornerRadius: rect.width * 0.18)
        if let image {
            g.drawLayer { l in l.clip(to: path); l.draw(Image(decorative: image, scale: 1), in: rect) }
        } else {
            g.fill(path, with: .color(Color(.systemGray4)))
        }
    }
}
