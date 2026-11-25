import XCTest
@testable import TidyRoll

final class GlowStateTests: XCTestCase {
    func testGlowIsOnDeviceWhenWorkingAndAvailable() { XCTAssertEqual(glowState(onDeviceAvailable: true, cloudBusy: false, working: true), .onDevice) }
    func testGlowIsCloudWhenCloudBusy() { XCTAssertEqual(glowState(onDeviceAvailable: true, cloudBusy: true, working: true), .cloud) }
    func testGlowIdleWhenNotWorking() { XCTAssertEqual(glowState(onDeviceAvailable: true, cloudBusy: false, working: false), .idle) }
    func testNoSpectrumGlowWithoutOnDeviceModel() { XCTAssertEqual(glowState(onDeviceAvailable: false, cloudBusy: false, working: true), .idle) }
    func testReduceMotionStopsRotation() {
        XCTAssertEqual(glowAngle(time: 0, lap: 3.2, reduceMotion: true), glowAngle(time: 1.7, lap: 3.2, reduceMotion: true))
        XCTAssertNotEqual(glowAngle(time: 0, lap: 3.2, reduceMotion: false), glowAngle(time: 1.6, lap: 3.2, reduceMotion: false))
    }
}
