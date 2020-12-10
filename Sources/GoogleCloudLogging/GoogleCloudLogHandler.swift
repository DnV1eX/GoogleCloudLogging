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

/// Customizable SwiftLog logging backend for Google Cloud Logging via REST API v2 with offline functionality.
public struct GoogleCloudLogHandler: LogHandler {
    
    /// Predefined metadata key strings.
    ///
    /// - clientId
    /// - buildConfiguration
    /// - error
    /// - description
    ///
    /// A good practice is to add custom keys in *extension* rather than use string literals.
    ///
    /// It is also convenient to define *typealias*:
    ///
    ///     typealias LogKey = GoogleCloudLogHandler.MetadataKey
    ///
    public struct MetadataKey {
        public static let clientId = "clientId"
        public static let buildConfiguration = "buildConfiguration"
        public static let error = "error"
        public static let description = "description"
    }
    
    /// Global metadata dictionary. *Atomic*.
    ///
    /// Used to store `clientId`.
    ///
    /// Another good use case is storing `buildConfiguration` when logger is used in *Debug* builds (`LogKey` is *typealias* for `GoogleCloudLogHandler.MetadataKey`):
    ///
    ///     #if DEBUG
    ///     GoogleCloudLogHandler.globalMetadata[LogKey.buildConfiguration] = "Debug"
    ///     #endif
    ///
    /// - Remark: Takes precedence over `Logger` and `Log` metadata keys in case of overlapping.
    ///
    /// - Warning: Do not abuse `globalMetadata` as it is added to each log entry of the app.
    ///
    @Atomic public static var globalMetadata: Logger.Metadata = [:]
    
    /// Overridden log level of each `Logger`. *Atomic*.
    ///
    /// For example, you can set `.trace` in a particular app instance to debug some special error case or track its behavior.
    ///
    @Atomic public static var forcedLogLevel: Logger.Level?
    
    /// Initial log level of `Logger`. *Atomic*.
    ///
    /// **Default** is `.info`.
    ///
    @Atomic public static var defaultLogLevel: Logger.Level = .info
    
    /// The log level upon receipt of which an attempt is made to immediately `upload` local logs to the server. *Atomic*.
    ///
    /// **Default** is `.critical`.
    ///
    @Atomic public static var signalingLogLevel: Logger.Level? = .critical
    
    /// Log entry upload size limit in bytes. *Atomic*.
    ///
    /// Logs that exceed the limit are excluded from the upload and deleted.
    ///
    /// **Default** is equivalent to `256 KB`, which is the approximate Google Cloud limit.
    ///
    @Atomic public static var maxLogEntrySize: UInt? = 256_000

    /// Log upload size limit in bytes. *Atomic*.
    ///
    /// Overflow is excluded from the upload and deleted starting with older logs.
    ///
    /// **Default** is equivalent to `10 MB`, which is the approximate Google Cloud limit.
    ///
    @Atomic public static var maxLogSize: UInt? = 10_000_000

    /// Logs retention period in seconds. *Atomic*.
    ///
    /// Expired logs are excluded from the upload and deleted.
    ///
    /// **Default** is equivalent to `30 days`, which is the default Google Cloud logs retention period.
    ///
    @Atomic public static var retentionPeriod: TimeInterval? = 3600 * 24 * 30
    
    /// Log upload interval in seconds. *Atomic*.
    ///
    /// Schedules the next and all repeated uploads after the specified time interval.
    ///
    /// **Default** is equivalent to `1 hour`.
    ///
    @Atomic public static var uploadInterval: TimeInterval? = 3600 {
        didSet {
            if logging != nil {
                timer.schedule(delay: uploadInterval, repeating: uploadInterval)
                logger.debug("Log upload interval has been updated", metadata: [MetadataKey.uploadInterval: uploadInterval.map { "\($0)" } ?? "nil"])
            }
        }
    }
    
    /// Whether to include additional information about the source code location. *Atomic*.
    ///
    /// For each logger call, the source file path, the line number within the source file and the function name are added to the produced log entry.
    /// Assign `false` to opt out this behavior.
    ///
    /// **Default** is `true`.
    ///
    @Atomic public static var includeSourceLocation = true

    /// Internal logger for GoogleCloudLogHandler. *Atomic*.
    ///
    /// You can choose an appropriate `logLevel`.
    ///
    @Atomic public static var logger = Logger(label: "GoogleCloudLogHandler")
    
    /// URL to the local logs storage. *Atomic*.
    ///
    /// It can only be set once during `setup()`.
    /// Logs are stored in JSON Lines format.
    ///
    /// **Default** is `/tmp/GoogleCloudLogEntries.jsonl`.
    ///
    @Atomic public internal(set) static var logFile = FileManager.default.temporaryDirectory.appendingPathComponent("GoogleCloudLogEntries", isDirectory: false).appendingPathExtension("jsonl")
    
    @Atomic static var logging: GoogleCloudLogging?
    
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
    
    /// Setup `GoogleCloudLogHandler`.
    ///
    /// It must be called once, usually right after the app has been launched.
    ///
    /// - Parameters:
    ///     - url: Service account credentials URL pointing to a JSON file generated by GCP and typically located in the app bundle.
    ///     - clientId: The unique identifier for the client app instance that is added to each log entry and used to group and differ logs.
    ///     - logFile: Optional custom log file URL.
    ///
    /// - Throws: `Error` if the service account credentials are unreadable or malformed, and also if unable to access or create the log file.
    ///
    public static func setup(serviceAccountCredentials url: URL, clientId: UUID?, logFile: URL = logFile) throws {
        
        let isFirstSetup = (logging == nil)
        logging = try GoogleCloudLogging(serviceAccountCredentials: url)
        
        globalMetadata[MetadataKey.clientId] = clientId.map(Logger.MetadataValue.stringConvertible)
        
        Self.logFile = logFile
        try prepareLogFile()
        
        upload()
        
        DispatchQueue.main.async { // Async in case setup before LoggingSystem bootstrap.
            if isFirstSetup {
                logger.info("GoogleCloudLogHandler has been setup", metadata: [MetadataKey.serviceAccountCredentials: "\(url)", MetadataKey.logFile: "\(logFile)"])
            } else {
                logger.warning("Repeated setup of GoogleCloudLogHandler", metadata: [MetadataKey.serviceAccountCredentials: "\(url)", MetadataKey.logFile: "\(logFile)"])
                fileHandleQueue.async { // Assert in fileHandleQueue so warning is saved.
                    assertionFailure("App should only setup GoogleCloudLogHandler once")
                }
            }
        }
    }
    
    /// Use as `GoogleCloudLogHandler` factory for `LoggingSystem.bootstrap()` and `Logger.init()`.
    ///
    /// - Parameter label: Forwarded `logger.label` which is typically the enclosing class name.
    ///
    public init(label: String) {
        
        assert(Self.logging != nil, "App must setup GoogleCloudLogHandler before init")
        
        self.label = label
        
        DispatchQueue.main.async {
            Self.logger.trace("GoogleCloudLogHandler has been initialized", metadata: [MetadataKey.label: "\(label)"])
        }
    }
    
    
    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
        
        let date = Date()
        
        Self.fileHandleQueue.async {
            let hashValue: Int? = Self.globalMetadata[MetadataKey.clientId].map {
                var hasher = Hasher()
                hasher.combine("\($0)") // Required in case random seeding is disabled.
                hasher.combine("\(message)")
                hasher.combine(date)
                return hasher.finalize()
            }
            var metadata = metadata ?? [:]
            var replacedMetadata = metadata.update(with: self.metadata)
            if !replacedMetadata.isEmpty, file != #file || function != #function {
                Self.logger.warning("Log metadata is replaced by logger metadata", metadata: [MetadataKey.replacedMetadata: .dictionary(replacedMetadata)])
            }
            replacedMetadata = metadata.update(with: Self.globalMetadata)
            if !replacedMetadata.isEmpty, file != #file || function != #function {
                Self.logger.warning("Log metadata is replaced by global metadata", metadata: [MetadataKey.replacedMetadata: .dictionary(replacedMetadata)])
            }
            let labels = metadata.mapValues { "\($0)" }
            let logEntry = GoogleCloudLogging.Log.Entry(logName: self.label,
                                                        timestamp: date,
                                                        severity: .init(level: level),
                                                        insertId: hashValue.map { String($0, radix: 36) },
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
                if file != #file || function != #function {
                    Self.logger.error("Unable to save log entry", metadata: [MetadataKey.logEntry: "\(logEntry)", MetadataKey.error: "\(error)"])
                }
                return
            }
            
            if let signalingLevel = Self.signalingLogLevel, level >= signalingLevel, file != #file || function != "uploadOnSchedule()" {
                Self.upload()
            }
        }
    }
    
    /// Upload saved logs to GCP.
    ///
    /// It is called automatically after `setup()` and is repeating at `uploadInterval`.
    ///
    /// You can also call `upload()` manually in code e.g. before exit the app.
    ///
    public static func upload() {
        
        assert(logging != nil, "App must setup GoogleCloudLogHandler before upload")
        
        timer.schedule(delay: nil, repeating: uploadInterval)
    }
    
    
    static func uploadOnSchedule() {
        
        logger.debug("Start uploading logs")
        
        fileHandleQueue.async {
            do {
                let fileHandle = try FileHandle(forReadingFrom: logFile)
                guard let data = try fileHandle.legacyReadToEnd(), !data.isEmpty else {
                    logger.debug("No logs to upload")
                    return
                }
                
                var lines = data.split(separator: .newline)
                let lineCount = lines.count
                var logSize = lines.reduce(0) { $0 + $1.count }
                let exclusionMessage = "Some log entries are excluded from the upload"
                
                if let maxLogEntrySize = maxLogEntrySize, logSize > maxLogEntrySize {
                    lines.removeAll { $0.count > maxLogEntrySize }
                    let removedLineCount = lineCount - lines.count
                    if removedLineCount > 0 {
                        logSize = lines.reduce(0) { $0 + $1.count }
                        logger.warning("\(exclusionMessage) due to exceeding the log entry size limit", metadata: [MetadataKey.excludedLogEntryCount: "\(removedLineCount)", MetadataKey.maxLogEntrySize: "\(maxLogEntrySize)"])
                    }
                }
                
                if let maxLogSize = maxLogSize, logSize > maxLogSize {
                    let lineCount = lines.count
                    repeat {
                        logSize -= lines.removeFirst().count
                    } while logSize > maxLogSize
                    let removedLineCount = lineCount - lines.count
                    logger.warning("\(exclusionMessage) due to exceeding the log size limit", metadata: [MetadataKey.excludedLogEntryCount: "\(removedLineCount)", MetadataKey.maxLogSize: "\(maxLogSize)"])
                }
                
                let decoder = JSONDecoder()
                var logEntries = lines.compactMap { try? decoder.decode(GoogleCloudLogging.Log.Entry.self, from: $0) }
                let undecodedLogEntryCount = lines.count - logEntries.count
                if undecodedLogEntryCount > 0 {
                    logger.warning("\(exclusionMessage) due to decoding failure", metadata: [MetadataKey.excludedLogEntryCount: "\(undecodedLogEntryCount)"])
                }
                
                if let retentionPeriod = retentionPeriod {
                    let logEntryCount = logEntries.count
                    logEntries.removeAll { $0.timestamp.map { -$0.timeIntervalSinceNow > retentionPeriod } ?? false }
                    let removedLogEntryCount = logEntryCount - logEntries.count
                    if removedLogEntryCount > 0 {
                        logger.warning("\(exclusionMessage) due to exceeding the retention period", metadata: [MetadataKey.excludedLogEntryCount: "\(removedLogEntryCount)", MetadataKey.retentionPeriod: "\(retentionPeriod)"])
                    }
                }
                
                func deleteOldEntries() {
                    do {
                        try (fileHandle.legacyReadToEnd() ?? Data()).write(to: logFile, options: .atomic)
                        logger.debug("Uploaded logs have been deleted")
                    } catch {
                        logger.error("Unable to delete uploaded logs", metadata: [MetadataKey.error: "\(error)"])
                    }
                }
                
                func updateOldEntries() {
                    do {
                        if lineCount != logEntries.count {
                            let encoder = JSONEncoder()
                            var lines = logEntries.compactMap { try? encoder.encode($0) }
                            if let data = try fileHandle.legacyReadToEnd(), !data.isEmpty {
                                lines.append(data)
                            }
                            try Data(lines.joined(separator: [.newline])).write(to: logFile, options: .atomic)
                            logger.debug("Overflowed or expired logs have been deleted")
                        } else {
                            logger.debug("No overflowed or expired logs to delete")
                        }
                    } catch {
                        logger.error("Unable to delete overflowed or expired logs", metadata: [MetadataKey.error: "\(error)"])
                    }
                }
                
                guard let logging = logging else {
                    logger.critical("Attempt to upload logs without GoogleCloudLogHandler setup")
                    updateOldEntries()
                    return
                }
                
                logging.write(entries: logEntries) { result in
                    fileHandleQueue.async {
                        switch result {
                        case .success:
                            logger.info("Logs have been uploaded")
                            deleteOldEntries()
                        case .failure(let error):
                            switch error {
                            case let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorNotConnectedToInternet:
                                logger.notice("Logs cannot be uploaded without an internet connection")
                            case let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut:
                                logger.notice("Logs may not have been uploaded due to poor internet connection")
                            case GoogleCloudLogging.EntriesWriteError.noEntriesToSend:
                                logger.notice("No relevant logs to upload")
                            default:
                                logger.error("Unable to upload logs", metadata: [MetadataKey.error: "\(error)"])
                            }
                            updateOldEntries()
                        }
                    }
                }
            } catch {
                logger.error("Unable to read saved logs", metadata: [MetadataKey.error: "\(error)"])
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
        if #available(OSX 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
            return try seekToEnd()
        } else {
            return seekToEndOfFile()
        }
    }
    
    func legacyWrite<T>(contentsOf data: T) throws where T : DataProtocol {
        if #available(OSX 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
            try write(contentsOf: data)
        } else {
            write(Data(data))
        }
    }
    
    func legacyReadToEnd() throws -> Data? {
        if #available(OSX 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
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



extension Dictionary {
    
    mutating func update(with other: [Key : Value]) -> [Key : Value] {
        var replaced = [Key : Value]()
        self = other.reduce(into: self) { replaced[$1.key] = $0.updateValue($1.value, forKey: $1.key) }
        return replaced
    }
}



extension GoogleCloudLogHandler.MetadataKey {
    
    static let serviceAccountCredentials = "serviceAccountCredentials"
    static let logFile = "logFile"
    static let label = "label"
    static let replacedMetadata = "replacedMetadata"
    static let logEntry = "logEntry"
    static let excludedLogEntryCount = "excludedLogEntryCount"
    static let maxLogEntrySize = "maxLogEntrySize"
    static let maxLogSize = "maxLogSize"
    static let retentionPeriod = "retentionPeriod"
    static let uploadInterval = "uploadInterval"
}
