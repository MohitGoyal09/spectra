import Foundation
import Photos

/// Film mode, for recording the demo video without showing anyone's real photos.
/// Debug builds launched with `-film` see only the photos in the "Spectra Film" and "Spectra Demo" albums, and keep a
/// separate index, privacy log and smart-album list. Release builds: always off.
enum FilmScope {
    #if DEBUG
    nonisolated static let isOn = ProcessInfo.processInfo.arguments.contains("-film")
    #else
    nonisolated static let isOn = false
    #endif

    nonisolated static let albumTitles = ["Spectra Film", DemoKit.albumTitle]

    /// The app's data folder in Application Support.
    nonisolated static var dataFolder: String { isOn ? "TidyRoll-Film" : "TidyRoll" }

    /// The photos the app may see, or nil when film mode is off (everything).
    nonisolated static func ids() -> Set<String>? {
        guard isOn else { return nil }
        var out = Set<String>()
        let o = PHFetchOptions(); o.predicate = NSPredicate(format: "title IN %@", albumTitles)
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: o).enumerateObjects { c, _, _ in
            PHAsset.fetchAssets(in: c, options: nil).enumerateObjects { a, _, _ in out.insert(a.localIdentifier) }
        }
        return out
    }

    /// Keeps the order; drops anything outside the film albums when film mode is on.
    nonisolated static func filter(_ ids: [String]) -> [String] {
        guard let scope = Self.ids() else { return ids }
        return ids.filter(scope.contains)
    }
}
