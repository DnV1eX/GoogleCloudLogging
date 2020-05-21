import XCTest
@testable import GoogleCloudLogging
import Logging


final class GoogleCloudLoggingTests: XCTestCase {
    
    static let url = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("swiftlog-ab02c56147dc.json")
    
    
    override class func setUp() {
        
        try! GoogleCloudLogHandler.setup(serviceAccountCredentials: url)
        LoggingSystem.bootstrap(GoogleCloudLogHandler.init)
    }
    
    
    func testTokenRequest() {
        
        let gcl = try! GoogleCloudLogging(serviceAccountCredentials: Self.url)
        let dg = DispatchGroup()
        dg.enter()
        gcl.requestToken { result in
            if case .failure = result { XCTFail() }
            print(result)
            dg.leave()
        }
        dg.wait()
    }

    
    func testEntriesWrite() {
        
        let gcl = try! GoogleCloudLogging(serviceAccountCredentials: Self.url)
        let dg = DispatchGroup()
        dg.enter()
        let e1 = GoogleCloudLogging.Log.Entry(logName: GoogleCloudLogging.Log.name(projectId: gcl.serviceAccountCredentials.projectId, logId: "Test1"), timestamp: nil, severity: nil, labels: nil, sourceLocation: nil, textPayload: "Message 1")
        let e2 = GoogleCloudLogging.Log.Entry(logName: GoogleCloudLogging.Log.name(projectId: gcl.serviceAccountCredentials.projectId, logId: "Test2"), timestamp: Date(), severity: .default, labels: [:], sourceLocation: nil, textPayload: "Message 2")
        let e3 = GoogleCloudLogging.Log.Entry(logName: GoogleCloudLogging.Log.name(projectId: gcl.serviceAccountCredentials.projectId, logId: "Test3"), timestamp: Date() - 10, severity: .emergency, labels: ["a": "A", "b": "B"], sourceLocation: .init(file: #file, line: String(#line), function: #function), textPayload: "Message 3")
        gcl.write(entries: [e1, e2, e3]) { result in
            if case .failure = result { XCTFail() }
            print(result)
            dg.leave()
        }
        dg.wait()
    }

    
    func testLogHandler() {
        
        var logger1 = Logger(label: "first logger")
        logger1.logLevel = .debug
        logger1[metadataKey: "only-on"] = "first"
        
        var logger2 = logger1
        logger2.logLevel = .error                  // this must not override `logger1`'s log level
        logger2[metadataKey: "only-on"] = "second" // this must not override `logger1`'s metadata
        
        XCTAssertEqual(.debug, logger1.logLevel)
        XCTAssertEqual(.error, logger2.logLevel)
        XCTAssertEqual("first", logger1[metadataKey: "only-on"])
        XCTAssertEqual("second", logger2[metadataKey: "only-on"])
    }
    
    
    func testGoogleCloudLogHandler() {
        
        var logger = Logger(label: "GoogleCloudLoggingTests")
        logger[metadataKey: "LoggerMetadataKey"] = "LoggerMetadataValue"
        logger.critical("LoggerMessage", metadata: ["MessageMetadataKey": "MessageMetadataValue"])
        sleep(3)
    }
    
    
    static var allTests = [
        ("testTokenRequest", testTokenRequest),
        ("testEntriesWrite", testEntriesWrite),
        ("testLogHandler", testLogHandler),
        ("testGoogleCloudLogHandler", testGoogleCloudLogHandler),
    ]
}
