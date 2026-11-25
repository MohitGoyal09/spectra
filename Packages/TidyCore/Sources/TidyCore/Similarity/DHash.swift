/// Difference hash from a 9×8 grayscale image (row-major, 72 bytes): bit set when a pixel is brighter than its right neighbour.
public func dHash(gray9x8 px: [UInt8]) -> UInt64 {
    precondition(px.count == 72, "dHash needs 9×8 pixels")
    var h: UInt64 = 0
    for row in 0..<8 {
        for col in 0..<8 {
            h <<= 1
            if px[row * 9 + col] > px[row * 9 + col + 1] { h |= 1 }
        }
    }
    return h
}

public func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
