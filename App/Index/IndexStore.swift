import Foundation
import TidyCore

struct IndexedItem: Codable, Sendable {
    var record: PhotoRecord
    var verdict: Verdict
    var dHash: UInt64
    var faceQuality: Float
    var blurScore: Float?
    /// Best copy's id for every member of a duplicate group (the best copy points at itself).
    var dupGroup: String?
    /// The user chose to keep this item; rules never override it.
    var userKept: Bool?
    /// Vision saw real pixels. False for photos that couldn't be read (iCloud-only); nil in indexes made before this field.
    var hasImage: Bool?

    /// Whether content checks (duplicates) can trust this item; old entries without pixels have an empty hash and no labels.
    var readable: Bool { hasImage ?? !(dHash == 0 && record.labels.isEmpty) }
    var bucket: Bucket { TidyCore.bucket(for: verdict, record: record) }
}

/// On-device index: items as one JSON file, feature prints as one small file each (only needed for duplicate checks).
/// Limit: whole-file JSON rewrite; move to SQLite if libraries above ~50k items feel slow to save.
@MainActor final class IndexStore {
    private(set) var items: [String: IndexedItem] = [:]
    private let dir: URL
    private var indexURL: URL { dir.appendingPathComponent("index.json") }
    private var printsDir: URL { dir.appendingPathComponent("prints", isDirectory: true) }

    init(directory: URL) {
        dir = directory
        try? FileManager.default.createDirectory(at: printsDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let decoded = try? JSONDecoder().decode([String: IndexedItem].self, from: data) {
            items = decoded
        }
    }

    static func appDefault() -> IndexStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(FilmScope.dataFolder, isDirectory: true)
        return IndexStore(directory: base)
    }

    func put(_ item: IndexedItem, featurePrint: Data?) {
        items[item.record.id] = item
        if let fp = featurePrint { try? fp.write(to: printURL(item.record.id)) }
    }

    func update(_ id: String, _ edit: (inout IndexedItem) -> Void) { if var i = items[id] { edit(&i); items[id] = i } }

    func remove(ids: [String]) {
        for id in ids { items[id] = nil; try? FileManager.default.removeItem(at: printURL(id)) }
    }

    func featurePrint(_ id: String) -> Data? { try? Data(contentsOf: printURL(id)) }

    /// Encodes and writes off the main thread so large libraries never block the UI.
    func save() {
        let snapshot = items, url = indexURL
        Task.detached(priority: .utility) { try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic) }
    }

    nonisolated static func printURL(in dir: URL, id: String) -> URL {
        dir.appendingPathComponent("prints", isDirectory: true).appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + ".fp")
    }
    var directory: URL { dir }

    func reset() {
        items = [:]
        try? FileManager.default.removeItem(at: printsDir)
        try? FileManager.default.createDirectory(at: printsDir, withIntermediateDirectories: true)
        save()
    }

    private func printURL(_ id: String) -> URL {
        printsDir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + ".fp")
    }
}
