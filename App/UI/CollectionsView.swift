import SwiftUI
import TidyCore

/// Collections tab like Apple Photos: pinned media types and the user's albums, each opening a grid.
struct CollectionsView: View {
    @State private var mediaTypes: [AlbumInfo] = []
    @State private var albums: [AlbumInfo] = []
    @State private var open: AlbumInfo?
    @State private var openBucket: Bucket?
    @State private var newAlbum = false
    @State private var toast: Toast?
    @AppStorage(AlbumLock.key) private var lockedIDs = ""   // redraws tiles when a lock changes
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    cleanUpRow
                    smartAlbums
                    suggested
                    row("Pinned", mediaTypes)
                    row("Albums", albums)
                }
                .padding(.vertical, Space.l)
            }
            .background(Palette.background)
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AIStatusDot() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newAlbum = true } label: { Image(systemName: "plus") }.accessibilityLabel("New smart album")
                }
            }
            .sheet(isPresented: $newAlbum, onDismiss: { albums = Gallery.userAlbums() }) { SmartAlbumSheet() }
            .navigationDestination(item: $open) { AlbumGridView(album: $0) }
            .navigationDestination(item: $openBucket) { b in
                switch b {
                case .duplicates: DuplicatesView()
                case .usefulScreenshots: SavedInfoView()
                default: BucketGridView(bucket: b)
                }
            }
            .task { mediaTypes = Gallery.mediaTypes(); albums = Gallery.userAlbums() }
            .task(id: model.scanner.revision) { await model.refreshSuggestions() }
            .toast($toast)
            .refreshable { mediaTypes = Gallery.mediaTypes(); albums = Gallery.userAlbums() }
        }
    }

    /// TidyRoll's collections as a pinned row, like Apple's Utilities.
    @ViewBuilder private var cleanUpRow: some View {
        let buckets = Bucket.allCases.filter { $0 != .realPhotos && model.count($0) > 0 }
        if !buckets.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Text("Clean Up").font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("See all") { model.tab = .cleanUp }.font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
                }
                .padding(.horizontal, Space.l)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Space.m) {
                        ForEach(buckets, id: \.self) { b in
                            Button { openBucket = b } label: {
                                tile(AlbumInfo(id: b.rawValue, title: b.title, count: model.count(b), coverID: model.items(in: b).first?.record.id, symbol: b.symbol))
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                    .padding(.horizontal, Space.l)
                }
            }
        }
    }

    /// Albums made from a sentence: Gemini compiled the rule; this iPhone keeps them up to date.
    private var smartAlbums: some View {
        let _ = model.scanner.revision   // refresh when rules change
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("Smart albums").font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { newAlbum = true } label: { Label("New", systemImage: "plus") }.font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
            }
            .padding(.horizontal, Space.l)
            if model.rules.rules.isEmpty {
                Button { newAlbum = true } label: {
                    HStack(spacing: Space.m) {
                        Image(systemName: "text.badge.plus").font(.title2).foregroundStyle(Palette.glow[0])
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Describe an album in a sentence").font(.subheadline.weight(.semibold))
                            Text("\u{201C}Bills and receipts go to Tax 2026\u{201D}").font(.footnote).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                    }
                    .padding(Space.l)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                .buttonStyle(PressScaleStyle())
                .padding(.horizontal, Space.l)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Space.m) {
                        ForEach(model.rules.rules) { r in
                            let ids = model.matching(r)
                            Button { if let a = r.albumID { open = AlbumInfo(id: a, title: r.spec.name, count: ids.count, coverID: ids.first, symbol: "sparkles.rectangle.stack") } } label: {
                                tile(AlbumInfo(id: r.albumID ?? r.id.uuidString, title: r.spec.name, count: ids.count, coverID: ids.first, symbol: "sparkles.rectangle.stack"))
                            }
                            .buttonStyle(PressScaleStyle())
                            .contextMenu {
                                Text(r.sentence)
                                Button(role: .destructive) { model.rules.remove(r.id); model.scanner.touch() } label: { Label("Stop updating album", systemImage: "trash") }
                            }
                        }
                    }
                    .padding(.horizontal, Space.l)
                }
            }
        }
    }

    /// Albums the on-device AI suggests from what's already in the library. One tap makes a real, self-updating album.
    @ViewBuilder private var suggested: some View {
        if !model.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.s) {
                    Text("Suggested").font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Image(systemName: "sparkles").foregroundStyle(Palette.glow[1])
                }
                .padding(.horizontal, Space.l)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Space.m) {
                        ForEach(model.suggestions, id: \.spec.name) { s in suggestionCard(s) }
                    }
                    .padding(.horizontal, Space.l).padding(.vertical, Space.xs)
                }
            }
            .transition(.opacity)
        }
    }

    private func suggestionCard(_ s: AlbumSuggestion) -> some View {
        let title = model.title(of: s)
        return VStack(alignment: .leading, spacing: Space.s) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow { mosaic(s, 0); mosaic(s, 1) }
                GridRow { mosaic(s, 2); mosaic(s, 3) }
            }
            .frame(width: 196, height: 196)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button { withAnimation(Motion.snappy) { model.dismiss(s) } } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).padding(7)
                }
                .buttonStyle(.glass).padding(Space.s).accessibilityLabel("Not now")
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text("\(s.ids.count) photos").font(.footnote).foregroundStyle(Palette.secondary).monospacedDigit()
                }
                Spacer(minLength: Space.s)
                Button("Create") {
                    Task {
                        let ok = await model.accept(s)
                        albums = Gallery.userAlbums()
                        toast = ok ? Toast(symbol: "sparkles.rectangle.stack", text: "\u{201C}\(title)\u{201D} created", tint: Palette.keep)
                                   : Toast(symbol: "exclamationmark.triangle", text: "Couldn't create the album", tint: Palette.junk)
                    }
                }
                .font(.footnote.weight(.semibold)).buttonStyle(.glassProminent)
            }
            .frame(width: 196)
        }
        .padding(Space.s)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card + Space.s, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested album \(title), \(s.ids.count) photos")
    }

    @ViewBuilder private func mosaic(_ s: AlbumSuggestion, _ i: Int) -> some View {
        Color.clear.frame(width: 97, height: 97)
            .overlay { if s.ids.indices.contains(i) { AssetThumbnail(id: s.ids[i], side: 120) } else { Palette.fill } }
            .clipped()
    }

    @ViewBuilder private func row(_ title: String, _ items: [AlbumInfo]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(title).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader).padding(.horizontal, Space.l)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Space.m) {
                        ForEach(items) { a in
                            Button { open = a } label: { tile(a) }.buttonStyle(PressScaleStyle())
                        }
                    }
                    .padding(.horizontal, Space.l)
                }
            }
        }
    }

    private func tile(_ a: AlbumInfo) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ZStack(alignment: .bottomLeading) {
                let locked = lockedIDs.split(separator: "\n").contains { $0 == a.id }
                let cover = locked ? nil : a.coverID
                if let c = cover { AssetThumbnail(id: c, side: 160) } else { Palette.fill }
                if cover != nil { LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom) }
                Label(a.title, systemImage: locked ? "lock.fill" : a.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(cover == nil ? Palette.label : .white)
                    .lineLimit(2)
                    .padding(Space.s)
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            Text(a.count.formatted()).font(.footnote).foregroundStyle(Palette.secondary).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.title), \(a.count) items")
        .accessibilityAddTraits(.isButton)
    }
}

struct AlbumGridView: View {
    let album: AlbumInfo
    @Environment(AppModel.self) private var model
    @State private var ids: [String] = []
    @State private var viewer: ViewerContext?
    @State private var selection: Set<String>?
    @State private var locked = false
    @State private var unlocked = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if locked && !unlocked {
                ContentUnavailableView {
                    Label("Locked", systemImage: "lock.fill")
                } description: {
                    Text("Use Face ID to see this album.")
                } actions: {
                    Button("Unlock") { Task { await open() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView { PhotoGrid(ids: ids, selection: $selection) { viewer = ViewerContext(ids: ids, start: $0) } }
            }
        }
            .background(Palette.background)
            .navigationTitle(album.title)
            .navigationSubtitle(locked && !unlocked ? "Locked" : "\(ids.count.formatted()) items")
            .toolbar {
                if !locked || unlocked {
                    Button { toggleLock() } label: { Image(systemName: locked ? "lock.fill" : "lock.open") }
                        .accessibilityLabel(locked ? "Remove lock" : "Lock with Face ID")
                        .disabled(!locked && !AlbumLock.canLock)
                    Button(selection == nil ? "Select" : "Cancel") { selection = selection == nil ? [] : nil }
                }
            }
            .overlay(alignment: .bottom) { if selection != nil { SelectionBar(selection: $selection, onNotInAlbum: smartRule.map { rule in { ids in await model.remove(ids, from: rule) } }) { ids = Gallery.ids(inCollection: album.id) } } }
            .task {
                locked = AlbumLock.isLocked(album.id)
                await open()
            }
            .onChange(of: scenePhase) { _, phase in
                // Lock again as soon as Spectra stops being active (app switcher, Control Centre), so its snapshot shows nothing.
                // The Face ID prompt also makes the scene inactive, but `unlocked` is still false then, so this does nothing.
                if phase != .active && locked && unlocked { unlocked = false; viewer = nil; selection = nil; ids = [] }
            }
            .fullScreenCover(item: $viewer) { PhotoViewer(context: $0) }
    }

    private func open() async {
        if locked && !unlocked { unlocked = await AlbumLock.unlock("Open \(album.title)") }
        if !locked || unlocked { ids = Gallery.ids(inCollection: album.id) }
    }

    private func toggleLock() {
        locked.toggle()
        unlocked = true
        AlbumLock.setLocked(album.id, locked)
    }

    /// The smart album's rule, when this album is one (enables "Not in this album").
    private var smartRule: SavedRule? { model.rules.rules.first { $0.albumID == album.id } }
}
