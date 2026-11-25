import Vision
import CoreImage
import CoreGraphics
import TidyCore

struct VisionResult: Sendable {
    var labels: [String] = []
    var labelScores: [String: Float] = [:]
    var ocrText = ""
    var barcodes: [String] = []
    var faceCount = 0
    var faceQuality: Float = 0
    var blurScore: Float?
    var dHash: UInt64 = 0
    var featurePrint: Data?
}

protocol Analyzing: Sendable {
    func analyze(_ image: CGImage, textHeavy: Bool) async -> VisionResult
}

/// Cumulative seconds per stage, for the scan report.
final class StageTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var totals: [String: Double] = [:]
    func add(_ stage: String, _ seconds: Double) { lock.lock(); totals[stage, default: 0] += seconds; lock.unlock() }
    func measure<T>(_ stage: String, _ work: () async -> T) async -> T {
        let t0 = Date(); let v = await work(); add(stage, Date().timeIntervalSince(t0)); return v
    }
    var snapshot: [String: Double] { lock.lock(); defer { lock.unlock() }; return totals }
    func reset() { lock.lock(); totals = [:]; lock.unlock() }
}

/// Vision preprocessing only: it turns pixels into text and numbers. Every judgement runs through Firebase AI Logic.
final class VisionAnalyzer: Analyzing {
    private static let texty: Set<String> = ["document", "screenshot", "printed_page", "sign", "handwriting"]
    private let ci = CIContext(options: [.cacheIntermediates: false])

    let timer = StageTimer()

    func analyze(_ image: CGImage, textHeavy: Bool) async -> VisionResult {
        guard image.width >= 32, image.height >= 32 else { return VisionResult() }
        var out = VisionResult()
        let classes = await timer.measure("classify") { (try? await ClassifyImageRequest().perform(on: image)) ?? [] }
        out.labels = Array(classes.filter { $0.confidence >= 0.3 }.prefix(5).map(\.identifier))
        out.labelScores = Self.scores(classes)
        let texty = textHeavy || out.labels.contains { Self.texty.contains($0) }

        var text = RecognizeTextRequest()
        text.recognitionLevel = texty ? .accurate : .fast
        text.usesLanguageCorrection = texty
        out.ocrText = await timer.measure("ocr") {
            ((try? await text.perform(on: image)) ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }
        if texty {   // QR codes only matter on screenshots and documents
            out.barcodes = await timer.measure("barcodes") { ((try? await DetectBarcodesRequest().perform(on: image)) ?? []).compactMap(\.payloadString) }
        }
        out.faceCount = await timer.measure("faces") { ((try? await DetectFaceRectanglesRequest().perform(on: image)) ?? []).count }
        out.blurScore = await timer.measure("blur") { blurScore(image) }
        out.dHash = dHashOf(image)
        if !texty {  // near-duplicate fingerprints only for photos; screenshots use the hash
            out.featurePrint = await timer.measure("featureprint") { featurePrintData(image) }
        }
        return out
    }

    /// Up to 15 labels with confidence ≥ 0.1, for search and albums (matching needs ≥ MatchConfig.minLabelScore).
    static func scores(_ classes: [ClassificationObservation]) -> [String: Float] {
        Dictionary(classes.filter { $0.confidence >= 0.1 }.prefix(15).map { ($0.identifier, $0.confidence) }, uniquingKeysWith: max)
    }

    /// Edge energy on a 96 px copy (lower = blurrier; threshold 0.16). Same method and constants as
    /// nilkanthdesai76/swift-vision-photo-dedupe BlurDetector (MIT). Near-black frames return nil (not judged).
    private func blurScore(_ image: CGImage) -> Float? {
        // Shrink to 96 px on the CPU first; filtering the 1024 px image through a CI transform cost ~45× more.
        guard let tiny = downscaled(image, maxSide: 96) else { return nil }
        let small = CIImage(cgImage: tiny)
        guard let mean = average(small) else { return nil }
        if 0.2126 * mean[0] + 0.7152 * mean[1] + 0.0722 * mean[2] < 0.06 { return nil }
        guard let edges = CIFilter(name: "CIEdges", parameters: [kCIInputImageKey: small, kCIInputIntensityKey: 10.0])?.outputImage,
              let e = average(edges, extent: small.extent) else { return nil }
        return e[0] + e[1] + e[2]
    }

    private func downscaled(_ image: CGImage, maxSide: Int) -> CGImage? {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private func average(_ image: CIImage, extent: CGRect? = nil) -> [Float]? {
        guard let out = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image,
                                 kCIInputExtentKey: CIVector(cgRect: extent ?? image.extent)])?.outputImage else { return nil }
        var px: [Float] = [0, 0, 0, 0]
        ci.render(out, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        return px
    }

    private func dHashOf(_ image: CGImage) -> UInt64 {
        var px = [UInt8](repeating: 0, count: 72)
        guard let ctx = CGContext(data: &px, width: 9, height: 8, bitsPerComponent: 8, bytesPerRow: 9,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
        return dHash(gray9x8: px)
    }

    private func featurePrintData(_ image: CGImage) -> Data? {
        let req = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(cgImage: image).perform([req])
        guard let obs = req.results?.first else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
    }

    static func distance(_ a: Data, _ b: Data) -> Float? {
        guard let x = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: a),
              let y = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: b) else { return nil }
        var d: Float = 0
        return (try? x.computeDistance(&d, to: y)) != nil ? d : nil
    }
}
