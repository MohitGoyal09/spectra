import Foundation

public struct RuleHits: Equatable, Sendable {
    public var otp = false
    public var payment = false
    public var ticketOrQR = false
    public var greeting = false
    public var eventDate: Date?
    public var sensitive: Sensitive?
    public var docType: DocType?
    public init() {}
}

private func has(_ pattern: String, _ text: String, caseInsensitive: Bool = true) -> Bool {
    text.range(of: pattern, options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression) != nil
}

private func matches(_ pattern: String, _ text: String) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
}

private let otpWords = #"(otp|one[- ]time|verification code|passcode|code is|security code)"#

func detectSensitive(_ text: String) -> Sensitive? {
    let upper = text.uppercased()
    for m in matches(#"\b[2-9]\d{3}\s?\d{4}\s?\d{4}\b"#, text) where verhoeffValid(m.filter(\.isNumber)) { return .aadhaar }
    if has(#"\b[A-Z]{5}[0-9]{4}[A-Z]\b"#, upper, caseInsensitive: false) { return .pan }
    let cardWords = has(#"(card|visa|master ?card|rupay|amex|debit|credit|valid thru|valid till|expiry|exp\.? date|cvv)"#, text)
    for m in matches(#"\b(?:\d[ -]?){12,18}\d\b"#, text) where luhnValid(m.filter(\.isNumber)) {
        let grouped = m.range(of: #"^\d{4}[ -]\d{4}[ -]\d{4}[ -]\d{4}$"#, options: .regularExpression) != nil
        if grouped || cardWords { return .card }
    }
    if upper.contains("P<") || (has("passport", text) && has(#"\b[A-Z][0-9]{7}\b"#, upper, caseInsensitive: false)) { return .passport }
    if has(#"\bIFSC\b"#, upper, caseInsensitive: false) || has(#"(pay\s+.{0,40}or bearer|a/c\s*no|account\s*no)"#, text) { return .bank }
    return nil
}

/// Deterministic text signals from OCR text and barcode payloads.
public func scanText(_ text: String, barcodes: [String]) -> RuleHits {
    var h = RuleHits()
    h.otp = has(otpWords + #"[^\d]{0,40}\b\d{4,8}\b"#, text) || has(#"\b\d{4,8}\b[^\d]{0,40}"# + otpWords, text)
    h.payment = has(#"(\bupi\b|\butr\b|₹|\brs\.?\s?\d|\binr\b|\bpaid\b|\breceived\b|transaction id|debited|credited)"#, text)
    h.ticketOrQR = !barcodes.isEmpty || has(#"(boarding pass|\bpnr\b|\bseat\b|\bgate\b|ticket|booking id)"#, text)
    h.greeting = has(#"(good morning|good night|good evening|shubh|suprabhat|सुप्रभात|शुभ|wishing you|happy (diwali|holi|new year|navratri|dussehra|eid|christmas|independence day|republic day|raksha bandhan|janmashtami|pongal|onam|lohri|makar sankranti|ganesh chaturthi))"#, text)
    if h.ticketOrQR, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
        h.eventDate = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date
    }
    h.sensitive = detectSensitive(text)
    if h.sensitive != nil { h.docType = .id }
    else if has(#"(receipt|invoice|\bgst\b|total)"#, text) { h.docType = .receipt }
    else if has(#"(\bbill\b|due date|amount due)"#, text) { h.docType = .bill }
    else if has(#"(boarding pass|ticket|\bpnr\b)"#, text) { h.docType = .ticket }
    else if has(#"(booking|reservation|check-in)"#, text) { h.docType = .booking }
    return h
}
