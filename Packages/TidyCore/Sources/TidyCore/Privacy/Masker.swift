import Foundation

private let maskRules: [(pattern: String, token: String)] = [
    (#"[\p{L}\p{M}\p{Nd}._%+-]+@[\p{L}\p{Nd}.-]+\.\p{L}{2,}"#, "[EMAIL]"),
    (#"[\p{L}\p{M}\p{Nd}._-]{2,}@\p{L}{2,}\b"#, "[UPI]"),
    (#"(\+91[\s-]?)?\b[6-9]\d{4}[\s-]?\d{5}\b"#, "[PHONE]"),
    // Any 4+ digits (any script) joined by spaces or common separators, so "4111.1111…", "(022) 1234/5678" and "४८२९१३" are caught.
    (#"\p{Nd}(?:[\s.\-/(),:]*\p{Nd}){3,}"#, "[NUM]"),
]

/// Masks emails, UPI IDs, phone numbers and any run of 4+ digits before text leaves the device.
public func mask(_ text: String) -> String {
    maskRules.reduce(text) { $0.replacingOccurrences(of: $1.pattern, with: $1.token, options: .regularExpression) }
}
