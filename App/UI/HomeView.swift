import SwiftUI
import TidyCore

/// Library tab, modelled on Apple Photos (iOS 26): large title with a count, Filter and Select,
/// the user's photos edge to edge by month, and what can go just under the title.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showScan = false
    @AppStorage("gridColumnsV2") private var gridColumns = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewer: ViewerContext?
    @State private var selection: Set<String>?
    @Namespace private var zoom
    @AppStorage("libraryFilter") private var filter: LibraryFilter = .all
    /// "Sort by size": the most requested thing Apple Photos can't do.
    @AppStorage("librarySortBySize") private var sortBySize = false
    /// Albums as folders: photos already filed in an album stay out of the Library.
    @AppStorage("libraryHidesAlbumPhotos") private var hideAlbumPhotos = false

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "All Items", real = "Real Photos", videos = "Videos", screenshots = "Screenshots", favorites = "Favorites"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .all: "photo.on.rectangle"
            case .real: "camera"
            case .videos: "video"
            case .screenshots: "camera.viewfinder"
            case .favorites: "heart"
            }
        }
    }

    @State private var ids: [String] = []

    private func filtered() async -> [String] {
        var out = basic()
        if hideAlbumPhotos {
            let filed = await Gallery.idsInUserAlbums()
            out = out.filter { !filed.contains($0) }
        }
        guard sortBySize else { return out }
        let sizes = await sizes(for: out)
        return out.sorted { (sizes[$0] ?? 0) > (sizes[$1] ?? 0) }
    }

    /// Sizes from the index; anything not indexed yet is read from PhotoKit off the main thread.
    private func sizes(for ids: [String]) async -> [String: Int64] {
        var known: [String: Int64] = [:]
        for id in ids { if let b = model.store.items[id]?.record.fileBytes, b > 0 { known[id] = b } }
        let missing = ids.filter { known[$0] == nil }
        guard !missing.isEmpty else { return known }
        return known.merging(await Gallery.fileSizes(missing)) { a, _ in a }
    }

    private func basic() -> [String] {
        switch filter {
        case .all: model.libraryIDs
        case .real: model.items(in: .realPhotos).map(\.record.id)
        case .videos: model.libraryIDs.filter { model.store.items[$0]?.record.isVideo == true }
        case .screenshots: model.libraryIDs.filter { model.store.items[$0]?.record.isScreenshot == true }
        case .favorites: model.libraryIDs.filter { model.store.items[$0]?.record.isFavorite == true }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    if model.hasIndex {
                        Button { model.tab = .cleanUp } label: {
                            StorageBar(storage: model.storage, segments: model.librarySegments, freeable: model.freeableBytes, review: model.reviewBytes)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Space.l)
                    }
                    PhotoGrid(ids: ids, sectioned: !sortBySize, showSizes: sortBySize, selection: $selection, zoomNamespace: zoom) { viewer = ViewerContext(ids: ids, start: $0) }
                }
                .padding(.bottom, selection == nil ? 0 : 80)
            }
            .background(Palette.background)
            .navigationTitle(filter == .all ? "Library" : filter.rawValue)
            .navigationSubtitle(subtitle(ids.count) + (sortBySize ? " · Largest first" : "") + (hideAlbumPhotos ? " · Not in an album" : ""))
            .toolbar { toolbar }
            .overlay(alignment: .bottom) {
                if selection != nil { SelectionBar(selection: $selection) { Task { await model.loadLibrary() } }.padding(.bottom, Space.s) }
            }
            .overlay {
                if model.libraryIDs.isEmpty {
                    ContentUnavailableView {
                        Label("Your photos stay on this iPhone", systemImage: "lock.iphone")
                    } description: {
                        Text("Spectra sorts your camera roll with on-device AI and shows what can go.")
                    } actions: {
                        Button("Scan my photos") { showScan = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .task { if model.libraryIDs.isEmpty { await model.loadLibrary() } }
            .task(id: "\(filter.rawValue)-\(sortBySize)-\(hideAlbumPhotos)-\(model.libraryIDs.count)-\(model.scanner.revision)") { ids = await filtered() }
            .fullScreenCover(isPresented: $showScan) { ScanView() }
            .fullScreenCover(item: $viewer) { ctx in
                PhotoViewer(context: ctx).navigationTransition(.zoom(sourceID: ctx.ids[ctx.start], in: zoom))
            }
        }
    }

    private func subtitle(_ n: Int) -> String {
        var parts = ["\(n.formatted()) items"]
        if model.freeableBytes > 0 { parts.append("\(gbText(model.freeableBytes)) can go") }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { AIStatusDot() }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if selection == nil {
                Button { showScan = true } label: {
                    Image(systemName: "sparkles").symbolEffect(.breathe, isActive: !reduceMotion && (model.scanner.running || model.scanner.titling))
                }
                    .accessibilityLabel(model.hasIndex ? "Scan again" : "Scan")
                Menu {
                    Picker("Show", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    Section {
                        Picker("Sort", selection: $sortBySize) {
                            Label("Date", systemImage: "calendar").tag(false)
                            Label("Largest first", systemImage: "arrow.down.circle").tag(true)
                        }
                        Toggle(isOn: $hideAlbumPhotos) { Label("Hide photos in albums", systemImage: "rectangle.stack.badge.minus") }
                    }
                    // Same as pinching the grid, for anyone who can't pinch.
                    Picker("Grid size", selection: $gridColumns) {
                        Text("Large").tag(3); Text("Medium").tag(5); Text("Small").tag(9)
                    }
                    .pickerStyle(.menu)
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .accessibilityLabel("Filter")
                Button("Select") { selection = [] }
            } else {
                Button("Cancel") { selection = nil }
            }
        }
    }
}
