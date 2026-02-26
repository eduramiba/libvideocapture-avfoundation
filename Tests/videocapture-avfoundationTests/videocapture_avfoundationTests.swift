import XCTest
import videocapture_avfoundation

final class videocapture_avfoundationTests: XCTestCase {
    func testCFunctionsLinked() {
        XCTAssertGreaterThanOrEqual(Int(vcavf_devices_count()), 0)
    }
}
