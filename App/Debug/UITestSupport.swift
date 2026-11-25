#if DEBUG
import SwiftUI
import Photos
import AVFoundation

/// UI-test helpers, debug builds only, triggered by launch arguments from TidyRollUITests:
/// `-uitest-seed` adds 3 test photos dated 1 Jan 2001; `-uitest-cleanup` deletes them (and copies of them) plus
/// smart albums made during the run; `-uitest-dark` forces dark mode. The user's own photos are never touched.
enum UITestSupport {
    static let seedDate = Date(timeIntervalSinceReferenceDate: 0)       // 2001-01-01 00:00 UTC
    private static let startKey = "uitestStart"
    static var args: [String] { ProcessInfo.processInfo.arguments }
    static var scheme: ColorScheme? { args.contains("-uitest-dark") ? .dark : args.contains("-uitest-light") ? .light : nil }

    @MainActor static func run(_ model: AppModel) async {
        if args.contains("-uitest-real-ai") { model.judge.simulateNoOnDevice = false }   // undo a demo switch a failed run left on
        if args.contains("-uitest-seed") { await seed() }
        if args.contains("-uitest-cleanup") { await cleanup(model) }
        if args.contains("-film-reset") { await FilmImport.reset() }
        if args.contains("-film-import") { await FilmImport.run(); _ = await DemoKit.add() }
    }

    /// Only assets dated within a minute of the seed date: the seeded photos and their duplicates.
    nonisolated static func testAssets() -> PHFetchResult<PHAsset> {
        let o = PHFetchOptions(); o.includeHiddenAssets = true
        o.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", seedDate as NSDate, seedDate.addingTimeInterval(60) as NSDate)
        return PHAsset.fetchAssets(with: o)
    }

    nonisolated private static func seed() async {
        UserDefaults.standard.set(Date(), forKey: startKey)
        guard testAssets().count == 0 else { return }
        let images = [render(["UITEST RECEIPT", "Swiggy order", "Total Rs 450"], .white),
                      render(["UITEST WIFI", "Network: CafeBlue", "Password: tea4two"], .systemYellow),
                      render(["UITEST"], .systemRed),
                      render(["UITEST BOARDING PASS", "IndiGo 6E 2134 PNR X7K2QP", "Delhi to Goa 14 Dec 2026 06:45"], .systemTeal)]
        let video = makeVideo()
        try? await PHPhotoLibrary.shared().performChanges {
            for (i, img) in images.enumerated() {
                PHAssetChangeRequest.creationRequestForAsset(from: img).creationDate = seedDate.addingTimeInterval(Double(i))
            }
            if let video {
                let r = PHAssetCreationRequest.forAsset()
                r.addResource(with: .video, fileURL: video, options: nil)
                r.creationDate = seedDate.addingTimeInterval(10)
            }
        }
        if let video { try? FileManager.default.removeItem(at: video) }
    }

    @MainActor private static func cleanup(_ model: AppModel) async {
        let since = UserDefaults.standard.object(forKey: startKey) as? Date ?? .distantFuture
        let made = model.rules.rules.filter { $0.created >= since || $0.spec.name.lowercased().hasPrefix("uitest") }
        let albumIDs = made.compactMap(\.albumID)
        let titled = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var extra: [String] = []
        titled.enumerateObjects { c, _, _ in if c.localizedTitle?.hasPrefix("UITest") == true { extra.append(c.localIdentifier) } }
        for r in made { model.rules.remove(r.id) }
        await deleteTestItems(albums: albumIDs + extra)
        model.scanner.touch()
    }

    /// PhotoKit runs change blocks on its own queue, so this must not be main-actor isolated.
    nonisolated private static func deleteTestItems(albums ids: [String]) async {
        try? await PHPhotoLibrary.shared().performChanges {
            let assets = testAssets()
            if assets.count > 0 { PHAssetChangeRequest.deleteAssets(assets) }
            let albums = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: ids, options: nil)
            if albums.count > 0 { PHAssetCollectionChangeRequest.deleteAssetCollections(albums) }
        }
    }

    /// A 2-second 4K H.264 clip, so "Compress Video" has something to shrink.
    nonisolated private static func makeVideo() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-\(UUID().uuidString).mov")
        let (w, h) = (3840, 2160)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 40_000_000]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData { usleep(2000) }
            guard let pool = adaptor.pixelBufferPool else { return nil }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let pb = buffer else { return nil }
            CVPixelBufferLockBaseAddress(pb, [])
            let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(pb)
            for y in 0..<h { let v = UInt8((y + frame * 40) % 256); memset(base + y * row, Int32(v), row) }   // moving gradient
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        return writer.status == .completed ? url : nil
    }

    nonisolated private static func render(_ lines: [String], _ bg: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { ctx in
            bg.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 90), .foregroundColor: UIColor.black]
            for (i, l) in lines.enumerated() { (l as NSString).draw(at: CGPoint(x: 80, y: 120 + i * 200), withAttributes: attrs) }
        }
    }
}
#endif
