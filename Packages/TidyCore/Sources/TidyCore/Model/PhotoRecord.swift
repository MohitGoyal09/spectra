import Foundation

public struct ProvenanceInput: Codable, Sendable, Equatable {
    public var digitalSourceType: String?
    public var software: String?
    public var creatorTool: String?
    public var hasC2PA: Bool
    public init(digitalSourceType: String? = nil, software: String? = nil, creatorTool: String? = nil, hasC2PA: Bool = false) {
        self.digitalSourceType = digitalSourceType; self.software = software; self.creatorTool = creatorTool; self.hasC2PA = hasC2PA
    }
}

public struct PhotoRecord: Codable, Sendable {
    public var id: String
    public var createdAt: Date
    public var isScreenshot = false
    public var isScreenRecording = false
    public var isVideo = false
    public var durationSec: Double?
    public var pixelWidth = 0
    public var pixelHeight = 0
    public var fileBytes: Int64 = 0
    public var isLocal = true
    public var isFavorite = false
    public var sourceAlbums: [String] = []
    public var cameraMake: String?
    public var cameraModel: String?
    public var ocrText = ""
    public var labels: [String] = []
    /// Up to 15 Vision labels with confidence, for search and albums (bucketing keeps using the top `labels`).
    public var labelScores: [String: Float]?
    /// Town and region from the photo's location ("Panaji, Goa, India").
    public var place: String?
    public var faceCount = 0
    public var barcodePayloads: [String] = []
    public var blurScore: Float?
    public var provenance = ProvenanceInput()
    public init(id: String, createdAt: Date) { self.id = id; self.createdAt = createdAt }
}
