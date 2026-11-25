import SwiftUI
import TidyCore

/// Clean Up tab: clutter gathered into Apple-Photos-style collections, grouped by how safe they are to clear.
struct CleanUpView: View {
    @Environment(AppModel.self) private var model
    @State private var open: Bucket?
    @State private var planning = false
    private let columns = [GridItem(.flexible(), spacing: Space.l), GridItem(.flexible(), spacing: Space.l)]
    private let sections: [(String, String, [Bucket])] = [
        ("Safe to clear", "Copies, forwards and expired codes.", [.duplicates, .forwards, .expiredScreenshots]),
        ("Worth a look", "Large or unclear items. You decide.", [.bigVideos, .memes, .otherScreenshots, .blurry, .aiMade, .memesDownloads]),
        ("From other people", "Photos and documents people sent you.", [.receivedPhotos, .documents]),
        ("Kept for you", "Saved details and locked documents.", [.usefulScreenshots, .idsCards]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    StorageBar(storage: model.storage, segments: model.librarySegments, freeable: model.freeableBytes, review: model.reviewBytes)
                    if model.hasIndex {
                        Button { planning = true } label: {
                            Label("Get me space", systemImage: "arrow.up.bin").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    ForEach(sections, id: \.0) { title, subtitle, buckets in
                        let present = buckets.filter { model.count($0) > 0 }
                        if !present.isEmpty {
                            VStack(alignment: .leading, spacing: Space.m) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                                    Text(subtitle).font(.subheadline).foregroundStyle(Palette.secondary)
                                }
                                LazyVGrid(columns: columns, spacing: Space.xl) {
                                    ForEach(present, id: \.self) { b in
                                        Button { open = b } label: {
                                            CollectionCard(bucket: b, coverIDs: model.items(in: b).prefix(4).map(\.record.id),
                                                           count: model.count(b), bytes: model.bytes(b),
                                                           glow: model.scanner.titling && model.items(in: b).contains { $0.record.id == model.scanner.titlingID } ? model.glow : .idle)
                                        }
                                        .buttonStyle(PressScaleStyle())
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.xxl)
            }
            .background(Palette.grouped)
            .navigationTitle("Clean Up")
            .toolbar { ToolbarItem(placement: .topBarLeading) { AIStatusDot() } }
            .navigationDestination(item: $open) { b in
                switch b {
                case .duplicates: DuplicatesView()
                case .usefulScreenshots: SavedInfoView()
                default: BucketGridView(bucket: b)
                }
            }
            .sheet(isPresented: $planning, onDismiss: { model.pendingPlanGB = nil }) { PlannerSheet(initialGB: model.pendingPlanGB ?? 1) }
            .onChange(of: model.pendingPlanGB, initial: true) { _, gb in if gb != nil { planning = true } }
            .overlay {
                if !model.hasIndex {
                    ContentUnavailableView("Nothing sorted yet", systemImage: "sparkles",
                                           description: Text("Scan from the Library tab. Sorting runs on this iPhone."))
                }
            }
        }
    }
}
