import XCTest
import Photos
import TidyCore
@testable import TidyRoll

/// Diagnostic: loads the UI-test photos (dated 2001) exactly as a scan does and prints what Vision reads.
final class SeedDebugTests: XCTestCase {
    func testLoadSeededItems() async throws {
        let o = PHFetchOptions(); o.includeHiddenAssets = true
        o.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", Date(timeIntervalSinceReferenceDate: 0) as NSDate, Date(timeIntervalSinceReferenceDate: 60) as NSDate)
        var ids: [String] = []
        PHAsset.fetchAssets(with: o).enumerateObjects { a, _, _ in ids.append(a.localIdentifier) }
        try XCTSkipIf(ids.isEmpty, "No seeded photos")
        let lib = PhotoLibraryService(), vision = VisionAnalyzer()
        for id in ids {
            let t0 = Date()
            let loaded = await lib.load(id: id, whatsAppIDs: [])
            let img = loaded?.image
            var line = "SEED \(id.prefix(8)) load=\(String(format: "%.1f", Date().timeIntervalSince(t0)))s retry=\(loaded?.retryLater ?? false) img=\(img.map { "\($0.width)x\($0.height)" } ?? "nil") local=\(loaded?.record.isLocal ?? false)"
            if let img {
                let v = await vision.analyze(img, textHeavy: false)
                line += " labels=\(v.labels) ocr=\(v.ocrText.prefix(50))"
            }
            print(line)
        }
    }
}
