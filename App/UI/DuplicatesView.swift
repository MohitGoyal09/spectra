import SwiftUI
import TidyCore

/// Like Photos' Duplicates: each group side by side, the best copy marked Keep, Merge removes the rest.
struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    @State private var result: ResultSummary?

    private var groups: [[IndexedItem]] {
        _ = model.scanner.revision
        let members = model.store.items.values.filter { $0.dupGroup != nil }
        let grouped: [String: [IndexedItem]] = Dictionary(grouping: members) { $0.dupGroup ?? "" }
        var out: [[IndexedItem]] = []
        for (_, g) in grouped where g.count > 1 && g.contains(where: { $0.verdict.junkType == .duplicate }) {
            out.append(g.sorted(by: Self.bestFirst))
        }
        return out.sorted { Self.bytes($0) > Self.bytes($1) }
    }

    private static func bytes(_ g: [IndexedItem]) -> Int64 { g.map(\.record.fileBytes).reduce(0, +) }

    private static func bestFirst(_ a: IndexedItem, _ b: IndexedItem) -> Bool {
        let aBest = a.record.id == a.dupGroup, bBest = b.record.id == b.dupGroup
        if aBest != bBest { return aBest }
        return a.record.createdAt < b.record.createdAt
    }

    var body: some View {
        let groups = groups
        List {
            if groups.count > 1 {
                Button { Task { await merge(groups.flatMap { Array($0.dropFirst()) }) } } label: {
                    Label("Merge all \(groups.count) groups", systemImage: "square.on.square.dashed").font(.headline)
                }
            }
            ForEach(groups, id: \.first!.record.id) { g in
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s) {
                            ForEach(g, id: \.record.id) { item in
                                let best = item.record.id == item.dupGroup
                                AssetThumbnail(id: item.record.id, side: 140)
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                                    .overlay(alignment: .topLeading) {
                                        if best {
                                            Text("Keep").font(.caption.weight(.bold)).foregroundStyle(.white)
                                                .padding(.horizontal, 8).padding(.vertical, 3).background(Color(red: 0.08, green: 0.45, blue: 0.2), in: Capsule()).padding(6)
                                        }
                                    }
                                    .accessibilityLabel(best ? "Best copy, kept" : "Copy")
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: Space.s, leading: Space.l, bottom: Space.s, trailing: Space.l))
                    Button("Merge · free \(gbText(g.dropFirst().map(\.record.fileBytes).reduce(0, +)))") {
                        Task { await merge(Array(g.dropFirst())) }
                    }
                } header: {
                    Text("\(g.count) copies · \(g.first!.verdict.reason == "Camera photo" ? "Photos" : g.first!.bucket.title)")
                }
            }
        }
        .navigationTitle("Duplicates")
        .overlay { if groups.isEmpty { ContentUnavailableView("No duplicates", systemImage: "checkmark.circle", description: Text("Every photo here is one of a kind.")) } }
        .fullScreenCover(item: $result) { ResultView(summary: $0) { result = nil } }
    }

    private func merge(_ copies: [IndexedItem]) async {
        let ids = copies.map(\.record.id)
        let bytes = copies.map(\.record.fileBytes).reduce(0, +)
        if await Gallery.delete(ids) {
            await model.forget(ids)
            result = ResultSummary(freedBytes: bytes, deleted: ids.count, locked: 0)
        }
    }
}
