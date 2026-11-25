import AVFoundation
import Photos
import CoreMedia

/// Shrinks videos on this iPhone: re-encodes to HEVC at up to 1080p, saves each copy with the original's date, place and
/// favourite, and moves the originals to Recently Deleted, all in one change, so iOS asks once and nothing is lost if
/// the user says no. Skips videos that are already compact or wouldn't get at least 15% smaller.
enum VideoCompressor {
    struct Result: Sendable { var saved: Int64 = 0; var compressed = 0; var alreadyCompact = 0; var failed = 0; var declined = false }

    private struct Prepared: @unchecked Sendable {
        let id: String, file: URL, saved: Int64
        let date: Date?, location: CLLocation?, favorite: Bool
    }

    private static let minSaving = 0.15

    /// Encodes every video first, then saves all copies and removes the originals in one change (one iOS prompt).
    nonisolated static func compress(_ ids: [String], progress: @escaping @Sendable (Int) -> Void) async -> Result {
        var result = Result()
        var ready: [Prepared] = []
        for (i, id) in ids.enumerated() {
            switch await prepare(id) {
            case .some(.some(let p)): ready.append(p)
            case .some(.none): result.alreadyCompact += 1
            case .none: result.failed += 1
            }
            progress(i + 1)
        }
        defer { for p in ready { try? FileManager.default.removeItem(at: p.file) } }
        guard !ready.isEmpty else { return result }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for p in ready {
                    let req = PHAssetCreationRequest.forAsset()
                    req.addResource(with: .video, fileURL: p.file, options: nil)
                    req.creationDate = p.date; req.location = p.location; req.isFavorite = p.favorite
                }
                PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ready.map(\.id), options: nil))
            }
            result.compressed = ready.count
            result.saved = ready.reduce(0) { $0 + $1.saved }
        } catch { result.declined = true }
        return result
    }

    /// nil = failed; .some(nil) = already compact; .some(file) = encoded copy ready to save.
    nonisolated private static func prepare(_ id: String) async -> Prepared?? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject, asset.mediaType == .video else { return nil }
        let originalBytes = (PHAssetResource.assetResources(for: asset).first?.value(forKey: "fileSize") as? Int64) ?? 0
        guard let av = await avAsset(asset) else { return nil }
        guard await needsCompression(av, width: asset.pixelWidth, height: asset.pixelHeight) else { return .some(nil) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("compress-\(UUID().uuidString).mov")
        guard let session = AVAssetExportSession(asset: av, presetName: AVAssetExportPresetHEVC1920x1080) else { return nil }
        do { try await session.export(to: out, as: .mov) } catch { return nil }
        let newBytes = ((try? FileManager.default.attributesOfItem(atPath: out.path)[.size]) as? NSNumber)?.int64Value ?? 0
        guard newBytes > 0, originalBytes == 0 || Double(newBytes) < Double(originalBytes) * (1 - minSaving) else {
            try? FileManager.default.removeItem(at: out); return .some(nil)
        }
        return .some(Prepared(id: id, file: out, saved: max(0, originalBytes - newBytes),
                              date: asset.creationDate, location: asset.location, favorite: asset.isFavorite))
    }

    /// Larger than 1080p, or not HEVC: worth re-encoding.
    nonisolated private static func needsCompression(_ av: AVAsset, width: Int, height: Int) async -> Bool {
        if min(width, height) > 1080 { return true }
        guard let track = try? await av.loadTracks(withMediaType: .video).first,
              let formats = try? await track.load(.formatDescriptions), let f = formats.first else { return false }
        return CMFormatDescriptionGetMediaSubType(f) != kCMVideoCodecType_HEVC
    }

    nonisolated private static func avAsset(_ asset: PHAsset) async -> AVAsset? {
        let box = await withCheckedContinuation { (c: CheckedContinuation<UncheckedBox<AVAsset?>, Never>) in
            let o = PHVideoRequestOptions(); o.isNetworkAccessAllowed = true; o.deliveryMode = .highQualityFormat; o.version = .current
            PHImageManager.default().requestAVAsset(forVideo: asset, options: o) { av, _, _ in c.resume(returning: UncheckedBox(av)) }
        }
        return box.value
    }
}
