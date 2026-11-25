import Foundation
import Observation
import TidyCore

enum ScanConfig {
    static let concurrency = 4
    static let chunk = 20
    static let candidateHamming = 6
    static let exactHamming = 2
}

/// Indexes the library: metadata → Vision → rules → (vague items only) model notes → merge → save. Resumable.
@MainActor @Observable final class Scanner {
    private(set) var total = 0
    private(set) var done = 0
    /// Photos the last scan had to skip because iOS hadn't finished saving them; scan again shortly.
    private(set) var waiting = 0
    private(set) var running = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastEvent: (id: String, bucket: Bucket)?
    /// Every judged item in order, for the scan animation (consumers keep their own read position).
    private(set) var events: [(id: String, bucket: Bucket)] = []
    /// Bumped whenever the index changes, so views that read derived values refresh.
    private(set) var revision = 0
    var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }

    @ObservationIgnored let store: IndexStore
    @ObservationIgnored private let library: LibraryProviding
    @ObservationIgnored private let analyzer: Analyzing
    @ObservationIgnored private let judge: Judging
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored let timer = StageTimer()
    private(set) var titling = false
    private(set) var titlingID: String?
    private(set) var titled = 0

    init(store: IndexStore, library: LibraryProviding, analyzer: Analyzing, judge: Judging) {
        self.store = store; self.library = library; self.analyzer = analyzer; self.judge = judge
    }

    var analyzerTimer: StageTimer? { (analyzer as? VisionAnalyzer)?.timer }
    var counts: [Bucket: Int] { store.items.values.reduce(into: [:]) { $0[$1.bucket, default: 0] += 1 } }
    var bytesByBucket: [Bucket: Int64] {
        store.items.values.reduce(into: [:]) { acc, i in if i.record.isLocal { acc[i.bucket, default: 0] += i.record.fileBytes } }
    }

    func cancel() { cancelled = true }

    /// Signals that the index changed outside a scan (keep, delete, lock) so views refresh.
    func touch() { revision += 1 }

    func scan(limit: Int? = nil) async {
        guard !running else { return }
        running = true; cancelled = false
        defer { running = false }
        let start = Date()
        timer.reset()
        events = []
        let all = await library.assetIDs()
        let ids = limit.map { Array(all.prefix($0)) } ?? all
        let present = Set(all)
        store.remove(ids: store.items.keys.filter { !present.contains($0) })   // deleted elsewhere since last scan
        let whatsApp = await library.whatsAppAssetIDs()
        let todo = ids.filter { store.items[$0] == nil }
        total = ids.count
        done = ids.count - todo.count

        for offset in stride(from: 0, to: todo.count, by: ScanConfig.chunk) where !cancelled {
            let chunk = Array(todo[offset..<min(offset + ScanConfig.chunk, todo.count)])
            let loaded = await loadAndAnalyze(chunk, whatsApp: whatsApp)
            await judgeAndStore(loaded)
            done += chunk.count
            revision += 1
            elapsed = Date().timeIntervalSince(start)
            if (offset / ScanConfig.chunk) % 10 == 9 { store.save() }
        }
        await markDuplicates(ids: ids)
        store.save()
        waiting = todo.filter { store.items[$0] == nil }.count
        revision += 1
        elapsed = Date().timeIntervalSince(start)
    }

    // MARK: - Steps

    private struct Analyzed: @unchecked Sendable { var record: PhotoRecord; var vision: VisionResult; var hasImage = false }

    private func loadAndAnalyze(_ ids: [String], whatsApp: Set<String>) async -> [Analyzed] {
        let library = library, analyzer = analyzer, timer = timer
        return await withTaskGroup(of: Analyzed?.self) { group in
            var out: [Analyzed] = []
            var next = 0
            func add() {
                guard next < ids.count else { return }
                let id = ids[next]; next += 1
                group.addTask {
                    let t0 = Date()
                    guard let asset = await library.load(id: id, whatsAppIDs: whatsApp), !asset.retryLater else { return nil }   // deleted mid-scan, or not saved yet
                    timer.add("load", Date().timeIntervalSince(t0))
                    var r = asset.record
                    var v = VisionResult()
                    if let img = asset.image {
                        v = await analyzer.analyze(img, textHeavy: r.isScreenshot)
                        r.ocrText = v.ocrText; r.labels = v.labels; r.labelScores = v.labelScores; r.faceCount = v.faceCount
                        r.barcodePayloads = v.barcodes; r.blurScore = r.isVideo ? nil : v.blurScore
                    }
                    return Analyzed(record: r, vision: v, hasImage: asset.image != nil)
                }
            }
            for _ in 0..<ScanConfig.concurrency { add() }
            while let result = await group.next() {
                if let result { out.append(result) }
                add()
            }
            return out
        }
    }

    /// Rules only: the scan never waits for the model.
    private func judgeAndStore(_ items: [Analyzed]) async {
        let now = Date()
        for a in items {
            let hits = scanText(a.record.ocrText, barcodes: a.record.barcodePayloads)
            var item = IndexedItem(record: a.record, verdict: ruleVerdict(a.record, hits: hits, now: now), dHash: a.vision.dHash,
                                   faceQuality: a.vision.faceQuality, blurScore: a.vision.blurScore)
            item.hasImage = a.hasImage
            store.put(item, featurePrint: a.vision.featurePrint)
            lastEvent = (a.record.id, item.bucket)
            events.append((a.record.id, item.bucket))
        }
    }

    /// Screenshots whose verdict depends on time (OTPs, tickets) are re-judged on launch, so "expired" stays true to the clock.
    func rejudgeTimeSensitive() async {
        let now = Date()
        var changed = false
        for (id, item) in store.items where item.record.isScreenshot && item.userKept != true && item.dupGroup == nil {
            let v = ruleVerdict(item.record, hits: scanText(item.record.ocrText, barcodes: item.record.barcodePayloads), now: now)
            if v.reason != item.verdict.reason || v.verdict != item.verdict.verdict { store.update(id) { $0.verdict = v }; changed = true }
        }
        if changed { store.save(); revision += 1 }
    }

    /// Re-applies the current rules to every stored item (no rescan: OCR, labels and metadata are already stored), then re-groups duplicates.
    func rejudgeAll() async {
        let now = Date()
        for (id, item) in store.items where item.userKept != true {
            let hits = scanText(item.record.ocrText, barcodes: item.record.barcodePayloads)
            store.update(id) { $0.verdict = ruleVerdict(item.record, hits: hits, now: now) }
        }
        await markDuplicates(ids: Array(store.items.keys))
        store.save()
        revision += 1
    }

    /// Background pass: on-device titles for vague, non-sensitive items, highest-value buckets first. Safe to cancel any time.
    func titlePending(order: [Bucket] = [.memesDownloads, .otherScreenshots, .usefulScreenshots, .forwards, .blurry, .realPhotos], limit: Int = .max) async {
        guard !titling else { return }
        titling = true
        defer { titling = false; titlingID = nil; store.save() }
        let pending = store.items.values.filter { wantsNote($0.verdict) && !$0.record.isVideo }
        let ranked = pending.sorted { (order.firstIndex(of: $0.bucket) ?? 99) < (order.firstIndex(of: $1.bucket) ?? 99) }.prefix(limit)
        let rows = Array(ranked)
        for b in stride(from: 0, to: rows.count, by: PromptConfig.batchSize) where !cancelled {
            let batch = Array(rows[b..<min(b + PromptConfig.batchSize, rows.count)])
            titlingID = batch.first?.record.id
            let t0 = Date()
            let notes = await judge.notes(for: batch.map { ($0.record, scanText($0.record.ocrText, barcodes: $0.record.barcodePayloads)) })
            timer.add("model", Date().timeIntervalSince(t0))
            let byID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for item in batch {
                store.update(item.record.id) {
                    $0.verdict = merge(rule: $0.verdict, note: byID[item.record.id], ocrText: $0.record.ocrText, topLabel: $0.record.labels.first)
                    if !wantsNote($0.verdict) { titled += 1 }
                }
            }
            revision += 1
        }
    }

    private struct DupInput: Sendable { let id: String; let hash: UInt64; let w: Int; let h: Int; let camera: Bool }

    /// Exact copies (near-identical hash and same size, or feature distance ≤ 0.08) become junk except the best copy;
    /// similar camera photos (distance ≤ 0.40) become review. Grouping runs off the main thread.
    func markDuplicates(ids: [String]) async {
        // Regroup from scratch; a photo that is no longer in any group gets its own verdict back.
        let now = Date()
        for id in ids {
            guard let it = store.items[id], it.dupGroup != nil || it.verdict.junkType == .duplicate else { continue }
            store.update(id) {
                $0.dupGroup = nil
                if $0.verdict.junkType == .duplicate, $0.userKept != true {
                    $0.verdict = ruleVerdict($0.record, hits: scanText($0.record.ocrText, barcodes: $0.record.barcodePayloads), now: now)
                }
            }
        }
        // Photos whose pixels couldn't be read all share an empty fingerprint; never call them copies of each other.
        let inputs = ids.compactMap { store.items[$0] }.filter { !$0.record.isVideo && $0.verdict.sensitive == nil && $0.readable }
            .map { DupInput(id: $0.record.id, hash: $0.dHash, w: $0.record.pixelWidth, h: $0.record.pixelHeight, camera: $0.record.cameraMake != nil) }
        let dir = store.directory
        let (exact, near) = await Task.detached(priority: .userInitiated) { () -> ([[String]], [[String]]) in
            Self.groups(inputs, dir: dir)
        }.value
        for g in exact { apply(group: g, exact: true) }
        for g in near { apply(group: g, exact: false) }
    }

    nonisolated private static func groups(_ inputs: [DupInput], dir: URL) -> ([[String]], [[String]]) {
        let byID = Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, $0) })
        var prints: [String: Data?] = [:]
        func fp(_ id: String) -> Data? {
            if let p = prints[id] { return p }
            let d = try? Data(contentsOf: IndexStore.printURL(in: dir, id: id)); prints[id] = d; return d
        }
        func distance(_ a: String, _ b: String, exactOnly: Bool) -> Float {
            guard let x = byID[a], let y = byID[b] else { return .infinity }
            if hamming(x.hash, y.hash) <= ScanConfig.exactHamming, x.w == y.w, x.h == y.h { return 0 }
            guard let fx = fp(a), let fy = fp(b), let d = VisionAnalyzer.distance(fx, fy) else { return .infinity }
            return exactOnly && d > SimilarityConfig.duplicateMaxDistance ? .infinity : d
        }
        let tree = BKTree()
        for i in inputs { tree.insert(i.hash, id: i.id) }
        var seen = Set<String>(), exact: [[String]] = [], near: [[String]] = []
        for i in inputs where !seen.contains(i.id) {
            let candidates = Array(Set(tree.query(i.hash, maxDistance: ScanConfig.candidateHamming)).subtracting(seen))
            guard candidates.count > 1 else { continue }
            for g in groupDuplicates(ids: candidates, distance: { distance($0, $1, exactOnly: true) }, maxDistance: SimilarityConfig.duplicateMaxDistance) {
                exact.append(g); seen.formUnion(g)
            }
            for g in groupDuplicates(ids: candidates, distance: { distance($0, $1, exactOnly: false) }, maxDistance: SimilarityConfig.maxDistance)
            where g.allSatisfy({ !seen.contains($0) && byID[$0]?.camera == true }) {
                near.append(g); seen.formUnion(g)
            }
        }
        return (exact, near)
    }

    private func apply(group: [String], exact: Bool) {
        let members = group.compactMap { store.items[$0] }
        let best = members[bestCopyIndex(members.map {
            CopyQuality(sharpness: min(1, ($0.blurScore ?? 0) / 0.5), faceQuality: $0.faceQuality, pixels: $0.record.pixelWidth * $0.record.pixelHeight)
        })].record.id
        for m in members { store.update(m.record.id) { $0.dupGroup = best } }
        for m in members where m.record.id != best && !m.record.isFavorite && m.userKept != true {
            store.update(m.record.id) {
                $0.verdict.junkType = .duplicate
                $0.verdict.verdict = exact ? .junk : .review
                $0.verdict.reason = exact ? "Exact copy — keeping the best one" : "Similar to \(members.count - 1) other photo\(members.count > 2 ? "s" : "")"
            }
        }
    }
}
