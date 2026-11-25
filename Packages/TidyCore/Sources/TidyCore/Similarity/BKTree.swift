/// BK-tree over 64-bit hashes with Hamming distance, for cheap near-duplicate candidates.
public final class BKTree {
    private final class Node {
        let hash: UInt64
        var ids: [String]
        var children: [Int: Node] = [:]
        init(_ hash: UInt64, _ id: String) { self.hash = hash; ids = [id] }
    }
    private var root: Node?
    public init() {}

    public func insert(_ h: UInt64, id: String) {
        guard var node = root else { root = Node(h, id); return }
        while true {
            let d = hamming(h, node.hash)
            if d == 0 { node.ids.append(id); return }
            guard let next = node.children[d] else { node.children[d] = Node(h, id); return }
            node = next
        }
    }

    public func query(_ h: UInt64, maxDistance: Int) -> [String] {
        guard let root else { return [] }
        var out: [String] = []
        var stack = [root]
        while let node = stack.popLast() {
            let d = hamming(h, node.hash)
            if d <= maxDistance { out += node.ids }
            for (k, child) in node.children where k >= d - maxDistance && k <= d + maxDistance { stack.append(child) }
        }
        return out
    }
}
