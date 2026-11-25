import XCTest
@testable import TidyRoll

final class ScanStageTests: XCTestCase {
    func testPointsLieOnTheUnitSphere() {
        for i in 0..<72 {
            let p = fibonacciSpherePoint(i, of: 72)
            XCTAssertEqual((p * p).sum().squareRoot(), 1, accuracy: 1e-9)
        }
    }
    func testRotationKeepsPointsOnTheSphere() {
        let p = projectOnGlobe(fibonacciSpherePoint(10, of: 72), spin: 1.3)
        XCTAssertEqual((p * p).sum().squareRoot(), 1, accuracy: 1e-9)
    }
    func testPointsSpreadAcrossBothHemispheres() {
        let ys = (0..<72).map { fibonacciSpherePoint($0, of: 72).y }
        XCTAssertEqual(ys.filter { $0 > 0 }.count, 36)
    }
}

final class StreamPathTests: XCTestCase {
    func testStreamStartsAndEndsAtItsPoints() {
        let a = CGPoint(x: 10, y: 300), b = CGPoint(x: 200, y: 600)
        XCTAssertEqual(streamPoint(from: a, to: b, t: 0, bow: 30), a)
        let end = streamPoint(from: a, to: b, t: 1, bow: 30)
        XCTAssertEqual(end.x, b.x, accuracy: 1e-9); XCTAssertEqual(end.y, b.y, accuracy: 1e-9)
    }
}
