import Foundation

/// What the model may contribute. It never carries a verdict.
public struct ModelNote: Sendable, Equatable {
    public var id: String
    public var kind: Kind?
    public var title: String?
    public var savedInfo: SavedInfo?
    public init(id: String, kind: Kind?, title: String?, savedInfo: SavedInfo? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.savedInfo = savedInfo
    }
}

let genericReasons: Set<String> = ["Screenshot", "Saved image", "Image from WhatsApp", "Camera photo", "Video", "Recent OTP"]

func copiesInput(_ title: String, _ ocr: String, run: Int = 6) -> Bool {
    let t = title.lowercased().split(separator: " ")
    let o = " " + ocr.lowercased().split(separator: " ").joined(separator: " ") + " "
    guard t.count >= run else { return false }
    return (0...(t.count - run)).contains { o.contains(" " + t[$0..<($0 + run)].joined(separator: " ") + " ") }
}

func looksLikeEcho(_ title: String) -> Bool {
    let l = title.lowercased()
    return ["words", "photo shows", "input text", "under 10"].contains { l.contains($0) }
}

/// Rules own the verdict. The model can refine a low-information kind, replace a generic reason with a short title,
/// and add saved info for non-sensitive items. Copied or echoed titles fall back to the top scene label.
public func merge(rule: Verdict, note: ModelNote?, ocrText: String, topLabel: String?) -> Verdict {
    guard let note else { return rule }
    var out = rule
    if rule.sensitive == nil {
        if let k = note.kind, [.document, .forward].contains(k), rule.kind == .download { out.kind = k }
        if let info = note.savedInfo, info.fields.values.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            out.savedInfo = info
        }
    }
    if genericReasons.contains(rule.reason), rule.sensitive == nil {
        if let t = note.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
           !copiesInput(t, ocrText), !looksLikeEcho(t), t.count <= 60 {
            out.reason = t
            out.source = .onDevice
        } else if let label = topLabel {
            out.reason = label.replacingOccurrences(of: "_", with: " ").capitalized(with: Locale(identifier: "en_US_POSIX"))
        }
    }
    return out
}

/// Whether a photo is worth a model call: only generic reasons, and never sensitive items (they never reach any model).
public func wantsNote(_ v: Verdict) -> Bool { v.sensitive == nil && genericReasons.contains(v.reason) }
