import SwiftUI
import Photos
import PhotosUI
import AVKit
import MapKit
import TidyCore
import VisionKit

struct ViewerContext: Identifiable { let id = UUID(); let ids: [String]; let start: Int }

/// Full-screen pager like Apple Photos: pinch/double-tap zoom, videos and Live Photos play,
/// and a glass toolbar with Share · Favourite · Info · Delete. TidyRoll's reason shows on the info sheet.
struct PhotoViewer: View {
    let context: ViewerContext
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [String] = []
    @State private var index = 0
    @State private var chromeHidden = false
    @State private var favorite = false
    @State private var showInfo = false
    @State private var preparing = false
    @State private var sheet: ViewerSheet?
    @State private var slideshow = false
    @State private var liveText = false
    @State private var event: EventSheet?
    @State private var toast: Toast?
    @State private var currentDate: Date?

    private var current: String? { ids.indices.contains(index) ? ids[index] : nil }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                    AssetPage(id: id, active: i == index, liveText: liveText && i == index).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background((chromeHidden ? Color.black : Palette.background).ignoresSafeArea())
            .onTapGesture { withAnimation(Motion.snappy) { chromeHidden.toggle() } }
            .toolbar { toolbar }
            .toolbarVisibility(chromeHidden ? .hidden : .visible, for: .navigationBar, .bottomBar)
            .navigationBarTitleDisplayMode(.inline)
            .statusBarHidden(chromeHidden)
            .safeAreaInset(edge: .bottom) {
                if !chromeHidden && ids.count > 1 {
                    Filmstrip(ids: ids, index: $index).transition(.opacity)
                }
            }
        }
        .onAppear { ids = context.ids; index = context.start; refreshFavorite() }
        .onChange(of: index) { _, _ in refreshFavorite(); liveText = false }
        .sheet(isPresented: $showInfo) { if let current { InfoSheet(id: current).presentationDetents([.medium, .large]) } }
        .sheet(item: $sheet) { s in
            if let current {
                switch s {
                case .album: AlbumPickerSheet(ids: [current]) { title in
                    toast = title.map { Toast(symbol: "rectangle.stack.badge.plus", text: "Added to \($0)") } ?? Toast(symbol: "exclamationmark.triangle", text: "Couldn't add to album")
                }
                case .date: AdjustDateSheet(id: current) { ok in done(ok, "Date adjusted"); refreshFavorite() }
                case .location: AdjustLocationSheet(id: current) { ok in done(ok, "Location updated") }
                }
            }
        }
        .fullScreenCover(isPresented: $slideshow) { SlideshowView(ids: ids, start: index) }
        .sheet(item: $event) { EventEditor(draft: $0.draft, note: $0.note).ignoresSafeArea() }
        .toast($toast)
        .sensoryFeedback(.impact(weight: .light), trigger: favorite)
    }

    /// System toolbars, so every control gets the same iOS 26 glass treatment Photos uses:
    /// Back and the date on top; Share · (Favourite, Info) · Delete along the bottom.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Back")
        }
        ToolbarItem(placement: .principal) {
            if let date = currentDate {
                VStack(spacing: 0) {
                    Text(date.formatted(.dateTime.day().month(.wide).year())).font(.subheadline.weight(.semibold))
                    HStack(spacing: 4) {
                        Text(date.formatted(.dateTime.hour().minute())).foregroundStyle(Palette.secondary)
                        if let item = flagged {
                            Text("·").foregroundStyle(Palette.secondary)
                            Text(item.verdict.reason).foregroundStyle(item.bucket.tint).lineLimit(1)
                        }
                    }
                    .font(.caption)
                }
                .accessibilityElement(children: .combine)
            }
        }
        ToolbarItem(placement: .topBarTrailing) { moreMenu }
        ToolbarItem(placement: .bottomBar) {
            Button { Task { await share() } } label: {
                if preparing { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
            }
            .disabled(preparing).accessibilityLabel(preparing ? "Preparing to share" : "Share")
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            Button { Task { await toggleFavorite() } } label: {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .foregroundStyle(favorite ? Color(.systemPink) : Palette.label)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: favorite)
            }
            .accessibilityLabel(favorite ? "Unfavourite" : "Favourite")
            Button { showInfo = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("Info")
            if isPhoto && ImageAnalyzer.isSupported {
                Button { withAnimation(Motion.snappy) { liveText.toggle() } } label: {
                    Image(systemName: "text.viewfinder").foregroundStyle(liveText ? Color.accentColor : Palette.label)
                }
                .accessibilityLabel(liveText ? "Hide Live Text" : "Live Text")
            }
            if let item = flagged {
                if item.verdict.sensitive != nil {
                    Button { Task { await lock(item) } } label: { Image(systemName: "lock").foregroundStyle(Palette.locked) }
                        .accessibilityLabel("Lock in Hidden album")
                } else {
                    Button { keep(item) } label: { Image(systemName: "checkmark.circle").foregroundStyle(Palette.keep) }
                        .accessibilityLabel("Keep")
                }
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button(role: .destructive) { Task { await delete() } } label: { Image(systemName: "trash") }.accessibilityLabel("Delete")
        }
    }

    /// Photos' ⋯ menu: Copy, Duplicate, Hide, Slideshow, Add to Album, Adjust Date & Time, Adjust Location, Delete.
    private var moreMenu: some View {
        Menu {
            Section {
                if isPhoto { Button { Task { await copy() } } label: { Label("Copy", systemImage: "doc.on.doc") } }
                Button { Task { done(await current.asyncMap(Gallery.duplicate) ?? false, "Duplicated") } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button { Task { await hide() } } label: { Label("Hide", systemImage: "eye.slash") }
                Button { slideshow = true } label: { Label("Slideshow", systemImage: "play.rectangle") }
                if !isPhoto { Button { Task { await compressVideo() } } label: { Label("Compress Video", systemImage: "rectangle.compress.vertical") } }
            }
            Section {
                Button { sheet = .album } label: { Label("Add to Album", systemImage: "rectangle.stack.badge.plus") }
                if let current, model.store.items[current]?.looksLikeEvent == true {
                    Button { Task { await addToCalendar(current) } } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                }
            }
            Section {
                Button { sheet = .date } label: { Label("Adjust Date & Time", systemImage: "calendar.badge.clock") }
                Button { sheet = .location } label: { Label("Adjust Location", systemImage: "mappin.and.ellipse") }
            }
            Section {
                Button(role: .destructive) { Task { await delete() } } label: { Label("Delete", systemImage: "trash") }
            }
        } label: { Image(systemName: "ellipsis") }
        .accessibilityLabel("More")
    }

    private var isPhoto: Bool { current.flatMap(Gallery.asset)?.mediaType == .image }

    private func done(_ ok: Bool, _ text: String) {
        toast = ok ? Toast(symbol: "checkmark.circle.fill", text: text, tint: Palette.keep)
                   : Toast(symbol: "exclamationmark.triangle", text: "Couldn't finish — try again", tint: Palette.junk)
    }

    private func copy() async {
        guard let current, let img = await Gallery.image(current, maxPixel: 4096) else { return done(false, "") }
        UIPasteboard.general.image = img
        done(true, "Copied")
    }

    private func addToCalendar(_ id: String) async {
        toast = Toast(symbol: "sparkles", text: "Reading the ticket on this iPhone…")
        switch await model.calendarEvent(for: id) {
        case .success(let e): toast = nil; event = e
        case .failure(let err): toast = Toast(symbol: "calendar.badge.exclamationmark", text: err.message)
        }
    }

    private func compressVideo() async {
        guard let current else { return }
        toast = Toast(symbol: "hourglass", text: "Compressing on this iPhone…")
        let r = await VideoCompressor.compress([current]) { _ in }
        if r.compressed > 0 {
            toast = Toast(symbol: "checkmark.circle.fill", text: "Freed \(gbText(r.saved)) · kept in HD", tint: Palette.keep)
            await removeCurrent()
        } else {
            toast = Toast(symbol: r.alreadyCompact > 0 ? "checkmark.seal" : "xmark.circle", text: r.alreadyCompact > 0 ? "Already compact" : "Nothing changed")
        }
    }

    private func hide() async {
        guard let current, await Gallery.hide([current]) else { return }
        toast = Toast(symbol: "eye.slash", text: "Moved to Hidden album")
        await removeCurrent()
    }

    /// The current item when TidyRoll flagged it (anything not kept, or an ID to lock).
    private var flagged: IndexedItem? {
        guard let current, let item = model.store.items[current] else { return nil }
        return item.verdict.verdict != .keep || item.verdict.sensitive != nil ? item : nil
    }

    private func keep(_ item: IndexedItem) {
        model.keep([item.record.id])
        toast = Toast(symbol: "checkmark.circle.fill", text: "Kept", tint: Palette.keep)
    }

    private func lock(_ item: IndexedItem) async {
        guard await Gallery.hide([item.record.id]) else { return }
        toast = Toast(symbol: "lock.fill", text: "Locked in your Hidden album", tint: Palette.locked)
        await removeCurrent()
    }

    private func removeCurrent() async {
        guard let current, let at = ids.firstIndex(of: current) else { return }
        let next = min(at, ids.count - 2)
        if next < 0 { await model.forget([current]); dismiss(); return }
        index = next
        ids.remove(at: at)
        await model.forget([current])
    }

    /// One PhotoKit read per photo change (not per render).
    private func refreshFavorite() {
        let a = current.flatMap(Gallery.asset)
        favorite = a?.isFavorite ?? false
        currentDate = a?.creationDate
    }

    private func toggleFavorite() async {
        guard let current else { return }
        try? await Gallery.setFavorite(current, !favorite)
        favorite.toggle()
        toast = Toast(symbol: favorite ? "heart.fill" : "heart.slash", text: favorite ? "Added to Favourites" : "Removed from Favourites",
                      tint: favorite ? Color(.systemPink) : Palette.label)
    }

    private func delete() async {
        guard let current, await Gallery.delete([current]) else { return }
        toast = Toast(symbol: "trash", text: "Moved to Recently Deleted")
        await removeCurrent()
    }

    private func share() async {
        guard let current, !preparing else { return }
        preparing = true
        defer { preparing = false }
        if !(await Sharing.share([current])) { done(false, "") }
    }
}

/// One page: zoomable photo, Live Photo, or video.
private struct AssetPage: View {
    let id: String
    let active: Bool
    var liveText = false
    @State private var still: UIImage?
    @State private var kind: PHAssetMediaType = .image
    @State private var live = false
    @State private var player: AVPlayer?
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1

    var body: some View {
        Group {
            if kind == .video, let player {
                VideoPlayer(player: player).onAppear { if active { player.play() } }.onDisappear { player.pause() }
            } else if liveText, let still {
                LiveTextImage(image: still)
            } else if live {
                LivePhotoView(id: id)
            } else {
                AssetThumbnail(id: id, side: 1200, fit: true)
                    .scaleEffect(zoom)
                    .gesture(MagnifyGesture()
                        .onChanged { zoom = max(1, lastZoom * $0.magnification) }
                        .onEnded { _ in lastZoom = zoom; if zoom < 1.05 { withAnimation(Motion.snappy) { zoom = 1; lastZoom = 1 } } })
                    .onTapGesture(count: 2) { withAnimation(Motion.smooth) { zoom = zoom > 1 ? 1 : 2.5; lastZoom = zoom } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Photo")
                    .accessibilityAddTraits(.isImage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: id) { await load() }
        .onChange(of: active) { _, on in if !on { player?.pause() } }
        .task(id: liveText) { if liveText && still == nil { still = await Gallery.image(id, maxPixel: 2400) } }
    }

    private func load() async {
        guard let a = Gallery.asset(id) else { return }
        kind = a.mediaType
        live = a.mediaSubtypes.contains(.photoLive)
        guard a.mediaType == .video else { return }
        player = await Gallery.playerItem(id).map(AVPlayer.init)
    }
}

/// Live Photo that plays on press, like Photos.
private struct LivePhotoView: UIViewRepresentable {
    let id: String
    func makeUIView(context: Context) -> PHLivePhotoView {
        let v = PHLivePhotoView(); v.contentMode = .scaleAspectFit
        if let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
            let o = PHLivePhotoRequestOptions(); o.isNetworkAccessAllowed = true; o.deliveryMode = .highQualityFormat
            PHImageManager.default().requestLivePhoto(for: a, targetSize: UIScreen.main.bounds.size, contentMode: .aspectFit, options: o) { lp, _ in
                v.livePhoto = lp
            }
        }
        return v
    }
    func updateUIView(_ v: PHLivePhotoView, context: Context) {}
}

/// Info panel like Photos: date, file, size, location, plus TidyRoll's reason and where it was decided.
private struct InfoSheet: View {
    let id: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let info = Gallery.info(id)
        let item = model.store.items[id]
        NavigationStack {
            List {
                if let item {
                    Section("Spectra") {
                        Label(item.verdict.reason, systemImage: item.bucket.symbol).foregroundStyle(item.bucket.tint)
                        LabeledContent("Collection", value: item.bucket.title)
                        LabeledContent("Decided by", value: item.verdict.source == .rules ? "Rules on this iPhone" : item.verdict.source == .onDevice ? "On-device AI" : "Cloud (text only)")
                        if let s = item.verdict.savedInfo { LabeledContent(s.title, value: s.fields["detail"] ?? "") }
                    }
                }
                if let info {
                    Section("Details") {
                        if let d = info.date { LabeledContent("Date", value: d.formatted(date: .complete, time: .shortened)) }
                        LabeledContent("File", value: info.filename)
                        LabeledContent("Size", value: "\(gbText(info.bytes)) · \(info.pixelWidth) × \(info.pixelHeight)")
                        if info.isVideo { LabeledContent("Length", value: Duration.seconds(info.duration).formatted(.time(pattern: .minuteSecond))) }
                        if let make = item?.record.cameraMake { LabeledContent("Camera", value: [make, item?.record.cameraModel].compactMap { $0 }.joined(separator: " ")) }
                    }
                    if let loc = info.location {
                        Section("Location") {
                            Map(initialPosition: .region(MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))) {
                                Marker("", coordinate: loc.coordinate)
                            }
                            .frame(height: 180).listRowInsets(EdgeInsets())
                        }
                    }
                }
            }
            .navigationTitle("Info").navigationBarTitleDisplayMode(.inline)
        }
    }
}

enum ViewerSheet: String, Identifiable { case album, date, location; var id: String { rawValue } }

private extension Optional {
    func asyncMap<U>(_ f: (Wrapped) async -> U) async -> U? { if let w = self { await f(w) } else { nil } }
}

/// Thumbnail scrubber above the toolbar, like Photos. The current item is wider.
private struct Filmstrip: View {
    let ids: [String]
    @Binding var index: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 2) {
                    ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                        AssetThumbnail(id: id, side: 96)
                            .frame(width: i == index ? 44 : 32, height: 44).clipped()
                            .clipShape(.rect(cornerRadius: 3))
                            .padding(.horizontal, i == index ? 4 : 0)
                            .id(i)
                            .onTapGesture { index = i }
                            .accessibilityLabel("Item \(i + 1) of \(ids.count)")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHidden(abs(i - index) > 2)   // VoiceOver: only the neighbours, not hundreds of thumbnails
                    }
                }
                .padding(.horizontal, 180)
            }
            .frame(height: 44)
            .onAppear { proxy.scrollTo(index, anchor: .center) }
            .onChange(of: index) { _, i in withAnimation(Motion.snappy) { proxy.scrollTo(i, anchor: .center) } }
        }
        .padding(.bottom, Space.s)
    }
}
