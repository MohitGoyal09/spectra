import Photos

/// Tells the app when the photo library changes (our deletes, favourites, locks, or edits in Apple Photos),
/// so every screen stays in sync. Pattern from Apple's PhotoKit sample.
final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let onChange: @Sendable () -> Void
    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    func photoLibraryDidChange(_ changeInstance: PHChange) { onChange() }
}
