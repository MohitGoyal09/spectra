import SwiftUI
import TidyCore

/// A collection, shown as an edge-to-edge grid like an Apple Photos album.
struct BucketGridView: View {
    let bucket: Bucket
    @Environment(AppModel.self) private var model
    @State private var viewer: ViewerContext?

    @State private var selection: Set<String>?
    @Namespace private var zoom
    @State private var reviewing = false
    @State private var compressing: Int?          // videos done so far while compressing
    @State private var toast: Toast?

    var body: some View {
        let ids = model.items(in: bucket).map(\.record.id)
        ScrollView {
            PhotoGrid(ids: ids, sectioned: false, selection: $selection, zoomNamespace: zoom) { viewer = ViewerContext(ids: ids, start: $0) }
        }
        .background(Palette.background)
        .navigationTitle(bucket.title)
        .navigationSubtitle("\(ids.count.formatted()) items · \(gbText(model.bytes(bucket)))")
        .toolbar {
            if selection == nil, !ids.isEmpty, bucket != .realPhotos {
                Button { reviewing = true } label: { Label("Review", systemImage: "rectangle.stack") }
            }
            Button(selection == nil ? "Select" : "Cancel") { selection = selection == nil ? [] : nil }
        }
        .safeAreaInset(edge: .top) {
            if bucket == .bigVideos, selection == nil, !ids.isEmpty { compressBanner(ids) }
        }
        .toast($toast)
        .fullScreenCover(isPresented: $reviewing) { ReviewDeck(ids: ids) }
        .overlay(alignment: .bottom) {
            if selection != nil {
                SelectionBar(selection: $selection) { Task { await model.loadLibrary() } }.padding(.bottom, Space.s)
            }
        }
        .fullScreenCover(item: $viewer) { ctx in
            PhotoViewer(context: ctx).navigationTransition(.zoom(sourceID: ctx.ids[ctx.start], in: zoom))
        }
    }
}

private extension BucketGridView {
    /// Keep every video, just smaller: HEVC 1080p made on this iPhone.
    func compressBanner(_ ids: [String]) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: "rectangle.compress.vertical").font(.title2).foregroundStyle(Palette.keep)
            VStack(alignment: .leading, spacing: 2) {
                Text(compressing.map { "Compressing \($0 + 1 > ids.count ? ids.count : $0 + 1) of \(ids.count)…" } ?? "Keep them, just smaller")
                    .font(.subheadline.weight(.semibold)).contentTransition(.numericText())
                Text("Re-saves as HD (1080p) on this iPhone. Originals go to Recently Deleted.")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 0)
            if compressing != nil { ProgressView() } else {
                Button("Compress") { Task { await compress(ids) } }.buttonStyle(.glassProminent).font(.subheadline.weight(.semibold))
            }
        }
        .padding(Space.m)
        .background(.bar, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, Space.l).padding(.bottom, Space.s)
    }

    func compress(_ ids: [String]) async {
        compressing = 0
        let r = await VideoCompressor.compress(ids) { n in Task { @MainActor in compressing = n } }
        compressing = nil
        toast = r.compressed > 0 ? Toast(symbol: "checkmark.circle.fill", text: "Freed \(gbText(r.saved)) · \(r.compressed) video\(r.compressed == 1 ? "" : "s") kept in HD", tint: Palette.keep)
              : r.declined ? Toast(symbol: "xmark.circle", text: "Nothing changed")
              : r.alreadyCompact > 0 ? Toast(symbol: "checkmark.seal", text: "Already compact")
              : Toast(symbol: "exclamationmark.triangle", text: "Couldn't compress", tint: Palette.junk)
        if r.compressed > 0 { await model.forget(ids) }
    }
}

extension IndexedItem: Identifiable { var id: String { record.id } }
