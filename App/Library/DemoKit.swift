import UIKit
import Photos
import CoreImage
import TidyCore

/// A safe demo set for recording the video: 13 obviously fake photos that hit every collection
/// (forwards, receipts, payments, Wi-Fi, a ticket, an event, a SAMPLE ID card, a meme, duplicates, a blurry shot).
/// All go into a "Spectra Demo" album, so "Remove demo photos" deletes exactly these and nothing else.
enum DemoKit {
    static let albumTitle = "Spectra Demo"
    private static let size = CGSize(width: 1179, height: 1500)

    private struct Item { let daysAgo: Double; let image: UIImage }

    /// Adds the set (once). Returns how many photos were added.
    nonisolated static func add() async -> Int {
        guard albumAssets().count == 0 else { return 0 }
        let items = makeItems()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                var placeholders: [PHObjectPlaceholder] = []
                for item in items {
                    let r = PHAssetChangeRequest.creationRequestForAsset(from: item.image)
                    r.creationDate = Date().addingTimeInterval(-item.daysAgo * 86_400)
                    if let p = r.placeholderForCreatedAsset { placeholders.append(p) }
                }
                album.addAssets(placeholders as NSArray)
            }
            return items.count
        } catch { return 0 }
    }

    /// Deletes every photo in the demo album and the album itself (iOS asks to confirm).
    nonisolated static func remove() async -> Bool {
        guard let album = album() else { return true }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(in: album, options: nil))
                PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
            }
            return true
        } catch { return false }
    }

    nonisolated static var isAdded: Bool { albumAssets().count > 0 }

    nonisolated private static func album() -> PHAssetCollection? {
        let o = PHFetchOptions(); o.predicate = NSPredicate(format: "title == %@", albumTitle)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: o).firstObject
    }

    nonisolated private static func albumAssets() -> PHFetchResult<PHAsset> {
        guard let a = album() else { return PHFetchResult() }
        return PHAsset.fetchAssets(in: a, options: nil)
    }

    // MARK: - The set

    nonisolated private static func makeItems() -> [Item] {
        let sunset = scene(top: UIColor(red: 1.0, green: 0.55, blue: 0.35, alpha: 1), bottom: UIColor(red: 0.35, green: 0.2, blue: 0.55, alpha: 1))
        return [
            Item(daysAgo: 2, image: card(bg: [UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), UIColor(red: 1, green: 0.55, blue: 0.6, alpha: 1)],
                                         lines: [("Good Morning!", 120, .bold), ("Have a blessed day", 64, .regular), ("Shared via WhatsApp", 38, .regular)])),
            Item(daysAgo: 20, image: card(bg: [UIColor(red: 0.95, green: 0.6, blue: 0.1, alpha: 1), UIColor(red: 0.6, green: 0.1, blue: 0.2, alpha: 1)],
                                          lines: [("Happy Diwali", 120, .bold), ("May the festival of lights", 54, .regular), ("bring joy to your family", 54, .regular)])),
            Item(daysAgo: 6, image: doc(title: "SWIGGY", lines: ["Order #81234567", "Paneer Tikka Bowl      Rs 289", "Cold Coffee            Rs 149",
                                                               "Delivery fee           Rs 25", "Total paid             Rs 463", "Tax invoice · Thank you for ordering"])),
            Item(daysAgo: 4, image: doc(title: "Payment successful", lines: ["Rs 1,250.00 paid to", "Blue Tokai Coffee", "UPI Ref No 4123 5567 8890",
                                                                           "From HDFC Bank ••4821", "23 Nov 2026, 9:41 AM"])),
            Item(daysAgo: 9, image: doc(title: "Guest Wi-Fi", lines: ["Network: BlueTokai_Guest", "Password: brew2026", "Ask our baristas if you need help"])),
            Item(daysAgo: 3, image: doc(title: "BOARDING PASS", lines: ["IndiGo 6E 512", "Bengaluru BLR  →  Goa GOI", "Date 12 Dec 2026", "Departure 07:10   Gate 14",
                                                                      "PNR K8Z2QM   Seat 14C", "Passenger DEMO USER"])),
            Item(daysAgo: 12, image: card(bg: [UIColor(red: 0.1, green: 0.1, blue: 0.25, alpha: 1), UIColor(red: 0.45, green: 0.1, blue: 0.6, alpha: 1)],
                                          lines: [("Live in Mumbai", 90, .bold), ("Indie Night", 70, .regular), ("18 Jan 2027 · 7:00 PM", 52, .regular), ("NSCI Dome, Worli", 52, .regular)])),
            Item(daysAgo: 30, image: sampleID()),
            Item(daysAgo: 1, image: card(bg: [UIColor.white, UIColor(white: 0.92, alpha: 1)],
                                         lines: [("me: storage almost full", 60, .bold), ("also me: 400 screenshots", 60, .bold), ("of the same meme", 60, .bold)], ink: .black)),
            Item(daysAgo: 15, image: sunset),
            Item(daysAgo: 15, image: sunset),                       // exact duplicate
            Item(daysAgo: 8, image: blurred(scene(top: UIColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1), bottom: UIColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1)))),
            Item(daysAgo: 0.5, image: doc(title: "Messages", lines: ["Your OTP for login is 482913.", "Valid for 10 minutes.", "Do not share it with anyone."])),
        ]
    }

    // MARK: - Drawing

    nonisolated private static func card(bg: [UIColor], lines: [(String, CGFloat, UIFont.Weight)], ink: UIColor = .white) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bg.map(\.cgColor) as CFArray, locations: nil)!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            var y = size.height / 2 - CGFloat(lines.count) * 70
            for (text, pt, w) in lines {
                let font = UIFont.systemFont(ofSize: pt, weight: w)
                let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
                s.draw(at: CGPoint(x: (size.width - s.size().width) / 2, y: y))
                y += pt * 1.35
            }
        }
    }

    nonisolated private static func doc(title: String, lines: [String]) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 84, weight: .heavy), .foregroundColor: UIColor.black])
                .draw(at: CGPoint(x: 90, y: 160))
            for (i, l) in lines.enumerated() {
                NSAttributedString(string: l, attributes: [.font: UIFont.monospacedSystemFont(ofSize: 48, weight: .medium), .foregroundColor: UIColor.darkGray])
                    .draw(at: CGPoint(x: 90, y: 330 + CGFloat(i) * 92))
            }
        }
    }

    /// Obviously fake ID: "SAMPLE" watermark, demo name, a checksum-valid but invented number so the ID lock triggers.
    nonisolated private static func sampleID() -> UIImage {
        let base = "23456789012"
        let number = base + (0...9).map(String.init).first { verhoeffValid(base + $0) }!
        let spaced = stride(from: 0, to: 12, by: 4).map { i in String(Array(number)[i..<i + 4]) }.joined(separator: " ")
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.96, green: 0.95, blue: 0.9, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let ink: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 56, weight: .semibold), .foregroundColor: UIColor.black]
            NSAttributedString(string: "IDENTITY CARD (SAMPLE)", attributes: [.font: UIFont.systemFont(ofSize: 64, weight: .heavy), .foregroundColor: UIColor.black]).draw(at: CGPoint(x: 90, y: 220))
            NSAttributedString(string: "Name: Demo User", attributes: ink).draw(at: CGPoint(x: 90, y: 420))
            NSAttributedString(string: "DOB: 01/01/1990", attributes: ink).draw(at: CGPoint(x: 90, y: 510))
            NSAttributedString(string: "Aadhaar \(spaced)", attributes: [.font: UIFont.monospacedSystemFont(ofSize: 66, weight: .bold), .foregroundColor: UIColor.black]).draw(at: CGPoint(x: 90, y: 680))
            ctx.cgContext.rotate(by: -0.35)
            NSAttributedString(string: "SAMPLE · NOT A REAL ID", attributes: [.font: UIFont.systemFont(ofSize: 96, weight: .black),
                .foregroundColor: UIColor.red.withAlphaComponent(0.35)]).draw(at: CGPoint(x: -120, y: 1050))
        }
    }

    nonisolated private static func scene(top: UIColor, bottom: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: nil)!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            UIColor(white: 1, alpha: 0.9).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 780, y: 300, width: 220, height: 220))
            UIColor(white: 0.05, alpha: 0.85).setFill()
            let hills = UIBezierPath(); hills.move(to: CGPoint(x: 0, y: 1500)); hills.addLine(to: CGPoint(x: 0, y: 1050))
            hills.addCurve(to: CGPoint(x: 1179, y: 980), controlPoint1: CGPoint(x: 400, y: 820), controlPoint2: CGPoint(x: 800, y: 1200))
            hills.addLine(to: CGPoint(x: 1179, y: 1500)); hills.close(); hills.fill()
        }
    }

    nonisolated private static func blurred(_ img: UIImage) -> UIImage {
        guard let ci = CIImage(image: img) else { return img }
        let out = ci.clampedToExtent().applyingGaussianBlur(sigma: 28).cropped(to: ci.extent)
        guard let cg = CIContext().createCGImage(out, from: ci.extent) else { return img }
        return UIImage(cgImage: cg)
    }
}
