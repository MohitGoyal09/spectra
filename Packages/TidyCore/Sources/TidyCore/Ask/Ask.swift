import Foundation

private let questionWords: Set<String> = ["what", "whats", "what's", "when", "where", "which", "who", "how", "is", "did", "do", "does", "find", "show"]

/// A query is a question when it ends with "?" or starts with a question word ("what's my wifi password").
public func isQuestion(_ q: String) -> Bool {
    let t = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if t.hasSuffix("?") { return true }
    guard let first = t.split(separator: " ").first, t.split(separator: " ").count >= 3 else { return false }
    return questionWords.contains(String(first).replacingOccurrences(of: "\u{2019}", with: "'"))
}

private let stopWords: Set<String> = [
    "a", "an", "the", "is", "are", "was", "were", "be", "my", "me", "i", "of", "for", "to", "in", "on", "at", "and", "or",
    "what", "whats", "when", "where", "which", "who", "how", "much", "many", "did", "do", "does", "i'm", "it", "its", "that",
    "this", "from", "with", "find", "show", "tell", "give", "photo", "picture", "image", "screenshot", "there", "any", "s",
]

/// Words that carry meaning: lowercased, hyphens joined ("wi-fi" → "wifi"), stop words dropped.
func contentWords(_ text: String) -> [String] {
    text.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "\u{2019}", with: "'")
        .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
        .map { String($0).replacingOccurrences(of: "'s", with: "") }
        .filter { !stopWords.contains($0) && $0.count > 1 }
}

/// On-device retrieval for Ask: scores each text by the question words it holds, rarer words weighing more (IDF).
/// Returns ids of the best texts, best first; nothing when no content word matches.
public func retrieve(_ question: String, from docs: [(id: String, text: String)], limit: Int) -> [String] {
    let words = Array(Set(contentWords(question)))
    guard !words.isEmpty, !docs.isEmpty else { return [] }
    let hay = docs.map { $0.text.lowercased().replacingOccurrences(of: "-", with: "") }
    let n = Double(docs.count)
    let has = hay.map { h in Set(words.filter { textHas(h, $0) }) }      // whole words only ("lens" ✗ "challenges")
    let idf = words.map { w in log((n + 1) / (Double(has.filter { $0.contains(w) }.count) + 1)) + 1 }
    let scored = has.enumerated().map { i, h in
        (i, zip(words, idf).reduce(0.0) { $0 + (h.contains($1.0) ? $1.1 : 0) })
    }
    return scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(limit).map { docs[$0.0].id }
}
