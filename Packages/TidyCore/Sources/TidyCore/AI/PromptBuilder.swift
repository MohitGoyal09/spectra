import Foundation

public enum PromptConfig {
    public static let ocrChars = 100
    public static let batchSize = 5
}

/// One compact text line per photo for the judge model. Cloud prompts are masked and never include sensitive items.
public func judgePrompt(records: [(PhotoRecord, RuleHits)], forCloud: Bool, now: Date) -> String {
    records.compactMap { r, h -> String? in
        if forCloud && h.sensitive != nil { return nil }
        var flags: [String] = []
        if r.isScreenshot { flags.append("screenshot") }
        if r.sourceAlbums.contains(where: { $0.localizedCaseInsensitiveContains("whatsapp") }) { flags.append("whatsapp") }
        flags.append(r.cameraMake == nil ? "no-camera-exif" : "camera-exif")
        var hits: [String] = []
        if h.otp { hits.append("otp") }
        if h.payment { hits.append("payment") }
        if h.ticketOrQR { hits.append("ticket") }
        if h.greeting { hits.append("greeting") }
        if let d = h.docType { hits.append(d.rawValue) }
        // Mask the full text first, then cut at a word boundary, so no fragment of a number or address escapes the mask.
        let text = clip(forCloud ? mask(r.ocrText) : r.ocrText, to: PromptConfig.ocrChars)
        let age = Int(now.timeIntervalSince(r.createdAt) / 86_400)
        return "\(r.id) | \(flags.joined(separator: ",")) | \(r.labels.prefix(4).joined(separator: ",")) | \(hits.joined(separator: ",")) | \(text) | \(age)d"
    }.joined(separator: "\n")
}

/// Prefix of at most `limit` characters, ending at the last whitespace so tokens are never split.
func clip(_ s: String, to limit: Int) -> String {
    guard s.count > limit else { return s }
    let head = s.prefix(limit)
    guard let cut = head.lastIndex(where: \.isWhitespace) else { return "" }
    return String(head[..<cut])
}
