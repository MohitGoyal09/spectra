import Foundation
import TidyCore

struct SavedRule: Codable, Identifiable, Sendable {
    var id = UUID()
    var sentence: String
    var spec: RuleSpec
    var albumID: String?
    var created = Date()
    /// Photos the user took out of this album ("Not this photo"); never added back.
    var excluded: [String]?
}

/// Saved info that outlives its screenshot (kept after the screenshot is deleted).
struct ArchivedInfo: Codable, Identifiable, Sendable {
    var id: String          // the original photo id
    var info: SavedInfo
    var date: Date
}

/// Smart-album rules and archived saved info, stored on this iPhone.
@MainActor final class RuleStore {
    private(set) var rules: [SavedRule] = []
    private(set) var archive: [ArchivedInfo] = []
    private let rulesURL: URL, archiveURL: URL

    init(directory: URL) {
        rulesURL = directory.appendingPathComponent("rules.json")
        archiveURL = directory.appendingPathComponent("saved-info.json")
        rules = (try? JSONDecoder().decode([SavedRule].self, from: Data(contentsOf: rulesURL))) ?? []
        archive = (try? JSONDecoder().decode([ArchivedInfo].self, from: Data(contentsOf: archiveURL))) ?? []
    }

    func add(_ r: SavedRule) { rules.insert(r, at: 0); save() }
    func remove(_ id: UUID) { rules.removeAll { $0.id == id }; save() }
    func exclude(_ ids: [String], from rule: UUID) {
        guard let i = rules.firstIndex(where: { $0.id == rule }) else { return }
        rules[i].excluded = Array(Set((rules[i].excluded ?? []) + ids)); save()
    }
    func setAlbum(_ id: UUID, _ albumID: String?) { if let i = rules.firstIndex(where: { $0.id == id }) { rules[i].albumID = albumID; save() } }
    func archive(_ items: [ArchivedInfo]) {
        let known = Set(archive.map(\.id))
        archive.insert(contentsOf: items.filter { !known.contains($0.id) }, at: 0)
        save()
    }
    func removeArchived(_ id: String) { archive.removeAll { $0.id == id }; save() }

    private func save() {
        try? JSONEncoder().encode(rules).write(to: rulesURL, options: .atomic)
        try? JSONEncoder().encode(archive).write(to: archiveURL, options: .atomic)
    }
}
