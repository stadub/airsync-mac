import XCTest
@testable import MirroringCore

final class MirroringCoreTests: XCTestCase {
    func testReconnectAdoptsLiveTransportUnlessResetIsExplicit() {
        let normal = WirelessReconnectPlan(livePort: 40000, reportedPorts: ["39000"], resetServer: false)
        XCTAssertEqual(normal.reusePort, 40000)
        XCTAssertFalse(normal.resetServer)
        let reset = WirelessReconnectPlan(livePort: 40000, reportedPorts: ["39000", "40000"], resetServer: true)
        XCTAssertNil(reset.reusePort)
        XCTAssertEqual(reset.candidatePorts, ["40000", "39000"])
        let disconnected = WirelessReconnectPlan(livePort: nil, reportedPorts: ["39000"], resetServer: false)
        XCTAssertNil(disconnected.reusePort)
        XCTAssertEqual(disconnected.candidatePorts, ["39000"])
    }
}
