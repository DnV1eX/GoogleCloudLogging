//
//  GoogleCloudLogHandler.swift
//  GoogleCloudLogging
//
//  Created by Alexey Demin on 2020-05-07.
//  Copyright © 2020 DnV1eX. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Logging


public struct GoogleCloudLogHandler: LogHandler {
    
    @Atomic public static var forcedLogLevel: Logger.Level?
    @Atomic public static var defaultLogLevel: Logger.Level = .info
    @Atomic public static var signalingLogLevel: Logger.Level? = .critical

    @Atomic public static var maxLogSize: UInt? = 10_000_000
    
    @Atomic public static var logsRetentionPeriod: TimeInterval? = 3600 * 24 * 30
    
    @Atomic public static var uploadInterval: TimeInterval? = 3600 {
        didSet {
            if logging != nil {
                timer.schedule(delay: uploadInterval, repeating: uploadInterval)
            }
        }
    }
    
    @Atomic public static var includeSourceLocation = true

    
    static var logging: GoogleCloudLogging!
    
    static var logFile: URL!
    
    static let fileHandleQueue = DispatchQueue(label: "GoogleCloudLogHandler.FileHandle")
    
    static let timer: DispatchSourceTimer = {
        let timer = DispatchSource.makeTimerSource()
        timer.setEventHandler(handler: uploadOnSchedule)
        timer.activate()
        return timer
    }()


    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            metadata[key]
        }
        set {
            metadata[key] = newValue
        }
    }
    
    public var metadata: Logger.Metadata = [:]
    
    
    private var _logLevel: Logger.Level = Self.defaultLogLevel
    
    public var logLevel: Logger.Level {
        get {
            Self.forcedLogLevel ?? _logLevel
        }
        set {
            _logLevel = newValue
        }
    }
    
    
    let label: String
    

    static func prepareLogFile() throws {
        
        if (try? logFile.checkResourceIsReachable()) != true {
            try FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try Data().write(to: logFile)
        }
    }
    
    
    public static func setup(serviceAccountCredentials url: URL, logFile: URL = FileManager.default.temporaryDirectory.appendingPathComponent("GoogleCloudLogEntries", isDirectory: false).appendingPathExtension("jsonl")) throws {
        
        assert(logging == nil, "Can only setup GoogleCloudLogHandler once")
        
        logging = try GoogleCloudLogging(serviceAccountCredentials: url)
        
        Self.logFile = logFile
        try prepareLogFile()
        
        upload()
    }
    
    
    public init(label: String) {
        
        assert(Self.logging != nil, "Must setup GoogleCloudLogHandler before init")
        
        self.label = label
    }
    
    
    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
        
        Self.fileHandleQueue.async {
            let logName = GoogleCloudLogging.Log.name(projectId: Self.logging.serviceAccountCredentials.projectId, logId: self.label)
            let labels = self.metadata.merging(metadata ?? [:]) { $1 }.mapValues { "\($0)" }
            let logEntry = GoogleCloudLogging.Log.Entry(logName: logName,
                                                        timestamp: Date(),
                                                        severity: .init(level: level),
                                                        labels: labels.isEmpty ? nil : labels,
                                                        sourceLocation: Self.includeSourceLocation ? .init(file: file, line: "\(line)", function: function) : nil,
                                                        textPayload: "\(message)")
            do {
                try Self.prepareLogFile()
                let fileHandle = try FileHandle(forWritingTo: Self.logFile)
                try fileHandle.legacySeekToEnd()
                try fileHandle.legacyWrite(contentsOf: JSONEncoder().encode(logEntry))
                try fileHandle.legacyWrite(contentsOf: [.newline])
            } catch {
                print(error, logEntry)
            }
            if let signalingLevel = Self.signalingLogLevel, level >= signalingLevel {
                Self.upload()
            }
        }
    }
    
    
    public static func upload() {
        
        assert(logging != nil, "Must setup GoogleCloudLogHandler before upload")
        
        timer.schedule(delay: nil, repeating: uploadInterval)
    }
    
    
    static func uploadOnSchedule() {
        
        fileHandleQueue.async {
            do {
                let fileHandle = try FileHandle(forReadingFrom: logFile)
                guard var data = try fileHandle.legacyReadToEnd(), !data.isEmpty else { return }
                
                let overflow = maxLogSize.map { data.count - Int($0) } ?? 0
                if overflow > 0 {
                    data.removeFirst(overflow)
                }
                let lines = data.split(separator: .newline)
                let lineCount = lines.count
                let decoder = JSONDecoder()
                var logEntries = lines.compactMap { try? decoder.decode(GoogleCloudLogging.Log.Entry.self, from: $0) }
                if let logsRetentionPeriod = logsRetentionPeriod {
                    logEntries.removeAll { $0.timestamp.map { -$0.timeIntervalSinceNow > logsRetentionPeriod } ?? false }
                }
                
                logging.write(entries: logEntries) { result in
                    fileHandleQueue.async {
                        do {
                            switch result {
                            case .success:
                                try (fileHandle.legacyReadToEnd() ?? Data()).write(to: logFile, options: .atomic)
                            case .failure(let error):
                                print(error)
                                if overflow > 0 || lineCount != logEntries.count {
                                    let encoder = JSONEncoder()
                                    var lines = logEntries.compactMap { try? encoder.encode($0) }
                                    if let data = try fileHandle.legacyReadToEnd(), !data.isEmpty {
                                        lines.append(data)
                                    }
                                    try Data(lines.joined(separator: [.newline])).write(to: logFile, options: .atomic)
                                }
                            }
                        } catch {
                            print(error)
                        }
                    }
                }
            } catch {
                print(error)
            }
        }
    }
}



extension GoogleCloudLogging.Log.Entry.Severity {
    
    init(level: Logger.Level) {
        switch level {
        case .trace: self = .default
        case .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .warning: self = .warning
        case .error: self = .error
        case .critical: self = .critical
        }
    }
}



@propertyWrapper
public class Atomic<T> {
    
    private let queue = DispatchQueue(label: "GoogleCloudLogHandler.AtomicProperty", attributes: .concurrent)
    private var value: T
    public var wrappedValue: T {
        get { queue.sync { value } }
        set { queue.async(flags: .barrier) { self.value = newValue } }
    }
    public init(wrappedValue: T) {
        value = wrappedValue
    }
}



extension Data.Element {
    
    static let newline = Data("\n".utf8).first! // 10
}



extension FileHandle {
    
    @discardableResult
    func legacySeekToEnd() throws -> UInt64 {
        if #available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            return try seekToEnd()
        } else {
            return seekToEndOfFile()
        }
    }
    
    func legacyWrite<T>(contentsOf data: T) throws where T : DataProtocol {
        if #available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            try write(contentsOf: data)
        } else {
            write(Data(data))
        }
    }
    
    func legacyReadToEnd() throws -> Data? {
        if #available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            return try readToEnd()
        } else {
            return readDataToEndOfFile()
        }
    }
}



extension DispatchSourceTimer {
    
    func schedule(delay: TimeInterval?, repeating: TimeInterval?) {
        schedule(deadline: delay.map { .now() + $0 } ?? .now(), repeating: repeating.map { .seconds(Int($0)) } ?? .never, leeway: repeating.map { .seconds(Int($0 / 2)) } ?? .nanoseconds(0))
    }
}
