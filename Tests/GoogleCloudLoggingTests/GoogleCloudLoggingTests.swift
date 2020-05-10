import XCTest
@testable import GoogleCloudLogging


final class GoogleCloudLoggingTests: XCTestCase {
    
    let url = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("swiftlog-ab02c56147dc.json")
    
    
    func testTokenRequest() {
        
        let gcl = try! GoogleCloudLogging(serviceAccountCredentialsURL: url)
        let dg = DispatchGroup()
        dg.enter()
        gcl.requestToken { result in
            try? XCTAssertNoThrow(try result.get())
            print(result)
            dg.leave()
        }
        dg.wait()
    }

    
    func testEntriesWrite() {
        
        let gcl = try! GoogleCloudLogging(serviceAccountCredentialsURL: url)
        let dg = DispatchGroup()
        dg.enter()
        let e1 = GoogleCloudLogging.Log.Entry(logName: GoogleCloudLogging.Log.name(projectId: gcl.serviceAccountCredentials.projectId, logId: "Test1"), timestamp: nil, severity: nil, labels: nil, sourceLocation: nil, textPayload: "Message 1")
        let e2 = GoogleCloudLogging.Log.Entry(logName: GoogleCloudLogging.Log.name(projectId: gcl.serviceAccountCredentials.projectId, logId: "Test2"), timestamp: Date(), severity: .default, labels: [:], sourceLocation: nil, textPayload: "Message 2")
        let e3 = GoogleCloudLogging.Log.Entry(logName: GoogleCloudLogging.Log.name(projectId: gcl.serviceAccountCredentials.projectId, logId: "Test3"), timestamp: Date() - 10, severity: .emergency, labels: ["a": "A", "b": "B"], sourceLocation: .init(file: #file, line: String(#line), function: #function), textPayload: "Message 3")
        gcl.write(entries: [e1, e2, e3]) { result in
            try? XCTAssertNoThrow(try result.get())
            print(result)
            dg.leave()
        }
        dg.wait()
    }

    
    static var allTests = [
        ("testTokenRequest", testTokenRequest),
        ("testEntriesWrite", testEntriesWrite),
    ]
}
