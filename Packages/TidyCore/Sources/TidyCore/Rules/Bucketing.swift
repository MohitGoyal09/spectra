import Foundation

public enum RuleConfig {
    public static let bigVideoBytes: Int64 = 200_000_000
    public static let blurThreshold: Float = 0.16
    public static let otpExpiryDays = 1.0
    public static let undatedTicketExpiryDays = 30.0
    static let greetingLabels: Set<String> = ["flower", "sunrise", "sunset", "sunset_sunrise", "deity", "candle", "fireworks"]
    static let documentLabels: Set<String> = ["document", "printed_page", "handwriting", "receipt", "paper"]
    static let sceneLabels: Set<String> = ["people", "adult", "child", "outdoor", "land", "sky", "food", "animal", "dog", "cat", "beach",
                                           "mountain", "water_body", "plant", "tree", "vehicle", "automobile"]
    static let memeLabels: Set<String> = ["art", "illustrations", "cartoon", "sign", "poster", "comic", "text"]
    /// Phone status bar text ("6:08 LTE 91%", "Jio 5G"), a sign that an image is someone else's screenshot.
    static let statusBar = #"(\b\d{1,2}:\d{2}\b.{0,40}(lte|5g|4g|wi-?fi|\d{1,3}\s?%))|(\bjio\b|\bairtel\b|\bvi\b).{0,20}(5g|4g|lte)"#
}

func shortDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "d MMM"
    return f.string(from: d)
}

func sizeText(_ bytes: Int64) -> String {
    bytes >= 1_000_000_000 ? String(format: "%.1f GB", Double(bytes) / 1e9) : String(format: "%.0f MB", Double(bytes) / 1e6)
}

private let sensitiveReason: [Sensitive: String] = [
    .aadhaar: "Looks like an Aadhaar card — lock it", .pan: "Looks like a PAN card — lock it",
    .card: "Looks like a bank card — lock it", .bank: "Looks like a cheque or bank details — lock it",
    .passport: "Looks like a passport — lock it", .other: "Looks like an ID — lock it",
]

/// Deterministic verdict for one photo. This is the final verdict; the model may only add titles and saved info.
public func ruleVerdict(_ r: PhotoRecord, hits: RuleHits, now: Date, bigVideoBytes: Int64 = RuleConfig.bigVideoBytes) -> Verdict {
    let ageDays = now.timeIntervalSince(r.createdAt) / 86_400
    let hasCamera = r.cameraMake != nil
    let fromWhatsApp = r.sourceAlbums.contains { $0.localizedCaseInsensitiveContains("whatsapp") }
    func v(_ kind: Kind, _ verdict: VerdictKind, _ reason: String, _ junk: JunkType? = nil, _ conf: Double = 0.9) -> Verdict {
        Verdict(id: r.id, kind: kind, verdict: verdict, reason: reason, junkType: junk, docType: hits.docType,
                sensitive: hits.sensitive, confidence: conf, source: .rules)
    }

    if let s = hits.sensitive { return v(r.isScreenshot ? .screenshot : .document, .keep, sensitiveReason[s]!, nil, 0.95) }
    if r.isVideo {
        if r.isScreenRecording { return v(.recording, .review, "Screen recording, \(sizeText(r.fileBytes))", .screenRecording) }
        if r.fileBytes >= bigVideoBytes { return v(.video, .review, "Video, \(sizeText(r.fileBytes))", .bigVideo) }
        return v(.video, .keep, "Video")
    }
    if let ai = aiMadeSource(r.provenance) { return v(.download, .review, ai, .aiMade) }
    if r.isScreenshot {
        if hits.otp {
            return ageDays > RuleConfig.otpExpiryDays
                ? v(.screenshot, .junk, "OTP from \(shortDate(r.createdAt)), expired", .expiredOTP)
                : v(.screenshot, .review, "Recent OTP", nil, 0.6)
        }
        if hits.ticketOrQR {
            if let d = hits.eventDate, d < now { return v(.screenshot, .junk, "Ticket for \(shortDate(d)), date passed", .expiredQR) }
            if hits.eventDate == nil, ageDays > RuleConfig.undatedTicketExpiryDays {
                return v(.screenshot, .junk, "Code from \(shortDate(r.createdAt)), likely used", .expiredQR, 0.7)
            }
        }
        if hits.payment { return v(.screenshot, .review, "Payment screenshot from \(shortDate(r.createdAt))", .oldPayment) }
    }
    let greetingLook = !Set(r.labels).isDisjoint(with: RuleConfig.greetingLabels)
    if !hasCamera, !r.isScreenshot, hits.greeting || (fromWhatsApp && greetingLook && r.ocrText.count > 5) {
        return v(.forward, .junk, fromWhatsApp ? "Greeting forward from WhatsApp" : "Greeting image", .forward)
    }
    if let blur = r.blurScore, blur < RuleConfig.blurThreshold {
        return v(hasCamera ? .camera : .download, .review, "Blurry shot", .blurry, 0.7)
    }
    if hasCamera, !r.isScreenshot, !fromWhatsApp { return v(.camera, .keep, "Camera photo") }
    if r.isScreenshot { return v(.screenshot, .review, "Screenshot", nil, 0.4) }
    return receivedVerdict(r, labels: Set(r.labels), v: v)
}

/// Images that came from elsewhere (no camera EXIF, not this phone's screenshot): split them by what they are.
private func receivedVerdict(_ r: PhotoRecord, labels: Set<String>, v: (Kind, VerdictKind, String, JunkType?, Double) -> Verdict) -> Verdict {
    let text = r.ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
    let looksLikeScreenshot = labels.contains("screenshot") ||
        text.range(of: RuleConfig.statusBar, options: [.regularExpression, .caseInsensitive]) != nil
    if looksLikeScreenshot { return v(.screenshot, .review, "Screenshot someone sent you", nil, 0.6) }
    if !labels.isDisjoint(with: RuleConfig.documentLabels), text.count >= 80 { return v(.document, .review, "Photo of a document", nil, 0.6) }
    if r.faceCount > 0 { return v(.received, .review, "Photo of people from a chat", nil, 0.6) }
    if text.count >= 12, text.count < 200, !labels.isDisjoint(with: RuleConfig.memeLabels.union(["structure"])) {
        return v(.download, .review, "Meme or poster", .meme, 0.6)
    }
    if !labels.isDisjoint(with: RuleConfig.sceneLabels), text.count < 25 { return v(.received, .review, "Photo from a chat", nil, 0.6) }
    return v(.download, .review, "Saved image", nil, 0.4)
}

public func bucket(for v: Verdict, record: PhotoRecord) -> Bucket {
    if v.sensitive != nil { return .idsCards }
    switch v.junkType {
    case .duplicate: return .duplicates
    case .blurry: return .blurry
    case .forward: return .forwards
    case .expiredOTP, .expiredQR: return .expiredScreenshots
    case .oldPayment: return .usefulScreenshots
    case .bigVideo, .screenRecording: return .bigVideos
    case .aiMade: return .aiMade
    case .meme: return .memes
    case .other, .none: break
    }
    if v.savedInfo != nil { return .usefulScreenshots }
    switch v.kind {
    case .camera, .video: return .realPhotos
    case .screenshot, .recording: return .otherScreenshots
    case .received: return .receivedPhotos
    case .document: return .documents
    case .forward, .download: return .memesDownloads
    }
}
