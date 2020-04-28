import XCTest
@testable import GoogleCloudLogging

final class GoogleCloudLoggingTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(GoogleCloudLogging().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
