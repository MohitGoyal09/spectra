import Photos
import ImageIO
import TidyCore

/// One photo or video ready for analysis: metadata record plus a ≤1024 px image (nil if not on this iPhone or timed out).
struct LoadedAsset: @unchecked Sendable {
    var record: PhotoRecord
    var image: CGImage?
    /// The photo is on this iPhone but iOS hadn't finished saving it (just taken or downloaded): scan it next time.
    var retryLater = false
}

protocol LibraryProviding: Sendable {
    func assetIDs() async -> [String]
    func whatsAppAssetIDs() async -> Set<String>
    func load(id: String, whatsAppIDs: Set<String>) async -> LoadedAsset?
}

enum LibraryConfig {
    static let imageSide = 512
    static let textImageSide = 1024
    static let requestTimeout: Duration = .seconds(2)
}

final class PhotoLibraryService: LibraryProviding {
    func requestAccess() async -> PHAuthorizationStatus { await PHPhotoLibrary.requestAuthorization(for: .readWrite) }

    func assetIDs() async -> [String] {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let r = PHAsset.fetchAssets(with: o)
        var ids: [String] = []
        ids.reserveCapacity(r.count)
        r.enumerateObjects { a, _, _ in if a.mediaType == .image || a.mediaType == .video { ids.append(a.localIdentifier) } }
        return FilmScope.filter(ids)
    }

    func whatsAppAssetIDs() async -> Set<String> {
        var ids = Set<String>()
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { c, _, _ in
            guard c.localizedTitle?.localizedCaseInsensitiveContains("whatsapp") == true else { return }
            PHAsset.fetchAssets(in: c, options: nil).enumerateObjects { a, _, _ in ids.insert(a.localIdentifier) }
        }
        return ids
    }

    func load(id: String, whatsAppIDs: Set<String>) async -> LoadedAsset? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        var r = PhotoRecord(id: id, createdAt: asset.creationDate ?? .distantPast)
        r.isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        r.isVideo = asset.mediaType == .video
        r.isScreenRecording = asset.mediaSubtypes.contains(.videoScreenRecording)
        r.durationSec = r.isVideo ? asset.duration : nil
        r.pixelWidth = asset.pixelWidth
        r.pixelHeight = asset.pixelHeight
        r.isFavorite = asset.isFavorite
        r.sourceAlbums = whatsAppIDs.contains(id) ? ["WhatsApp"] : []
        let resource = PHAssetResource.assetResources(for: asset).first
        r.fileBytes = (resource?.value(forKey: "fileSize") as? Int64) ?? 0
        r.isLocal = (resource?.value(forKey: "locallyAvailable") as? Bool) ?? true

        if r.isVideo {
            return LoadedAsset(record: r, image: await posterFrame(asset))
        }
        guard let data = await imageData(asset) else {
            if r.isLocal { return LoadedAsset(record: r, image: nil, retryLater: true) }
            return LoadedAsset(record: r, image: await posterFrame(asset))
        }
        Self.applyMetadata(data, to: &r)
        // 1024 px for everything: ID numbers on photographed cards and cheques need it; accurate OCR still runs only on text-heavy images.
        return LoadedAsset(record: r, image: Self.thumbnail(data, side: LibraryConfig.textImageSide))
    }

    // MARK: - Helpers

    private func imageData(_ asset: PHAsset) async -> Data? {
        await withTimeout {
            await withCheckedContinuation { cont in
                let o = PHImageRequestOptions()
                o.isNetworkAccessAllowed = false
                o.version = .current
                o.deliveryMode = .highQualityFormat
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: o) { data, _, _, _ in cont.resume(returning: data) }
            }
        }
    }

    private func posterFrame(_ asset: PHAsset) async -> CGImage? {
        await withTimeout {
            await withCheckedContinuation { cont in
                let o = PHImageRequestOptions()
                o.isNetworkAccessAllowed = false
                o.deliveryMode = .fastFormat
                o.resizeMode = .fast
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 512, height: 512), contentMode: .aspectFit, options: o) { img, _ in
                    cont.resume(returning: img?.cgImage)
                }
            }
        }
    }

    private func withTimeout<T: Sendable>(_ work: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { g in
            g.addTask { await work() }
            g.addTask { try? await Task.sleep(for: LibraryConfig.requestTimeout); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
    }

    static func thumbnail(_ data: Data, side: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: side,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func applyMetadata(_ data: Data, to r: inout PhotoRecord) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let tiff = props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        r.cameraMake = tiff?[kCGImagePropertyTIFFMake] as? String
        r.cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String
        var p = ProvenanceInput(software: tiff?[kCGImagePropertyTIFFSoftware] as? String)
        if let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil) {
            p.digitalSourceType = CGImageMetadataCopyStringValueWithPath(meta, nil, "Iptc4xmpExt:DigitalSourceType" as CFString) as String?
            p.creatorTool = CGImageMetadataCopyStringValueWithPath(meta, nil, "xmp:CreatorTool" as CFString) as String?
        }
        p.hasC2PA = data.prefix(2_000_000).range(of: Data("c2pa".utf8)) != nil
        r.provenance = p
    }
}
