import CoreML
import CoreGraphics
import Vision
import Accelerate

/// On-device picture search with OpenAI CLIP ViT-B/32 (MIT licence), converted by `scripts/convert_clip.py`.
/// Photos and queries become 512-number vectors; similar meaning = similar vectors. Nothing leaves the iPhone.
/// Off (isAvailable == false) when the models aren't bundled, so the app still builds without them.
final class ClipModel: @unchecked Sendable {
    static let dimensions = 512

    /// The models are in the app bundle (checked without loading them).
    static let bundled = ["ClipImage", "ClipText"].allSatisfy { Bundle.main.url(forResource: $0, withExtension: "mlmodelc") != nil }

    nonisolated(unsafe) private static var loaded: ClipModel?
    private static let loadLock = NSLock()

    /// The loaded model, or nil while it is still loading (never blocks the caller).
    static var ready: ClipModel? { loadLock.withLock { loaded } }

    /// Loads both models off the main thread. The first load compiles them for the Neural Engine and can take
    /// several seconds, so it must never run on the main thread.
    static func warmUp() async {
        guard bundled, ready == nil else { return }
        let model = await Task.detached(priority: .utility) { ClipModel() }.value
        loadLock.withLock { if loaded == nil, model.isAvailable { loaded = model } }
    }

    private static let contextLength = 77

    private let imageModel: MLModel?
    private let textModel: MLModel?
    private let tokenizer: CLIPTokenizer?
    private let lock = NSLock()   // Limit: one prediction at a time; per-model queues if indexing needs more speed

    var isAvailable: Bool { imageModel != nil && textModel != nil && tokenizer != nil }

    private init() {
        let config = MLModelConfiguration(); config.computeUnits = .all
        func load(_ name: String) -> MLModel? {
            Bundle.main.url(forResource: name, withExtension: "mlmodelc").flatMap { try? MLModel(contentsOf: $0, configuration: config) }
        }
        imageModel = load("ClipImage")
        textModel = load("ClipText")
        tokenizer = Bundle.main.url(forResource: "clip-vocab", withExtension: "json") == nil ? nil : CLIPTokenizer()
    }

    /// Unit vector for a photo (centre-cropped to 224 × 224 by Core ML).
    func embed(_ image: CGImage) -> [Float]? {
        guard let imageModel, let constraint = imageModel.modelDescription.inputDescriptionsByName["image"]?.imageConstraint,
              let value = try? MLFeatureValue(cgImage: image, constraint: constraint,
                                              options: [.cropAndScale: VNImageCropAndScaleOption.centerCrop.rawValue]) else { return nil }
        return predict(imageModel, ["image": value])
    }

    /// Unit vector for a query, phrased the way CLIP was trained ("a photo of …").
    func embed(text: String) -> [Float]? {
        guard let textModel, let tokenizer, let ids = try? MLMultiArray(shape: [1, NSNumber(value: Self.contextLength)], dataType: .int32) else { return nil }
        let tokens = Array(tokenizer.encode(text: text).prefix(Self.contextLength - 2))
        let full = [tokenizer.encoder["<|startoftext|>"]!] + tokens + [tokenizer.encoder["<|endoftext|>"]!]
        for i in 0..<Self.contextLength { ids[i] = NSNumber(value: i < full.count ? full[i] : 0) }
        return predict(textModel, ["ids": MLFeatureValue(multiArray: ids)])
    }

    private func predict(_ model: MLModel, _ inputs: [String: MLFeatureValue]) -> [Float]? {
        lock.lock(); defer { lock.unlock() }
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: inputs),
              let out = try? model.prediction(from: provider).featureValue(for: "embedding")?.multiArrayValue,
              out.count == Self.dimensions else { return nil }
        return (0..<out.count).map { out[$0].floatValue }
    }

    /// Cosine similarity of one query with many stored photos (all vectors are unit length, so a dot product).
    static func similarities(_ query: [Float], _ photos: [[Float]]) -> [Float] {
        photos.map { p in
            var d: Float = 0
            vDSP_dotpr(query, 1, p, 1, &d, vDSP_Length(min(query.count, p.count)))
            return d
        }
    }
}
