import XCTest
import CoreGraphics
import TidyCore
@testable import TidyRoll

private final class FakeLibrary: LibraryProviding, @unchecked Sendable {
    var ids: [String]
    var missing: Set<String> = []
    var noImage: Set<String> = []
    var notReady: Set<String> = []
    var records: [String: PhotoRecord] = [:]
    private(set) var loads = 0
    init(_ ids: [String]) { self.ids = ids }
    func assetIDs() async -> [String] { ids }
    func whatsAppAssetIDs() async -> Set<String> { [] }
    func load(id: String, whatsAppIDs: Set<String>) async -> LoadedAsset? {
        loads += 1
        guard !missing.contains(id) else { return nil }
        let r = records[id] ?? PhotoRecord(id: id, createdAt: Date())
        if notReady.contains(id) { return LoadedAsset(record: r, image: nil, retryLater: true) }
        return LoadedAsset(record: r, image: noImage.contains(id) ? nil : FakeImage.make())
    }
}

private enum FakeImage {
    static func make() -> CGImage {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}

private struct FakeAnalyzer: Analyzing {
    var hashes: [String: UInt64] = [:]
    var text: String = ""
    func analyze(_ image: CGImage, textHeavy: Bool) async -> VisionResult {
        var v = VisionResult(); v.ocrText = text; v.dHash = 0xABCD; return v
    }
}

@MainActor private final class FakeJudge: Judging {
    var calls = 0
    func notes(for batch: [(PhotoRecord, RuleHits)]) async -> [ModelNote] { calls += 1; return [] }
}

@MainActor final class ScannerTests: XCTestCase {
    private func makeStore() -> IndexStore {
        IndexStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    func testResumeSkipsIndexed() async {
        let lib = FakeLibrary(["a", "b", "c"])
        let store = makeStore()
        let s = Scanner(store: store, library: lib, analyzer: FakeAnalyzer(), judge: FakeJudge())
        await s.scan()
        XCTAssertEqual(lib.loads, 3)
        await s.scan()
        XCTAssertEqual(lib.loads, 3, "already-indexed items are not loaded again")
        XCTAssertEqual(store.items.count, 3)
    }

    func testDeletedDuringScanIsSkipped() async {
        let lib = FakeLibrary(["a", "b"]); lib.missing = ["b"]
        let store = makeStore()
        await Scanner(store: store, library: lib, analyzer: FakeAnalyzer(), judge: FakeJudge()).scan()
        XCTAssertEqual(Set(store.items.keys), ["a"])
    }

    func testDeletedSinceLastScanIsRemoved() async {
        let lib = FakeLibrary(["a", "b"])
        let store = makeStore()
        let s = Scanner(store: store, library: lib, analyzer: FakeAnalyzer(), judge: FakeJudge())
        await s.scan()
        lib.ids = ["a"]
        await s.scan()
        XCTAssertEqual(Set(store.items.keys), ["a"])
    }

    func testMissingImageStillIndexedByRules() async {
        let lib = FakeLibrary(["a"]); lib.noImage = ["a"]
        let store = makeStore()
        await Scanner(store: store, library: lib, analyzer: FakeAnalyzer(), judge: FakeJudge()).scan()
        XCTAssertEqual(store.items["a"]?.verdict.source, .rules)
    }

    func testScanNeverCallsTheModel() async {
        let judge = FakeJudge()
        await Scanner(store: makeStore(), library: FakeLibrary((0..<30).map { "p\($0)" }), analyzer: FakeAnalyzer(), judge: judge).scan()
        XCTAssertEqual(judge.calls, 0)
    }

    func testTitlingSkipsSensitive() async {
        let lib = FakeLibrary(["id", "x"])
        let judge = FakeJudge()
        let store = makeStore()
        let s = Scanner(store: store, library: lib, analyzer: FakeAnalyzer(text: "ABCDE1234F"), judge: judge)
        await s.scan()
        await s.titlePending()
        XCTAssertEqual(judge.calls, 0, "PAN text makes every item sensitive, so nothing reaches the model")
    }

    func testExactDuplicatesKeepOneCopy() async {
        let lib = FakeLibrary(["a", "b"])
        for id in ["a", "b"] { var r = PhotoRecord(id: id, createdAt: Date()); r.pixelWidth = 100; r.pixelHeight = 100; lib.records[id] = r }
        let store = makeStore()
        await Scanner(store: store, library: lib, analyzer: FakeAnalyzer(), judge: FakeJudge()).scan()
        let junk = store.items.values.filter { $0.verdict.junkType == .duplicate && $0.verdict.verdict == .junk }
        XCTAssertEqual(junk.count, 1)
    }

    func testNonLocalBytesNotCountedAsFreeable() async {
        let lib = FakeLibrary(["a"])
        var r = PhotoRecord(id: "a", createdAt: Date()); r.fileBytes = 5_000_000; r.isLocal = false; lib.records["a"] = r
        let s = Scanner(store: makeStore(), library: lib, analyzer: FakeAnalyzer(), judge: FakeJudge())
        await s.scan()
        XCTAssertEqual(s.bytesByBucket.values.reduce(0, +), 0)
    }

    func testPhotosWithoutAnImageAreNeverDuplicates() async {
        let lib = FakeLibrary(["a", "b", "c"])
        lib.noImage = ["a", "b", "c"]          // e.g. iCloud-only originals that couldn't be read
        for id in lib.ids { var r = PhotoRecord(id: id, createdAt: Date()); r.pixelWidth = 4000; r.pixelHeight = 3000; lib.records[id] = r }
        let store = makeStore()
        let s = Scanner(store: store, library: lib, analyzer: FakeAnalyzer(), judge: FakeJudge())
        await s.scan()
        XCTAssertTrue(store.items.values.allSatisfy { $0.dupGroup == nil }, "unread photos share an empty fingerprint, not content")
        XCTAssertTrue(store.items.values.allSatisfy { $0.verdict.junkType != .duplicate })
    }

    func testNotReadyPhotoIsRetriedNotStoredBlank() async {
        let lib = FakeLibrary(["a", "b"])
        lib.notReady = ["b"]
        let store = makeStore()
        let s = Scanner(store: store, library: lib, analyzer: FakeAnalyzer(), judge: FakeJudge())
        await s.scan()
        XCTAssertNil(store.items["b"], "a photo iOS hasn't finished saving is retried later")
        XCTAssertEqual(s.waiting, 1, "the app knows to scan again")
        lib.notReady = []
        await s.scan()
        XCTAssertNotNil(store.items["b"])
    }

    func testStaleDuplicateGroupsAreCleared() async {
        let lib = FakeLibrary(["a", "b"])
        let store = makeStore()
        let s = Scanner(store: store, library: lib, analyzer: FakeAnalyzer(), judge: FakeJudge())
        await s.scan()
        store.update("a") { $0.dupGroup = "zzz" }
        await s.markDuplicates(ids: ["a", "b"])
        XCTAssertNotEqual(store.items["a"]?.dupGroup, "zzz")
    }
}
