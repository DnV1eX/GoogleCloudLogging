import XCTest
@testable import GoogleCloudLogging
import Logging


final class GoogleCloudLoggingTests: XCTestCase {
    
    static let url = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("swiftlog-ab02c56147dc.json")
    
    
    override class func setUp() {
        
        try! GoogleCloudLogHandler.setup(serviceAccountCredentials: url, clientId: UUID())
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
        let e1 = GoogleCloudLogging.Log.Entry(logName: "", timestamp: nil, severity: nil, insertId: nil, labels: nil, sourceLocation: nil, textPayload: "Message 1")
        let e2 = GoogleCloudLogging.Log.Entry(logName: " Test-2\n.", timestamp: Date(), severity: .default, insertId: nil, labels: [:], sourceLocation: nil, textPayload: " Message\n2 👌")
        let e3 = GoogleCloudLogging.Log.Entry(logName: "/Test_3", timestamp: Date() - 10, severity: .emergency, insertId: "ttt", labels: ["a": "A", "b": "B"], sourceLocation: .init(file: #file, line: String(#line), function: #function), textPayload: "Message 3")
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
    
    
    func testDictionaryUpdate() {
        
        var dictionary = ["a": 1, "b": 2]
        
        XCTAssertEqual(dictionary.update(with: [:]), [:])
        XCTAssertEqual(dictionary, ["a": 1, "b": 2])
        
        XCTAssertEqual(dictionary.update(with: ["c": 3, "b": 2]), ["b": 2])
        XCTAssertEqual(dictionary, ["a": 1, "b": 2, "c": 3])
        
        XCTAssertEqual(dictionary.update(with: ["a": 0]), ["a": 1])
        XCTAssertEqual(dictionary, ["a": 0, "b": 2, "c": 3])
        
        XCTAssertEqual(dictionary.update(with: ["d": 1, "e": 0]), [:])
        XCTAssertEqual(dictionary, ["a": 0, "b": 2, "c": 3, "d": 1, "e": 0])
    }
    
    
    func testSafeLogId() {
        
        XCTAssertEqual("My_class-1.swift".safeLogId(), "My_class-1.swift")
        XCTAssertEqual(" Mÿ@Cláss!✌️/ ".safeLogId(), "_MyClass_")
        XCTAssertEqual("Мой еёжз класс".safeLogId(), "Moj_eezz_klass")
        XCTAssertEqual("".safeLogId(), "_")
    }
    
    
    func testGoogleCloudLogHandler() {
        
        var logger = Logger(label: "GoogleCloudLoggingTests")
        logger[metadataKey: "LoggerMetadataKey"] = "LoggerMetadataValue"
        logger.critical("LoggerMessage", metadata: ["MessageMetadataKey": "MessageMetadataValue"])
        Thread.sleep(forTimeInterval: 3)
    }
    
    
    static var allTests = [
        ("testTokenRequest", testTokenRequest),
        ("testEntriesWrite", testEntriesWrite),
        ("testLogHandler", testLogHandler),
        ("testDictionaryUpdate", testDictionaryUpdate),
        ("testSafeLogId", testSafeLogId),
        ("testGoogleCloudLogHandler", testGoogleCloudLogHandler),
    ]
}
