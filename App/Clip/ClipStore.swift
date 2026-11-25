import Foundation
import TidyCore

/// Picture-search vectors for every indexed photo, kept on this iPhone: ids as JSON plus one Float16 matrix (1 KB per photo).
@MainActor final class ClipStore {
    private(set) var vectors: [String: [Float]] = [:]
    /// Bumps on every change so cached query results can be dropped.
    private(set) var revision = 0
    private let idsURL: URL, dataURL: URL

    init(directory: URL) {
        idsURL = directory.appendingPathComponent("clip-ids.json")
        dataURL = directory.appendingPathComponent("clip-vectors.bin")
        guard let ids = try? JSONDecoder().decode([String].self, from: Data(contentsOf: idsURL)),
              let data = try? Data(contentsOf: dataURL), data.count == ids.count * ClipModel.dimensions * 2 else { return }
        let halves = data.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        for (i, id) in ids.enumerated() {
            vectors[id] = halves[(i * ClipModel.dimensions)..<((i + 1) * ClipModel.dimensions)].map(Float.init)
        }
    }

    func set(_ id: String, _ v: [Float]) { vectors[id] = v; revision += 1 }
    func remove(_ ids: [String]) { for id in ids { vectors[id] = nil }; revision += 1 }

    func save() {
        let ids = Array(vectors.keys)
        let halves = ids.flatMap { vectors[$0]!.map(Float16.init) }
        let (idsURL, dataURL) = (idsURL, dataURL)
        Task.detached(priority: .utility) {
            try? JSONEncoder().encode(ids).write(to: idsURL, options: .atomic)
            try? halves.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: dataURL, options: .atomic)
        }
    }

    /// Photos that stand out for this query, with their similarity. Nil when picture search is unavailable.
    func search(_ query: String) -> [String: Float]? {
        guard let model = ClipModel.ready, !vectors.isEmpty, let q = model.embed(text: "a photo of \(query)") else { return nil }
        let ids = Array(vectors.keys)
        let sims = ClipModel.similarities(q, ids.map { vectors[$0]! })
        return Dictionary(uniqueKeysWithValues: clipPick(sims).map { (ids[$0], sims[$0]) })
    }
}
