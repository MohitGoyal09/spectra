/// Thresholds for Vision feature-print distance (0 = identical, 4 ≈ 0% similar).
/// Values from nilkanthdesai76/swift-vision-photo-dedupe (MIT).
public enum SimilarityConfig {
    public static let minimumPercent = 90
    public static let duplicatePercent = 98
    public static let distanceScale: Float = 4
    public static let maxDistance: Float = 0.40
    public static let duplicateMaxDistance: Float = 0.08
    public static let blurThreshold: Float = 0.16
    public static let dHashMaxHamming = 5
    public static func percent(from distance: Float) -> Int { max(0, min(100, Int(((1 - distance / distanceScale) * 100).rounded()))) }
}
