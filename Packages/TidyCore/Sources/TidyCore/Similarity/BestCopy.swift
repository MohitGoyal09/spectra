public struct CopyQuality: Sendable {
    public var sharpness: Float
    public var faceQuality: Float
    public var pixels: Int
    public init(sharpness: Float, faceQuality: Float, pixels: Int) { self.sharpness = sharpness; self.faceQuality = faceQuality; self.pixels = pixels }
}

/// Index of the copy to keep: 0.4·sharpness + 0.3·face quality + 0.3·relative resolution.
public func bestCopyIndex(_ copies: [CopyQuality]) -> Int {
    let maxPixels = Float(copies.map(\.pixels).max() ?? 1)
    let scores = copies.map { 0.4 * $0.sharpness + 0.3 * $0.faceQuality + 0.3 * Float($0.pixels) / max(maxPixels, 1) }
    return scores.indices.max { scores[$0] < scores[$1] } ?? 0
}

/// Union-find grouping of ids whose pairwise distance is within maxDistance. Groups of one are dropped.
/// Limit: O(n²) pairs; callers pass BK-tree candidate sets, not the whole library.
public func groupDuplicates(ids: [String], distance: (String, String) -> Float, maxDistance: Float) -> [[String]] {
    var parent = Array(ids.indices)
    func find(_ i: Int) -> Int { parent[i] == i ? i : { parent[i] = find(parent[i]); return parent[i] }() }
    for i in ids.indices { for j in ids.indices where j > i && distance(ids[i], ids[j]) <= maxDistance { parent[find(j)] = find(i) } }
    var groups: [Int: [String]] = [:]
    for i in ids.indices { groups[find(i), default: []].append(ids[i]) }
    return groups.values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }
}
