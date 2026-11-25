import Foundation
import LocalAuthentication

/// Albums the user locked with Face ID (or the passcode). Only the album IDs are stored, on this iPhone.
enum AlbumLock {
    static let key = "lockedAlbumIDs"

    /// One string (IDs separated by newlines) so views can watch it with @AppStorage.
    static func ids(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.string(forKey: key) ?? "").split(separator: "\n").map(String.init))
    }

    static func isLocked(_ id: String, in defaults: UserDefaults = .standard) -> Bool { ids(defaults).contains(id) }

    static func setLocked(_ id: String, _ locked: Bool, in defaults: UserDefaults = .standard) {
        var set = ids(defaults)
        if locked { set.insert(id) } else { set.remove(id) }
        defaults.set(set.sorted().joined(separator: "\n"), forKey: key)
    }

    /// False when the iPhone has no passcode, so a lock could never be opened.
    static var canLock: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    /// Face ID, falling back to the passcode.
    static func unlock(_ reason: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
