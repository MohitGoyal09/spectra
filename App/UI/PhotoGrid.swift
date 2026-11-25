import SwiftUI
import Photos

/// Apple-Photos-style grid: edge to edge, 1.5 pt gaps, pinch to change density, month headers, tap to open, select mode.
struct PhotoGrid: View {
    let ids: [String]
    var sectioned = true
    /// Show each item's file size on its tile (when sorting by size).
    var showSizes = false
    @Binding var selection: Set<String>?
    var zoomNamespace: Namespace.ID? = nil
    var onOpen: (Int) -> Void
    @AppStorage("gridColumnsV2") private var columns = 3   // new key: a one-column setting saved by the UI tests is dropped
    @State private var pinch: CGFloat = 1
    @State private var sections: [MonthSection] = []
    private static let steps = [3, 5, 9]   // always a grid, like Photos

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 1.5), count: columns)
        LazyVGrid(columns: cols, spacing: 1.5, pinnedViews: sectioned ? [.sectionHeaders] : []) {
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.items, id: \.id) { item in cell(item.id, index: item.index) }
                } header: {
                    if sectioned {
                        Text(section.title).font(columns >= 9 ? .largeTitle.weight(.bold) : .headline).foregroundStyle(Palette.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                            .background(.bar)
                    }
                }
            }
        }
        .scaleEffect(pinch, anchor: .center)
        .gesture(MagnifyGesture()
            .onChanged { pinch = min(max($0.magnification, 0.85), 1.15) }
            .onEnded { v in
                let i = Self.steps.firstIndex(of: columns) ?? 0
                if v.magnification > 1.1, i > 0 { columns = Self.steps[i - 1] }
                if v.magnification < 0.9, i < Self.steps.count - 1 { columns = Self.steps[i + 1] }
                withAnimation(Motion.snappy) { pinch = 1 }
            })
        .animation(Motion.smooth, value: columns)
        .sensoryFeedback(.selection, trigger: columns)
        .sensoryFeedback(.selection, trigger: selection?.count)
        .task(id: "\(ids.count)-\(ids.first ?? "")-\(ids.last ?? "")-\(columns >= 9)") { sections = await Self.group(ids, sectioned: sectioned, byYear: columns >= 9) }
    }

    private struct Entry: Sendable { let id: String; let index: Int }
    private struct MonthSection: Sendable { let title: String; let items: [Entry] }

    /// Groups ids into month sections using PhotoKit creation dates (ids are already newest first). Runs off the main thread.
    private static func group(_ ids: [String], sectioned: Bool, byYear: Bool) async -> [MonthSection] {
        guard sectioned else { return [MonthSection(title: "", items: ids.enumerated().map { Entry(id: $1, index: $0) })] }
        return await Task.detached(priority: .userInitiated) {
            var dates: [String: Date] = [:]
            PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { a, _, _ in dates[a.localIdentifier] = a.creationDate }
            let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate(byYear ? "yyyy" : "MMMM yyyy")
            var out: [MonthSection] = []
            var current: (title: String, items: [Entry])?
            for (i, id) in ids.enumerated() {
                let title = dates[id].map(f.string(from:)) ?? "Undated"
                if current?.title == title { current?.items.append(Entry(id: id, index: i)) }
                else { if let c = current { out.append(MonthSection(title: c.title, items: c.items)) }; current = (title, [Entry(id: id, index: i)]) }
            }
            if let c = current { out.append(MonthSection(title: c.title, items: c.items)) }
            return out
        }.value
    }

    private func cell(_ id: String, index: Int) -> some View {
        let selected = selection?.contains(id) == true
        return Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay(AssetThumbnail(id: id, side: columns >= 5 ? 70 : 130))
            .clipped()
            .overlay(alignment: .bottomTrailing) { VideoBadge(id: id) }
            .overlay(alignment: .bottomLeading) { if showSizes { SizeBadge(id: id) } }
            .overlay(alignment: .bottomTrailing) {
                if selection != nil {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .contentTransition(.symbolEffect(.replace))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, selected ? Color.accentColor : .black.opacity(0.25))
                        .font(.title3).padding(5)
                }
            }
            .overlay { if selected { Color.white.opacity(0.18) } }
            .scaleEffect(selected ? 0.92 : 1)
            .animation(Motion.snappy, value: selected)
            .modifier(ZoomSource(id: id, namespace: zoomNamespace))
            .contentShape(Rectangle())
            .onTapGesture {
                if var s = selection { if s.contains(id) { s.remove(id) } else { s.insert(id) }; selection = s } else { onOpen(index) }
            }
            .accessibilityLabel(selection == nil ? "Photo" : (selected ? "Selected photo" : "Photo, not selected"))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Bottom bar shown while selecting: share, more (favourite, album, hide), delete.
struct SelectionBar: View {
    @Binding var selection: Set<String>?
    /// Smart albums only: take the photos out for good.
    var onNotInAlbum: (([String]) async -> Void)? = nil
    var onDone: () -> Void
    @State private var preparing = false
    @State private var picking = false

    var body: some View {
        let ids = Array(selection ?? [])
        HStack {
            Button { Task { preparing = true; _ = await Sharing.share(ids); preparing = false } } label: {
                if preparing { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
            }
            .disabled(ids.isEmpty || preparing).accessibilityLabel("Share")
            Spacer()
            Text(ids.isEmpty ? "Select items" : "\(ids.count) selected").font(.headline).contentTransition(.numericText())
            Spacer()
            Menu {
                Button { Task { for id in ids { try? await Gallery.setFavorite(id, true) }; finish() } } label: { Label("Favourite", systemImage: "heart") }
                Button { picking = true } label: { Label("Add to Album", systemImage: "rectangle.stack.badge.plus") }
                Button { Task { if await Gallery.hide(ids) { finish() } } } label: { Label("Hide", systemImage: "eye.slash") }
                if let onNotInAlbum {
                    Button(role: .destructive) { Task { await onNotInAlbum(ids); finish() } } label: { Label("Not in this album", systemImage: "rectangle.stack.badge.minus") }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .disabled(ids.isEmpty).accessibilityLabel("More")
            Button(role: .destructive) {
                Task { if await Gallery.delete(ids) { finish() } }
            } label: { Image(systemName: "trash") }
                .disabled(ids.isEmpty).accessibilityLabel("Delete")
                .padding(.leading, Space.m)
        }
        .font(.title3)
        .padding(.horizontal, Space.xl).padding(.vertical, Space.m)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, Space.l)
        .sheet(isPresented: $picking) { AlbumPickerSheet(ids: ids) { if $0 != nil { finish() } } }
    }

    private func finish() { selection = nil; onDone() }
}

/// Marks a thumbnail as the source of the Photos-style zoom into the viewer.
struct ZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if let namespace { content.matchedTransitionSource(id: id, in: namespace) } else { content }
    }
}

/// File size on a tile ("84 MB"), from the index.
struct SizeBadge: View {
    let id: String
    @Environment(AppModel.self) private var model
    var body: some View {
        if let b = model.store.items[id]?.record.fileBytes, b > 0 {
            Text(gbText(b)).font(.caption2.weight(.bold)).monospacedDigit()
                .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule()).padding(4)
        }
    }
}
