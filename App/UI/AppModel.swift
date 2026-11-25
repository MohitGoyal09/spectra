import SwiftUI
import Photos
import WidgetKit
import TidyCore

/// App-wide state: the index, the scanner and the hybrid judge, plus derived numbers for the screens.
@MainActor @Observable final class AppModel {
    let store: IndexStore
    let judge: HybridJudge
    let scanner: Scanner
    let log: PrivacyLog
    let rules: RuleStore
    let enricher: Enricher
    var storage = StorageSnapshot.current()
    var askConsent = false
    var libraryIDs: [String] = []
    @ObservationIgnored private var observer: LibraryObserver?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    var tab: AppTab = .library
    /// Space target asked for by Siri or Shortcuts; Clean Up opens its planner with it.
    var pendingPlanGB: Double?
    /// A photo to open from a notification (clean as you go).
    var pendingViewer: ViewerContext?
    /// The running app's model, for App Intents (Siri, Shortcuts, widget taps).
    @ObservationIgnored nonisolated(unsafe) static weak var current: AppModel?

    func openPlanner(gigabytes: Double) { tab = .cleanUp; pendingPlanGB = gigabytes }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(FilmScope.dataFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        log = PrivacyLog(fileURL: dir.appendingPathComponent("privacy-log.json"))
        store = IndexStore(directory: dir)
        rules = RuleStore(directory: dir)
        enricher = Enricher(store: store, directory: dir, log: log)
        judge = HybridJudge(log: log)
        scanner = Scanner(store: store, library: PhotoLibraryService(), analyzer: VisionAnalyzer(), judge: judge)
        askConsent = judge.needsConsent
        Self.current = self
        observer = LibraryObserver { [weak self] in Task { @MainActor in self?.librarySoonChanged() } }
        if UserDefaults.standard.integer(forKey: "rulesVersion") < Self.rulesVersion, hasIndex {
            Task { await scanner.rejudgeAll(); UserDefaults.standard.set(Self.rulesVersion, forKey: "rulesVersion") }
        } else {
            UserDefaults.standard.set(Self.rulesVersion, forKey: "rulesVersion")
        }
        // Matching improves between versions: bring every smart album up to date on launch.
        if hasIndex { Task { await scanner.rejudgeTimeSensitive(); await applyRules(); await enrich() } }
    }

    /// Bump when sorting rules change so stored verdicts are recomputed on next launch.
    static let rulesVersion = 4

    /// Everything the screens derive from the index, computed once per index change (not per render).
    struct Snapshot {
        var all: [IndexedItem] = []
        var byBucket: [Bucket: [IndexedItem]] = [:]       // newest first
        var counts: [Bucket: Int] = [:]
        var localBytes: [Bucket: Int64] = [:]
        var freeable: Int64 = 0
        var review: Int64 = 0
        /// Vision labels in this library, most common first: the words search and smart albums can match on.
        var labels: [String] = []
    }
    @ObservationIgnored private var cache: (revision: Int, snapshot: Snapshot)?

    var snapshot: Snapshot {
        let rev = scanner.revision
        if let cache, cache.revision == rev { return cache.snapshot }
        var s = Snapshot()
        s.all = Array(store.items.values)
        for i in s.all {
            let b = i.bucket
            s.byBucket[b, default: []].append(i)
            if i.record.isLocal {
                s.localBytes[b, default: 0] += i.record.fileBytes
                if isPreselectable(i.verdict, record: i.record) { s.freeable += i.record.fileBytes }
                if i.verdict.verdict == .review && i.verdict.sensitive == nil && b != .realPhotos { s.review += i.record.fileBytes }
            }
        }
        for (b, list) in s.byBucket {
            s.byBucket[b] = list.sorted { $0.record.createdAt > $1.record.createdAt }
            s.counts[b] = list.count
        }
        var freq: [String: Int] = [:]
        for i in s.all where i.verdict.sensitive == nil { for l in i.record.labels { freq[l, default: 0] += 1 } }
        s.labels = freq.sorted { $0.value > $1.value }.prefix(RuleCompilerConfig.maxLabels).map(\.key)
        cache = (rev, s)
        return s
    }

    private var items: [IndexedItem] { snapshot.all }

    var realCount: Int { snapshot.counts[.realPhotos] ?? 0 }
    var elseCount: Int { snapshot.all.count - realCount }
    var freeableBytes: Int64 { snapshot.freeable }
    var hasIndex: Bool { !items.isEmpty }

    /// Library bytes on this iPhone per collection, largest first: the storage bar's segments.
    var librarySegments: [(bucket: Bucket, bytes: Int64)] {
        snapshot.localBytes.map { ($0.key, $0.value) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }

    /// The user keeps an item: rules never override it and it is never offered for deletion again.
    func keep(_ ids: [String]) {
        for id in ids {
            store.update(id) {
                $0.userKept = true
                $0.verdict.verdict = .keep
                $0.verdict.junkType = nil
                $0.verdict.reason = "Kept by you"
            }
        }
        store.save()
        scanner.touch()
    }

    /// Removes deleted or hidden items from the index and refreshes the library.
    func forget(_ ids: [String]) async {
        let infos = ids.compactMap { id in store.items[id].flatMap { i in i.verdict.savedInfo.map { ArchivedInfo(id: id, info: $0, date: i.record.createdAt) } } }
        if !infos.isEmpty { rules.archive(infos) }
        store.remove(ids: ids)
        store.save()
        scanner.touch()
        await loadLibrary()
        storage = .current()
        publishWidget()
    }

    /// Photos that match a rule (sensitive items never match).
    /// Photos that match a rule, newest first (sensitive items and photos the user took out never match).
    func matching(_ spec: RuleSpec, excluding: [String]? = nil) -> [String] {
        let out = Set(excluding ?? [])
        let picture = spec.visual.flatMap(pictureMatches)
        return snapshot.all.filter {
            !out.contains($0.record.id) && matches(spec, verdict: $0.verdict, record: $0.record, visual: picture.map { [id = $0.record.id] in $0[id] != nil })
        }
        .sorted { $0.record.createdAt > $1.record.createdAt }.map(\.record.id)
    }

    /// Rules saved before picture search get a look from their own words ("Lens", "girls"); document rules stay text-only.
    /// Models (small on-device, or Gemini) sometimes add kinds, types, labels or dates the sentence never asked for.
    /// If the rule finds nothing, drop those extras step by step and keep the words and look.
    func relaxed(_ s: RuleSpec) -> RuleSpec {
        guard matching(s).isEmpty else { return s }
        func content(_ r: RuleSpec) -> Bool { !r.include.isEmpty || r.visual != nil }
        var loose = s
        loose.include.kinds = nil; loose.include.docTypes = nil; loose.include.junkTypes = nil
        if content(loose), !matching(loose).isEmpty { return loose }
        loose.include.labels = nil
        if content(loose), !matching(loose).isEmpty { return loose }
        loose.include.dateFrom = nil; loose.include.dateTo = nil
        return content(loose) && !matching(loose).isEmpty ? loose : s
    }

    func matching(_ rule: SavedRule) -> [String] {
        var spec = rule.spec
        if spec.visual == nil, spec.include.docTypes == nil, let word = spec.include.labels?.first ?? spec.include.keywords?.first {
            spec.visual = word.replacingOccurrences(of: "_", with: " ")
        }
        return matching(spec, excluding: rule.excluded)
    }

    @ObservationIgnored private var pictureCache: (revision: Int, results: [String: [String: Float]]) = (-1, [:])

    /// Picture search, cached per query until the stored vectors change. Nil when picture search is unavailable.
    func pictureMatches(_ query: String) -> [String: Float]? {
        let key = query.lowercased().trimmingCharacters(in: .whitespaces)
        if pictureCache.revision != enricher.clip.revision { pictureCache = (enricher.clip.revision, [:]) }
        if let hit = pictureCache.results[key] { return hit }
        guard let r = enricher.clip.search(key) else { return nil }
        pictureCache.results[key] = r
        return r
    }

    /// Detailed labels, picture-search vectors and places for photos that lack them; albums refresh after.
    func enrich() async {
        await enricher.run { [weak self] in self?.scanner.touch() }
        await applyRules()
        publishWidget()
    }

    /// Updates the home-screen widget with what can be freed now.
    func publishWidget() {
        let s = WidgetSummary(freeableBytes: freeableBytes, reviewBytes: reviewBytes, expiredScreenshots: count(.expiredScreenshots),
                              duplicates: count(.duplicates), forwards: count(.forwards), updated: .now)
        WeeklyDigest.schedule(s)   // the digest is one-shot; reschedule every time
        let all = snapshot.all
        Task { await CleanAsYouGo.schedule(all) }
        let old = WidgetSummary.load()
        guard s.freeableBytes != old?.freeableBytes || s.duplicates != old?.duplicates || s.expiredScreenshots != old?.expiredScreenshots else { return }
        s.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// "Not this photo": takes photos out of a smart album for good.
    func remove(_ ids: [String], from rule: SavedRule) async {
        rules.exclude(ids, from: rule.id)
        if let album = rule.albumID { _ = await Gallery.remove(ids, fromAlbum: album) }
        scanner.touch()
    }

    /// Keeps every saved smart album up to date with newly sorted photos.
    func applyRules() async {
        for r in rules.rules {
            let ids = matching(r)
            if let albumID = await Gallery.addToAlbum(title: r.spec.name, ids: ids) { rules.setAlbum(r.id, albumID) }
        }
    }

    // MARK: Suggested albums

    private(set) var suggestions: [AlbumSuggestion] = []
    /// AI-written names, keyed by the rule-made name ("Dog" → "Good Dogs"); kept so each is named once.
    private(set) var suggestionNames: [String: String] = [:]
    @ObservationIgnored private var suggestedAt = -1
    private static let dismissedKey = "dismissedSuggestions"

    func title(of s: AlbumSuggestion) -> String { suggestionNames[s.spec.name] ?? s.spec.name }

    /// Recomputes suggestions once per index change (not while scanning), then names new ones with the on-device model.
    func refreshSuggestions() async {
        let rev = scanner.revision
        guard rev != suggestedAt, !scanner.running, hasIndex else { return }
        suggestedAt = rev
        let items = snapshot.all.map { (verdict: $0.verdict, record: $0.record) }
        let existing = rules.rules.map(\.spec)
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? [])
        let found = await Task.detached(priority: .utility) { suggestAlbums(items, existing: existing) }.value
            .filter { !dismissed.contains($0.spec.name) }
        let unnamed = found.filter { suggestionNames[$0.spec.name] == nil }
        if let names = await judge.nameSuggestions(unnamed) {
            for (x, n) in zip(unnamed, names) where !n.isEmpty { suggestionNames[x.spec.name] = n }
        }
        suggestions = found
    }

    func dismiss(_ s: AlbumSuggestion) {
        let key = Self.dismissedKey
        UserDefaults.standard.set((UserDefaults.standard.stringArray(forKey: key) ?? []) + [s.spec.name], forKey: key)
        suggestions.removeAll { $0.spec == s.spec }
    }

    /// Makes the suggestion a real smart album: saved rule + Apple Photos album, kept up to date.
    func accept(_ s: AlbumSuggestion) async -> Bool {
        var spec = s.spec
        spec.name = title(of: s)
        let rule = SavedRule(sentence: "Suggested: \(spec.name)", spec: spec)
        guard let album = await Gallery.addToAlbum(title: spec.name, ids: s.ids) else { return false }
        rules.add(rule)
        rules.setAlbum(rule.id, album)
        suggestions.removeAll { $0.spec == s.spec }
        scanner.touch()
        return true
    }

    /// Saved info from current screenshots plus info kept after its screenshot was deleted.
    var savedInfos: [ArchivedInfo] {
        let live = snapshot.all.compactMap { i in i.verdict.savedInfo.map { ArchivedInfo(id: i.record.id, info: $0, date: i.record.createdAt) } }
        let liveIDs = Set(live.map(\.id))
        return (live + rules.archive.filter { !liveIDs.contains($0.id) }).sorted { $0.date > $1.date }
    }

    func plan(target: Int64) -> (items: [PlanItem], freedBytes: Int64, metTarget: Bool) {
        let all = items
        let exact = Set(all.filter { $0.verdict.junkType == .duplicate && $0.verdict.verdict == .junk }.map(\.record.id))
        let near = Set(all.filter { $0.verdict.junkType == .duplicate && $0.verdict.verdict == .review }.map(\.record.id))
        return planSpace(targetBytes: target, items: all.filter { $0.userKept != true }.map { ($0.verdict, $0.record) },
                         nearDuplicateIDs: near, exactDuplicateIDs: exact)
    }

    /// Collections that can go, largest first, for the storage bar.
    /// Items worth a look (review verdict, on this phone, never real photos or IDs).
    var reviewBytes: Int64 { snapshot.review }

    var freeableSegments: [(bucket: Bucket, bytes: Int64)] {
        let groups = Dictionary(grouping: items.filter { isPreselectable($0.verdict, record: $0.record) && $0.record.isLocal }, by: \.bucket)
        return groups.map { ($0.key, $0.value.map(\.record.fileBytes).reduce(0, +)) }.sorted { $0.1 > $1.1 }
    }

    /// Gallery content: real photos after a scan, the whole library before one.
    var galleryIDs: [String] {
        let real = items(in: .realPhotos).map(\.record.id)
        return real.isEmpty ? libraryIDs : real
    }

    /// Coalesces bursts of library changes, then refreshes ids, drops deleted items from the index and refreshes favourites.
    private func librarySoonChanged() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let ids = await PhotoLibraryService().assetIDs()
            let present = Set(ids)
            let gone = store.items.keys.filter { !present.contains($0) }
            if !gone.isEmpty { store.remove(ids: gone); store.save() }
            let favOptions = PHFetchOptions(); favOptions.predicate = NSPredicate(format: "favorite == YES")
            let favorites = Set(Gallery.ids(in: PHAsset.fetchAssets(with: favOptions)))
            for (id, item) in store.items where item.record.isFavorite != favorites.contains(id) {
                store.update(id) { $0.record.isFavorite = favorites.contains(id) }
            }
            libraryIDs = ids
            storage = .current()
            scanner.touch()
            // New photos (camera, downloads, WhatsApp): sort them and add them to smart albums, once a first scan exists.
            if hasIndex, ids.contains(where: { store.items[$0] == nil }) {
                if scanner.running { syncAfterScan = true } else { await scan() }   // never drop photos that arrive mid-scan
            }
        }
    }

    func loadLibrary() async {
        let status = await PhotoLibraryService().requestAccess()
        guard status == .authorized || status == .limited else { return }
        libraryIDs = await PhotoLibraryService().assetIDs()
    }

    func items(in bucket: Bucket) -> [IndexedItem] { snapshot.byBucket[bucket] ?? [] }
    func count(_ b: Bucket) -> Int { snapshot.counts[b] ?? 0 }
    func bytes(_ b: Bucket) -> Int64 { snapshot.localBytes[b] ?? 0 }

    var glow: GlowState {
        glowState(onDeviceAvailable: judge.status == .available, cloudBusy: judge.cloudBusy, working: scanner.running || scanner.titling)
    }

    func scan() async {
        _ = await PhotoLibraryService().requestAccess()
        if libraryIDs.isEmpty { libraryIDs = await PhotoLibraryService().assetIDs() }
        await scanner.scan()
        storage = .current()
        await applyRules()
        await scanner.titlePending()
        await enrich()
        if syncAfterScan { syncAfterScan = false; await scan(); return }
        // Photos iOS was still saving (just taken or downloaded) were skipped: try again in a few seconds, a few times.
        if scanner.waiting > 0, scanRetries < Self.maxScanRetries {
            scanRetries += 1
            Task { try? await Task.sleep(for: .seconds(4)); await scan() }
        } else { scanRetries = 0 }
    }

    @ObservationIgnored private var scanRetries = 0
    /// Photos arrived while a scan was running; scan again when it ends.
    @ObservationIgnored private var syncAfterScan = false
    private static let maxScanRetries = 3
}

struct StorageSnapshot {
    var total: Int64
    var available: Int64
    var used: Int64 { max(total - available, 0) }
    static func current() -> StorageSnapshot {
        let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return StorageSnapshot(total: Int64(v?.volumeTotalCapacity ?? 0), available: v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

/// Small cached thumbnail for a photo id (never leaves the device).
struct AssetThumbnail: View {
    let id: String
    var side: CGFloat = 120
    /// Show the whole photo at its own shape (viewer, slideshow) instead of a cropped square tile.
    var fit = false
    @State private var image: UIImage?
    private static let manager = PHCachingImageManager()

    var body: some View {
        if fit {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: id) { image = await load() }
            .accessibilityHidden(true)
        } else {
            Rectangle().fill(Palette.fill)
                .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
                .clipped()
                .task(id: id) { image = await load() }
                .accessibilityHidden(true)
        }
    }

    /// Requests a thumbnail and cancels it if the cell scrolls away before it arrives.
    private func load() async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let px = side * UIScreen.main.scale
        let box = RequestBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                let o = PHImageRequestOptions()
                o.deliveryMode = .opportunistic
                o.isNetworkAccessAllowed = true   // the user's own preview from iCloud when not on the phone (download only)
                o.resizeMode = .fast
                var resumed = false
                box.id = Self.manager.requestImage(for: asset, targetSize: CGSize(width: px, height: px), contentMode: fit ? .aspectFit : .aspectFill, options: o) { img, info in
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    guard !resumed, !degraded || img == nil || cancelled else { return }
                    resumed = true
                    cont.resume(returning: cancelled ? nil : img)
                }
            }
        } onCancel: { [box] in
            if let id = box.id { Self.manager.cancelImageRequest(id) }
        }
    }
}

private final class RequestBox: @unchecked Sendable { var id: PHImageRequestID? }

/// Apple-Photos-style duration label on video thumbnails.
struct VideoBadge: View {
    let id: String
    @Environment(AppModel.self) private var model
    var body: some View {
        if let r = model.store.items[id]?.record, r.isVideo, let d = r.durationSec {
            Text(Duration.seconds(d).formatted(.time(pattern: .minuteSecond)))
                .font(.caption2.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 2)
                .padding(4)
                .accessibilityLabel("Video, \(Duration.seconds(d).formatted(.time(pattern: .minuteSecond)))")
        }
    }
}
enum AppTab: Hashable { case library, collections, cleanUp, debug, search }
