/// Whether an item may start checked for deletion. Favourites, sensitive items and camera photos with faces never may.
public func isPreselectable(_ v: Verdict, record: PhotoRecord) -> Bool {
    v.verdict == .junk && v.kind != .received && !record.isFavorite && v.sensitive == nil && !(record.cameraMake != nil && record.faceCount > 0 && !record.isScreenshot)
}
