import SwiftUI
import TidyCore

/// Apple Photos vocabulary: semantic system colours (light and dark), system text styles, SF Symbols, one tint.
/// The only owned colours are the on-device AI glow spectrum and the amber cloud state.
enum Palette {
    static let background = Color(.systemBackground)
    static let grouped = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let fill = Color(.tertiarySystemFill)
    static let label = Color(.label)
    static let secondary = Color(.secondaryLabel)
    static let separator = Color(.separator)
    static let keep = Color(.systemGreen)
    static let review = Color(.systemBlue)
    static let junk = Color(.systemRed)
    static let locked = Color(.systemPurple)
    static let cloud = Color(.systemOrange)
    static let glow: [Color] = [Color(red: 0.36, green: 0.55, blue: 1.0), Color(red: 0.70, green: 0.42, blue: 1.0),
                                Color(red: 1.0, green: 0.44, blue: 0.68), Color(red: 1.0, green: 0.71, blue: 0.36),
                                Color(red: 0.36, green: 0.55, blue: 1.0)]
}

enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32 }
enum Radius { static let card: CGFloat = 14, tile: CGFloat = 10, thumb: CGFloat = 6 }

enum Motion {
    static let snappy = Animation.spring(response: 0.30, dampingFraction: 0.86)
    static let smooth = Animation.spring(response: 0.50, dampingFraction: 0.92)
    static let bouncy = Animation.spring(response: 0.55, dampingFraction: 0.72)
}

extension Bucket {
    var title: String {
        switch self {
        case .realPhotos: "Real photos"
        case .duplicates: "Duplicates"
        case .blurry: "Blurry & dark"
        case .forwards: "Forwards"
        case .expiredScreenshots: "Expired screenshots"
        case .usefulScreenshots: "Saved info"
        case .otherScreenshots: "Screenshots"
        case .receivedPhotos: "From chats"
        case .memes: "Memes & posters"
        case .documents: "Documents"
        case .memesDownloads: "Saved images"
        case .idsCards: "IDs & cards"
        case .bigVideos: "Big videos"
        case .aiMade: "AI-made"
        }
    }
    var symbol: String {
        switch self {
        case .realPhotos: "camera"
        case .duplicates: "square.on.square"
        case .blurry: "camera.aperture"
        case .forwards: "arrowshape.turn.up.right"
        case .expiredScreenshots: "clock.badge.xmark"
        case .usefulScreenshots: "bookmark"
        case .otherScreenshots: "iphone"
        case .receivedPhotos: "bubble.left.and.text.bubble.right"
        case .memes: "face.smiling"
        case .documents: "doc.text"
        case .memesDownloads: "square.and.arrow.down"
        case .idsCards: "lock"
        case .bigVideos: "film"
        case .aiMade: "sparkles"
        }
    }
    /// A distinct hue per collection so the library bar and legend read at a glance.
    var tint: Color {
        switch self {
        case .realPhotos: Color(.systemGreen)
        case .duplicates: Color(.systemRed)
        case .forwards: Color(.systemOrange)
        case .expiredScreenshots: Color(.systemPink)
        case .bigVideos: Color(.systemYellow)
        case .memes: Color(.systemIndigo)
        case .otherScreenshots: Color(.systemBlue)
        case .receivedPhotos: Color(.systemTeal)
        case .documents: Color(.systemBrown)
        case .blurry: Color(.systemGray)
        case .aiMade: Color(.systemCyan)
        case .memesDownloads: Color(.systemMint)
        case .usefulScreenshots: Color(red: 0.2, green: 0.6, blue: 0.4)
        case .idsCards: Color(.systemPurple)
        }
    }
}

func gbText(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
