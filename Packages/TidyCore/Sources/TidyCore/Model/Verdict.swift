import Foundation

public enum Kind: String, Codable, Sendable, CaseIterable { case camera, screenshot, forward, download, document, recording, video, received }
public enum VerdictKind: String, Codable, Sendable { case keep, review, junk }
public enum JunkType: String, Codable, Sendable {
    case duplicate, blurry, forward, meme, other
    case expiredOTP = "expired_otp", expiredQR = "expired_qr", oldPayment = "old_payment"
    case bigVideo = "big_video", screenRecording = "screen_recording", aiMade = "ai_made"
}
public enum DocType: String, Codable, Sendable { case receipt, bill, ticket, booking, id, other }
public enum Sensitive: String, Codable, Sendable { case aadhaar, pan, card, passport, bank, other }
public enum VerdictSource: String, Codable, Sendable { case rules, onDevice = "on_device", cloud }

public struct SavedInfo: Codable, Sendable, Equatable {
    public var type: String
    public var title: String
    public var fields: [String: String]
    public init(type: String, title: String, fields: [String: String]) { self.type = type; self.title = title; self.fields = fields }
}

public struct Verdict: Codable, Sendable {
    public var id: String
    public var kind: Kind
    public var verdict: VerdictKind
    public var reason: String
    public var junkType: JunkType?
    public var docType: DocType?
    public var sensitive: Sensitive?
    public var savedInfo: SavedInfo?
    public var confidence: Double
    public var source: VerdictSource

    enum CodingKeys: String, CodingKey {
        case id, kind, verdict, reason, sensitive, confidence, source
        case junkType = "junk_type", docType = "doc_type", savedInfo = "saved_info"
    }

    public init(id: String, kind: Kind, verdict: VerdictKind, reason: String, junkType: JunkType? = nil,
                docType: DocType? = nil, sensitive: Sensitive? = nil, savedInfo: SavedInfo? = nil,
                confidence: Double, source: VerdictSource) {
        self.id = id; self.kind = kind; self.verdict = verdict; self.reason = reason
        self.junkType = junkType; self.docType = docType; self.sensitive = sensitive
        self.savedInfo = savedInfo; self.confidence = confidence; self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        verdict = try c.decode(VerdictKind.self, forKey: .verdict)
        reason = try c.decode(String.self, forKey: .reason)
        junkType = try c.decodeIfPresent(JunkType.self, forKey: .junkType)
        docType = try c.decodeIfPresent(DocType.self, forKey: .docType)
        sensitive = try c.decodeIfPresent(Sensitive.self, forKey: .sensitive)
        savedInfo = try c.decodeIfPresent(SavedInfo.self, forKey: .savedInfo)
        confidence = try c.decode(Double.self, forKey: .confidence)
        source = try c.decodeIfPresent(VerdictSource.self, forKey: .source) ?? .onDevice
    }
}

public enum Bucket: String, CaseIterable, Sendable {
    case realPhotos, duplicates, blurry, forwards, expiredScreenshots, usefulScreenshots, otherScreenshots, receivedPhotos, memes, documents, memesDownloads, idsCards, bigVideos, aiMade
}
