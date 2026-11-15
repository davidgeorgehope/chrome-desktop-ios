import XCTest

/// Hosted inside Crate.app on D4iPad so a debugger can attach and bless the
/// code region. Not a UI test: Designed for iPad rejects those.
final class StayAliveTests: XCTestCase {
    func testStayAliveForDebugger() throws {
        Thread.sleep(forTimeInterval: 180)
        XCTAssertTrue(true)
    }
}
