//
//  GoogleCloudLogging.swift
//  GoogleCloudLogging
//
//  Created by Alexey Demin on 2020-04-27.
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


class GoogleCloudLogging {
    
    enum InitError: Error {
        case wrongCredentialsType(Credentials)
    }
    
    enum TokenRequestError: Error {
        case invalidURL(String)
        case noDataReceived(URLResponse?)
        case errorReceived(Response.Error)
        case wrongTokenType(Token)
    }
    
    enum EntriesWriteError: Error {
        case noEntriesToSend
        case tokenExpired(Token)
        case noDataReceived(URLResponse?)
        case errorReceived(Response.Error)
    }
    
    
    struct Credentials: Decodable {
        enum CodingKeys: String, CodingKey {
            case type = "type"
            case projectId = "project_id"
            case privateKeyId = "private_key_id"
            case privateKey = "private_key"
            case clientEmail = "client_email"
            case clientId = "client_id"
            case authURI = "auth_uri"
            case tokenURI = "token_uri"
            case authProviderX509CertURL = "auth_provider_x509_cert_url"
            case clientX509CertURL = "client_x509_cert_url"
        }
        let type: String
        let projectId: String
        let privateKeyId: String
        let privateKey: String
        let clientEmail: String
        let clientId: String
        let authURI: String
        let tokenURI: String
        let authProviderX509CertURL: String
        let clientX509CertURL: String
    }
    
    
    enum Scope: String {
        case loggingWrite = "https://www.googleapis.com/auth/logging.write"
    }
    
    
    enum JWT {
        
        enum KeyError: Error {
            case unableToDecode(from: String)
        }
        
        struct Header: Encodable {
            enum CodingKeys: String, CodingKey {
                case type = "typ"
                case algorithm = "alg"
            }
            let type: String
            let algorithm: String
        }
        
        struct Payload: Encodable {
            enum CodingKeys: String, CodingKey {
                case issuer = "iss"
                case audience = "aud"
                case expiration = "exp"
                case issuedAt = "iat"
                case scope = "scope"
            }
            let issuer: String
            let audience: String
            let expiration: Int
            let issuedAt: Int
            let scope: String
        }
        
        static func create(using credentials: Credentials, for scopes: [Scope]) throws -> String {
            
            let header = Header(type: "JWT", algorithm: "RS256")
            let now = Date()
            let payload = Payload(issuer: credentials.clientEmail,
                                  audience: credentials.tokenURI,
                                  expiration: Int(now.addingTimeInterval(3600).timeIntervalSince1970),
                                  issuedAt: Int(now.timeIntervalSince1970),
                                  scope: scopes.map(\.rawValue).joined(separator: " "))
            let encoder = JSONEncoder()
            let encodedHeader = try encoder.encode(header).base64URLEncodedString()
            let encodedPayload = try encoder.encode(payload).base64URLEncodedString()
            let privateKey = try key(from: credentials.privateKey)
            let signature = try sign(Data("\(encodedHeader).\(encodedPayload)".utf8), with: privateKey)
            let encodedSignature = signature.base64URLEncodedString()
            return "\(encodedHeader).\(encodedPayload).\(encodedSignature)"
        }
        
        static func key(from pem: String) throws -> Data {
            let unwrappedPEM = pem.split(separator: "\n").filter { !$0.contains("PRIVATE KEY") }.joined()
            let headerLength = 26
            guard let der = Data(base64Encoded: unwrappedPEM), der.count > headerLength else { throw KeyError.unableToDecode(from: pem) }
            return der[headerLength...]
        }
        
        static func sign(_ data: Data, with key: Data) throws -> Data {
            var error: Unmanaged<CFError>?
            let attributes = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate, kSecAttrKeySizeInBits: 256] as CFDictionary
            guard let privateKey = SecKeyCreateWithData(key as CFData, attributes, &error) else {
                throw error!.takeRetainedValue() as Error
            }
            guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error) as Data? else {
                throw error!.takeRetainedValue() as Error
            }
            return signature
        }
    }
    
    
    struct Response: Decodable {
        struct Error: Decodable {
            let code: Int
            let message: String
            let status: String
        }
        let error: Error?
    }
    
    
    struct Token: Decodable {
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
        }
        let accessToken: String
        let expiresIn: Int
        let tokenType: String
        
        let receiptDate = Date()
        var isExpired: Bool { receiptDate + TimeInterval(expiresIn) < Date() }
    }
    
    
    struct Log: Encodable {
        struct MonitoredResource: Encodable {
            let type: String
            let labels: [String: String]
            
            static func global(projectId: String) -> MonitoredResource { MonitoredResource(type: "global", labels: ["project_id": projectId]) }
        }
        struct Entry: Codable {
            enum Severity: String, Codable {
                case `default` = "DEFAULT"
                case debug = "DEBUG"
                case info = "INFO"
                case notice = "NOTICE"
                case warning = "WARNING"
                case error = "ERROR"
                case critical = "CRITICAL"
                case alert = "ALERT"
                case emergency = "EMERGENCY"
            }
            struct SourceLocation: Codable {
                let file: String
                let line: String
                let function: String
            }
            let logName: String
            let timestamp: Date?
            let severity: Severity?
            let labels: [String: String]?
            let sourceLocation: SourceLocation?
            let textPayload: String
        }
        let resource: MonitoredResource
        let entries: [Entry]
        
        static func name(projectId: String, logId: String) -> String { "projects/\(projectId)/logs/\(logId)" }
    }
    
    
    let serviceAccountCredentials: Credentials
    
    private var accessToken: Token?
    
    let completionHandlerQueue = DispatchQueue(label: "GoogleCloudLogging.CompletionHandler")
    let accessTokenQueue = DispatchQueue(label: "GoogleCloudLogging.AccessToken")
    
    let session: URLSession

    
    init(serviceAccountCredentials url: URL) throws {
        
        let data = try Data(contentsOf: url)
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        guard credentials.type == "service_account" else { throw InitError.wrongCredentialsType(credentials) }
        
        serviceAccountCredentials = credentials
        
        let operationQueue = OperationQueue()
        operationQueue.underlyingQueue = completionHandlerQueue
        session = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: operationQueue)
    }
    
    
    func requestToken(completionHandler: @escaping (Result<Token, Error>) -> Void) {
        
        completionHandlerQueue.async {
            guard let url = URL(string: self.serviceAccountCredentials.tokenURI) else {
                completionHandler(.failure(TokenRequestError.invalidURL(self.serviceAccountCredentials.tokenURI)))
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                let jwt = try JWT.create(using: self.serviceAccountCredentials, for: [.loggingWrite])
                request.httpBody = try JSONEncoder().encode(["grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": jwt])
            } catch {
                completionHandler(.failure(error))
                return
            }
            
            self.session.dataTask(with: request) { data, response, error in
                completionHandler(Result {
                    if let error = error { throw error }
                    guard let data = data else { throw TokenRequestError.noDataReceived(response) }
                    if let responseError = try JSONDecoder().decode(Response.self, from: data).error { throw TokenRequestError.errorReceived(responseError) }
                    let token = try JSONDecoder().decode(Token.self, from: data)
                    guard token.tokenType == "Bearer" else { throw TokenRequestError.wrongTokenType(token) }
                    return token
                })
            }.resume()
        }
    }
    
    
    func write(entries: [Log.Entry], completionHandler: @escaping (Result<Void, Error>) -> Void) {
        
        accessTokenQueue.async {
            if let token = self.accessToken, !token.isExpired {
                self.write(entries: entries, token: token, completionHandler: completionHandler)
            } else {
                let tokenReference = Referenced<Token>()
                let tokenRequestSemaphore = DispatchSemaphore(value: 0)
                self.requestToken { result in
                    switch result {
                    case let .success(token):
                        tokenReference.wrappedValue = token
                        tokenRequestSemaphore.signal()
                        self.write(entries: entries, token: token, completionHandler: completionHandler)
                    case let .failure(error):
                        tokenRequestSemaphore.signal()
                        completionHandler(.failure(error))
                    }
                }
                tokenRequestSemaphore.wait()
                if let token = tokenReference.wrappedValue {
                    self.accessToken = token
                }
            }
        }
    }
    
    
    func write(entries: [Log.Entry], token: Token, completionHandler: @escaping (Result<Void, Error>) -> Void) {
        
        completionHandlerQueue.async {
            guard !entries.isEmpty else {
                completionHandler(.failure(EntriesWriteError.noEntriesToSend))
                return
            }
            guard !token.isExpired else {
                completionHandler(.failure(EntriesWriteError.tokenExpired(token)))
                return
            }
            let url = URL(string: "https://logging.googleapis.com/v2/entries:write")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
                request.httpBody = try encoder.encode(Log(resource: .global(projectId: self.serviceAccountCredentials.projectId), entries: entries))
            } catch {
                completionHandler(.failure(error))
                return
            }
            
            self.session.dataTask(with: request) { data, response, error in
                completionHandler(Result {
                    if let error = error { throw error }
                    guard let data = data else { throw EntriesWriteError.noDataReceived(response) }
                    if let responseError = try JSONDecoder().decode(Response.self, from: data).error { throw EntriesWriteError.errorReceived(responseError) }
                })
            }.resume()
        }
    }
}



extension Data {
    
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}



extension JSONEncoder.DateEncodingStrategy {
    
    static let iso8601WithFractionalSeconds = custom { date, encoder in
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var container = encoder.singleValueContainer()
        try container.encode(dateFormatter.string(from: date))
    }
}



@propertyWrapper
class Referenced<T> {
    var wrappedValue: T?
}
