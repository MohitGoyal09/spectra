import Testing
@testable import TidyCore

@Test func percentMapping() {
    #expect(SimilarityConfig.percent(from: 0.40) == 90)
    #expect(SimilarityConfig.percent(from: 0.08) == 98)
    #expect(SimilarityConfig.percent(from: 4) == 0)
    #expect(SimilarityConfig.percent(from: 5) == 0)
}
@Test func dHashIdenticalIsZeroDistance() {
    let px = (0..<72).map { UInt8(($0 * 37) % 256) }
    #expect(hamming(dHash(gray9x8: px), dHash(gray9x8: px)) == 0)
}
@Test func dHashGradientIsAllOnesOrZeros() {
    let rising = (0..<72).map { UInt8(($0 % 9) * 20) }
    #expect(dHash(gray9x8: rising) == 0 || dHash(gray9x8: rising) == UInt64.max)
}
@Test func bkTreeFindsWithinFive() {
    let t = BKTree()
    t.insert(0b1111, id: "a")
    t.insert(0b1111_0000_0000_1111, id: "b")
    t.insert(UInt64.max, id: "c")
    #expect(Set(t.query(0b0111, maxDistance: 3)) == ["a"])   // b is 5 bits away
    #expect(Set(t.query(0b0111, maxDistance: 5)) == ["a", "b"])
    #expect(t.query(0, maxDistance: 64).count == 3)
}
@Test func bestCopyPrefersSharpLargeFace() {
    let copies = [CopyQuality(sharpness: 0.2, faceQuality: 0.3, pixels: 12_000_000),
                  CopyQuality(sharpness: 0.9, faceQuality: 0.8, pixels: 12_000_000),
                  CopyQuality(sharpness: 0.9, faceQuality: 0.8, pixels: 3_000_000)]
    #expect(bestCopyIndex(copies) == 1)
}
@Test func groupsByDistance() {
    let groups = groupDuplicates(ids: ["a", "b", "c"], distance: { a, b in
        Set([a, b]) == ["a", "b"] ? 0.05 : 3.0
    }, maxDistance: SimilarityConfig.duplicateMaxDistance)
    #expect(groups == [["a", "b"]])
}
