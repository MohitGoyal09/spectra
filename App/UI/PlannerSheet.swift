import SwiftUI
import TidyCore

/// "Get me X GB": the safest set that reaches a target, least risky first, then slide to free.
struct PlannerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var targetGB: Double
    init(initialGB: Double = 1) { _targetGB = State(initialValue: initialGB) }
    @State private var unticked: Set<String> = []
    @State private var result: ResultSummary?
    private let presets: [Double] = [0.5, 1, 2, 5, 10]
    private static let tierNames = [1: "Exact copies", 2: "Expired screenshots", 3: "Forwards", 4: "Screen recordings", 5: "Big videos", 6: "Blurry shots", 7: "Similar photos"]

    var body: some View {
        let plan = model.plan(target: Int64(targetGB * 1_000_000_000))
        let chosen = plan.items.filter { !unticked.contains($0.id) }
        let bytes = chosen.map(\.bytes).reduce(0, +)
        NavigationStack {
            List {
                Section {
                    Picker("Target", selection: $targetGB) {
                        ForEach(presets, id: \.self) { Text($0 < 1 ? "500 MB" : "\(Int($0)) GB").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(plan.metTarget ? "\(gbText(bytes)) ready to free" : "I can only free \(gbText(plan.freedBytes)) safely")
                            .font(.title3.weight(.semibold))
                        ProgressView(value: min(Double(bytes) / (targetGB * 1e9), 1)).tint(Palette.junk)
                        Text("Least risky first. Real photos, favourites and IDs are never included.").font(.footnote).foregroundStyle(Palette.secondary)
                    }
                }
                ForEach(Dictionary(grouping: plan.items, by: \.tier).sorted { $0.key < $1.key }, id: \.key) { tier, items in
                    Section("\(Self.tierNames[tier] ?? "Other") · \(gbText(items.map(\.bytes).reduce(0, +)))") {
                        ForEach(items, id: \.id) { item in
                            HStack(spacing: Space.m) {
                                AssetThumbnail(id: item.id, side: 60).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading) {
                                    Text(item.reason).font(.subheadline).lineLimit(2)
                                    Text(gbText(item.bytes)).font(.caption).foregroundStyle(Palette.secondary)
                                }
                                Spacer()
                                Image(systemName: unticked.contains(item.id) ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(unticked.contains(item.id) ? Palette.secondary : Palette.junk).font(.title3)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { if unticked.contains(item.id) { unticked.remove(item.id) } else { unticked.insert(item.id) } }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityValue(unticked.contains(item.id) ? "Not included" : "Included")
                        }
                    }
                }
            }
            .navigationTitle("Get me space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if !chosen.isEmpty {
                    SlideToConfirm(label: "Slide to free \(gbText(bytes))") {
                        let ids = chosen.map(\.id)
                        if await Gallery.delete(ids) {
                            await model.forget(ids)
                            result = ResultSummary(freedBytes: bytes, deleted: ids.count, locked: 0)
                        }
                    }
                    .padding(Space.l)
                    .background(.bar)
                }
            }
            .fullScreenCover(item: $result) { ResultView(summary: $0) { dismiss() } }
        }
    }
}
