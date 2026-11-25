#if DEBUG
import Foundation
import Photos
import ImageIO

/// Debug only: launch with `-film-import` to move every photo and video in the app's Documents/FilmImport folder
/// (copied there with `xcrun devicectl device copy to`) into the "Spectra Film" album, then delete the folder.
/// Used to fill film mode with stock photos instead of anyone's own.
enum FilmImport {
    static let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("FilmImport")
    private static let albumTitle = FilmScope.albumTitles[0]

    /// `-film-reset`: deletes every photo in the film albums (hidden ones too) and the albums, so a retake starts
    /// from the same library. iOS asks to confirm. Only the film albums are touched.
    static func reset() async {
        let o = PHFetchOptions(); o.predicate = NSPredicate(format: "title IN %@", FilmScope.albumTitles)
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: o)
        let ao = PHFetchOptions(); ao.includeHiddenAssets = true
        var assets: [PHAsset] = []
        albums.enumerateObjects { c, _, _ in PHAsset.fetchAssets(in: c, options: ao).enumerateObjects { a, _, _ in assets.append(a) } }
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
            PHAssetCollectionChangeRequest.deleteAssetCollections(albums)
        }
    }

    static func run() async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil), !files.isEmpty else { return }
        let media = files.filter { ["jpg", "jpeg", "heic", "png", "mov", "mp4"].contains($0.pathExtension.lowercased()) }
        guard let album = await filmAlbum() else { return }
        for chunk in stride(from: 0, to: media.count, by: 40).map({ Array(media[$0..<min($0 + 40, media.count)]) }) {
            try? await PHPhotoLibrary.shared().performChanges {
                var placeholders: [PHObjectPlaceholder] = []
                for url in chunk {
                    let r = PHAssetCreationRequest.forAsset()
                    let isVideo = ["mov", "mp4"].contains(url.pathExtension.lowercased())
                    r.addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
                    if let d = captureDate(url) { r.creationDate = d }
                    if let p = r.placeholderForCreatedAsset { placeholders.append(p) }
                }
                PHAssetCollectionChangeRequest(for: album)?.addAssets(placeholders as NSArray)
            }
        }
        try? FileManager.default.removeItem(at: folder)
    }

    private static func filmAlbum() async -> PHAssetCollection? {
        let o = PHFetchOptions(); o.predicate = NSPredicate(format: "title == %@", albumTitle)
        if let a = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: o).firstObject { return a }
        var id: String?
        try? await PHPhotoLibrary.shared().performChanges {
            id = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle).placeholderForCreatedAssetCollection.localIdentifier
        }
        return id.flatMap { PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject }
    }

    /// EXIF DateTimeOriginal, so stock photos spread across the timeline instead of all landing today.
    private static func captureDate(_ url: URL) -> Date? {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
              let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: text)
    }
}
#endif
