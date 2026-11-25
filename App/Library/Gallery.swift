import Photos
import AVFoundation
import UniformTypeIdentifiers
import ImageIO
import UIKit
import CoreLocation

/// Gallery operations on the user's library (PhotoKit). Deletes always show the iOS confirmation and go to Recently Deleted.
struct AlbumInfo: Identifiable, Hashable { let id: String; let title: String; let count: Int; let coverID: String?; let symbol: String }

struct AssetInfo {
    var date: Date?
    var location: CLLocation?
    var pixelWidth = 0, pixelHeight = 0
    var bytes: Int64 = 0
    var filename = ""
    var isVideo = false, isLive = false, isFavorite = false
    var duration: TimeInterval = 0
}

@MainActor enum Gallery {
    static func asset(_ id: String) -> PHAsset? { PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject }

    static func info(_ id: String) -> AssetInfo? {
        guard let a = asset(id) else { return nil }
        let res = PHAssetResource.assetResources(for: a).first
        return AssetInfo(date: a.creationDate, location: a.location, pixelWidth: a.pixelWidth, pixelHeight: a.pixelHeight,
                         bytes: (res?.value(forKey: "fileSize") as? Int64) ?? 0, filename: res?.originalFilename ?? "",
                         isVideo: a.mediaType == .video, isLive: a.mediaSubtypes.contains(.photoLive), isFavorite: a.isFavorite,
                         duration: a.duration)
    }

    // Change requests must not be main-actor isolated: PhotoKit runs the change block on its own queue
    // (pattern from Apple's "Browsing and Modifying Photo Albums" sample). Each block re-fetches by id inside.

    nonisolated static func setFavorite(_ id: String, _ on: Bool) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
            PHAssetChangeRequest(for: a).isFavorite = on
        }
    }

    /// Moves items to Recently Deleted after the system confirmation. Returns false if the user cancelled or nothing matched.
    @discardableResult
    nonisolated static func delete(_ ids: [String]) async -> Bool {
        guard !ids.isEmpty, PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count > 0 else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
            }
            return true
        } catch { return false }
    }

    /// Moves items into Apple's Face ID–protected Hidden album.
    nonisolated static func hide(_ ids: [String]) async -> Bool {
        guard !ids.isEmpty else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { a, _, _ in PHAssetChangeRequest(for: a).isHidden = true }
            }
            return true
        } catch { return false }
    }

    /// Video for playback. PhotoKit calls back on its own queue, so this must not be main-actor isolated.
    nonisolated static func playerItem(_ id: String) async -> AVPlayerItem? {
        guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let item = await withCheckedContinuation { (cont: CheckedContinuation<UncheckedBox<AVPlayerItem?>, Never>) in
            let o = PHVideoRequestOptions(); o.isNetworkAccessAllowed = true; o.deliveryMode = .automatic
            PHImageManager.default().requestPlayerItem(forVideo: a, options: o) { item, _ in cont.resume(returning: UncheckedBox(item)) }
        }
        return item.value
    }

    /// Copies each item's original file (no decoding) to a temp folder for the share sheet, downloading from iCloud if needed.
    /// Runs in parallel; returns the files in the same order as `ids`.
    /// `asJPEG` re-saves HEIC photos as JPEG (metadata kept) for people and sites that can't open HEIC.
    nonisolated static func exportForSharing(_ ids: [String], asJPEG: Bool = false) async -> [URL] {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids.prefix(50)), options: nil)
        var resources: [(Int, UncheckedBox<PHAssetResource>)] = []
        assets.enumerateObjects { asset, i, _ in
            let rs = PHAssetResource.assetResources(for: asset)
            if let r = rs.first(where: { $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto }) ?? rs.first {
                resources.append((i, UncheckedBox(r)))
            }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return await withTaskGroup(of: (Int, URL?).self) { group in
            for (i, box) in resources {
                group.addTask {
                    let res = box.value
                    let url = dir.appendingPathComponent(res.originalFilename)
                    let o = PHAssetResourceRequestOptions(); o.isNetworkAccessAllowed = true
                    let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                        PHAssetResourceManager.default().writeData(for: res, toFile: url, options: o) { c.resume(returning: $0 == nil) }
                    }
                    guard ok else { return (i, nil) }
                    return (i, asJPEG ? (jpegCopy(of: url) ?? url) : url)
                }
            }
            var out: [(Int, URL)] = []
            for await (i, url) in group { if let url { out.append((i, url)) } }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Re-saves a HEIC/HEIF file as JPEG next to it, keeping EXIF and location; nil for anything else.
    nonisolated static func jpegCopy(of url: URL) -> URL? {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .heic) || type.conforms(to: .heif),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let out = url.deletingPathExtension().appendingPathExtension("jpg")
        guard let dst = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImageFromSource(dst, src, 0, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return out
    }

    /// Display image at up to `maxPixel` on its long side (downloads from iCloud if needed).
    nonisolated static func image(_ id: String, maxPixel: CGFloat) async -> UIImage? {
        guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let box = await withCheckedContinuation { (c: CheckedContinuation<UncheckedBox<UIImage?>, Never>) in
            let o = PHImageRequestOptions(); o.isNetworkAccessAllowed = true; o.deliveryMode = .highQualityFormat; o.isSynchronous = false
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: maxPixel, height: maxPixel), contentMode: .aspectFit, options: o) {
                img, _ in c.resume(returning: UncheckedBox(img))
            }
        }
        return box.value
    }

    nonisolated static func setDate(_ id: String, _ date: Date) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
                PHAssetChangeRequest(for: a).creationDate = date
            }
            return true
        } catch { return false }
    }

    nonisolated static func setLocation(_ id: String, _ location: CLLocation?) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
                PHAssetChangeRequest(for: a).location = location
            }
            return true
        } catch { return false }
    }

    /// Saves a copy of the original as a new item in the library.
    nonisolated static func duplicate(_ id: String) async -> Bool {
        guard let url = await exportForSharing([id]).first,
              let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return false }
        let isVideo = a.mediaType == .video
        let date = a.creationDate, loc = a.location
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
                req.creationDate = date
                req.location = loc
            }
            return true
        } catch { return false }
    }

    nonisolated static func add(_ ids: [String], toAlbum albumID: String) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else { return }
                PHAssetCollectionChangeRequest(for: album)?.addAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
            }
            return true
        } catch { return false }
    }

    nonisolated static func remove(_ ids: [String], fromAlbum albumID: String) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else { return }
                PHAssetCollectionChangeRequest(for: album)?.removeAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
            }
            return true
        } catch { return false }
    }

    /// Adds items to an album with this title, creating it if needed. Returns the album id.
    nonisolated static func addToAlbum(title: String, ids: [String]) async -> String? {
        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var albumID: String?
        existing.enumerateObjects { c, _, stop in if c.localizedTitle == title { albumID = c.localIdentifier; stop.pointee = true } }
        do {
            if albumID == nil {
                let box = UncheckedBox<NSMutableString>(NSMutableString())
                try await PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                    box.value.setString(req.placeholderForCreatedAssetCollection.localIdentifier)
                }
                albumID = box.value as String
            }
            guard let albumID, !ids.isEmpty else { return albumID }
            try await PHPhotoLibrary.shared().performChanges {
                guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else { return }
                PHAssetCollectionChangeRequest(for: album)?.addAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
            }
            return albumID
        } catch { return nil }
    }

    /// Every photo that sits in at least one of the user's own albums.
    nonisolated static func idsInUserAlbums() async -> Set<String> {
        var out = Set<String>()
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil).enumerateObjects { c, _, _ in
            PHAsset.fetchAssets(in: c, options: nil).enumerateObjects { a, _, _ in out.insert(a.localIdentifier) }
        }
        return out
    }

    /// File sizes straight from PhotoKit, for items the index hasn't seen yet.
    nonisolated static func fileSizes(_ ids: [String]) async -> [String: Int64] {
        var out: [String: Int64] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { a, _, _ in
            out[a.localIdentifier] = (PHAssetResource.assetResources(for: a).first?.value(forKey: "fileSize") as? Int64) ?? 0
        }
        return out
    }

    static func ids(in fetch: PHFetchResult<PHAsset>) -> [String] {
        var out: [String] = []; out.reserveCapacity(fetch.count)
        fetch.enumerateObjects { a, _, _ in out.append(a.localIdentifier) }
        return out
    }

    private static var newestFirst: PHFetchOptions {
        let o = PHFetchOptions(); o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]; return o
    }

    static func ids(inCollection id: String) -> [String] {
        guard let c = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else { return [] }
        return FilmScope.filter(ids(in: PHAsset.fetchAssets(in: c, options: newestFirst)))
    }

    private static func info(for c: PHAssetCollection, symbol: String, allowEmpty: Bool = false) -> AlbumInfo? {
        let r = PHAsset.fetchAssets(in: c, options: newestFirst)
        if let scope = FilmScope.ids() {       // film mode: count and cover from the film photos only
            let ids = ids(in: r).filter(scope.contains)
            guard !ids.isEmpty else { return nil }
            return AlbumInfo(id: c.localIdentifier, title: c.localizedTitle ?? "Album", count: ids.count, coverID: ids.first, symbol: symbol)
        }
        guard r.count > 0 || allowEmpty else { return nil }
        return AlbumInfo(id: c.localIdentifier, title: c.localizedTitle ?? "Album", count: r.count, coverID: r.firstObject?.localIdentifier, symbol: symbol)
    }

    /// Apple's built-in media-type collections that exist in this library.
    static func mediaTypes() -> [AlbumInfo] {
        let wanted: [(PHAssetCollectionSubtype, String)] = [
            (.smartAlbumFavorites, "heart"), (.smartAlbumRecentlyAdded, "clock"), (.smartAlbumVideos, "video"),
            (.smartAlbumSelfPortraits, "person.crop.square"), (.smartAlbumLivePhotos, "livephoto"), (.smartAlbumDepthEffect, "cube"),
            (.smartAlbumPanoramas, "pano"), (.smartAlbumScreenshots, "camera.viewfinder"), (.smartAlbumScreenRecordings, "record.circle"),
            (.smartAlbumBursts, "square.stack.3d.down.right"), (.smartAlbumRAW, "r.square"),
        ]
        return wanted.compactMap { sub, symbol in
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: sub, options: nil).firstObject.flatMap { info(for: $0, symbol: symbol) }
        }
    }

    static func userAlbums() -> [AlbumInfo] {
        var out: [AlbumInfo] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { c, _, _ in
            if let i = info(for: c, symbol: "rectangle.stack", allowEmpty: true) { out.append(i) }
        }
        return out.sorted { $0.count > $1.count }
    }
}

/// Carries a non-Sendable PhotoKit result across the callback boundary; the value is used on one actor only.
struct UncheckedBox<T>: @unchecked Sendable { let value: T; init(_ v: T) { value = v } }
