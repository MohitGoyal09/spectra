/// Verhoeff checksum (used by Aadhaar numbers).
public func verhoeffValid(_ digits: String) -> Bool {
    let d: [[Int]] = [[0,1,2,3,4,5,6,7,8,9],[1,2,3,4,0,6,7,8,9,5],[2,3,4,0,1,7,8,9,5,6],[3,4,0,1,2,8,9,5,6,7],
                      [4,0,1,2,3,9,5,6,7,8],[5,9,8,7,6,0,4,3,2,1],[6,5,9,8,7,1,0,4,3,2],[7,6,5,9,8,2,1,0,4,3],
                      [8,7,6,5,9,3,2,1,0,4],[9,8,7,6,5,4,3,2,1,0]]
    let p: [[Int]] = [[0,1,2,3,4,5,6,7,8,9],[1,5,7,6,2,8,3,0,9,4],[5,8,0,3,7,9,6,1,4,2],[8,9,1,6,0,4,3,5,2,7],
                      [9,4,5,3,1,2,6,8,7,0],[4,2,8,6,5,7,3,9,0,1],[2,7,9,3,8,0,6,4,1,5],[7,0,4,6,9,1,3,2,5,8]]
    let nums = digits.compactMap(\.wholeNumberValue)
    guard nums.count == digits.count, !nums.isEmpty else { return false }
    var c = 0
    for (i, n) in nums.reversed().enumerated() { c = d[c][p[i % 8][n]] }
    return c == 0
}

/// Luhn checksum (used by card numbers).
public func luhnValid(_ digits: String) -> Bool {
    let nums = digits.compactMap(\.wholeNumberValue)
    guard nums.count == digits.count, nums.count >= 13 else { return false }
    let sum = nums.reversed().enumerated().reduce(0) { acc, e in
        guard e.offset % 2 == 1 else { return acc + e.element }
        let x = e.element * 2
        return acc + (x > 9 ? x - 9 : x)
    }
    return sum % 10 == 0
}
