//
//  SSEService.swift
//  Ash
//

import Foundation

enum SSEEvent: Sendable {
    case message(SSEMessageEvent)
    case delivered(SSEDeliveredEvent)
    case burned(Date)
    case ping
    case error(Error)
    case connected
    case disconnected
}

struct SSEMessageEvent: Sendable {
    let id: UUID
    let sequence: UInt64?
    let ciphertext: Data
    let receivedAt: Date
}

struct SSEDeliveredEvent: Sendable {
    let blobIds: [UUID]
    let deliveredAt: Date
}

protocol SSEServiceProtocol: Sendable {
    func connect(conversationId: String, authToken: String) -> AsyncStream<SSEEvent>
    func disconnect()
}

final class SSEService: NSObject, SSEServiceProtocol, @unchecked Sendable {
    private let baseURL: URL
    private var task: URLSessionDataTask?
    private var continuation: AsyncStream<SSEEvent>.Continuation?
    private var buffer = ""
    private var currentConversationId: String?
    private var hasReceivedData = false
    private var delegateSession: URLSession?

    private var logId: String {
        currentConversationId.map { String($0.prefix(8)) } ?? "none"
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
        super.init()
        Log.debug(.sse, "SSE service initialized: \(baseURL.host ?? "unknown")")
    }

    convenience init?(baseURLString: String) {
        guard let url = URL(string: baseURLString) else { return nil }
        self.init(baseURL: url)
    }

    func connect(conversationId: String, authToken: String) -> AsyncStream<SSEEvent> {
        // Clean up without yielding events (we're creating a new stream)
        cleanupConnection()
        currentConversationId = conversationId
        hasReceivedData = false

        return AsyncStream { [weak self] continuation in
            self?.continuation = continuation

            guard let self = self else {
                continuation.finish()
                return
            }

            var components = URLComponents(url: self.baseURL.appendingPathComponent("v1/messages/stream"), resolvingAgainstBaseURL: true)!
            components.queryItems = [URLQueryItem(name: "conversation_id", value: conversationId)]

            guard let url = components.url else {
                Log.error(.sse, "[\(self.logId)] Invalid SSE URL")
                continuation.yield(.error(RelayError.invalidURL))
                continuation.finish()
                return
            }

            Log.info(.sse, "[\(self.logId)] Connecting to SSE stream")

            var request = URLRequest(url: url)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

            let delegate = SSEDelegate(service: self)
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = TimeInterval.infinity
            config.timeoutIntervalForResource = TimeInterval.infinity
            self.delegateSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            self.task = self.delegateSession?.dataTask(with: request)
            self.task?.resume()

            // Note: .connected is NOT yielded here - it's yielded when we receive first data

            continuation.onTermination = { [weak self] _ in
                self?.cleanupConnection()
            }
        }
    }

    /// Clean up connection without yielding events (used internally)
    private func cleanupConnection() {
        task?.cancel()
        task = nil
        delegateSession?.invalidateAndCancel()
        delegateSession = nil
        continuation?.finish()
        continuation = nil
        buffer = ""
    }

    func disconnect() {
        if task != nil {
            Log.info(.sse, "[\(logId)] Disconnecting SSE stream")
        }
        task?.cancel()
        task = nil
        delegateSession?.invalidateAndCancel()
        delegateSession = nil
        continuation?.yield(.disconnected)
        continuation?.finish()
        continuation = nil
        buffer = ""
        currentConversationId = nil
        hasReceivedData = false
    }

    fileprivate func processData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }

        // Yield .connected on first data received (actual connection established)
        if !hasReceivedData {
            hasReceivedData = true
            Log.info(.sse, "[\(logId)] Connection established (received first data)")
            continuation?.yield(.connected)
        }

        buffer += string

        while let range = buffer.range(of: "\n\n") {
            let eventString = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])

            if let event = parseEvent(eventString) {
                continuation?.yield(event)
            }
        }
    }

    private func parseEvent(_ eventString: String) -> SSEEvent? {
        var eventType: String?
        var data: String?

        for line in eventString.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)

            if lineStr.hasPrefix("event:") {
                eventType = String(lineStr.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if lineStr.hasPrefix("data:") {
                let dataValue = String(lineStr.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if data == nil {
                    data = dataValue
                } else {
                    data! += "\n" + dataValue
                }
            } else if lineStr == "ping" || lineStr.contains(":ping") {
                return .ping
            }
        }

        guard let jsonString = data,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        return parseEventData(jsonData, eventType: eventType)
    }

    private func parseEventData(_ data: Data, eventType: String?) -> SSEEvent? {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dateString) {
                    return date
                }

                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
            }

            let rawEvent = try decoder.decode(RawSSEEvent.self, from: data)

            switch rawEvent.type {
            case "message":
                if let id = rawEvent.id,
                   let ciphertextBase64 = rawEvent.ciphertext,
                   let ciphertext = Data(base64Encoded: ciphertextBase64),
                   let receivedAt = rawEvent.received_at {
                    let message = SSEMessageEvent(
                        id: id,
                        sequence: rawEvent.sequence,
                        ciphertext: ciphertext,
                        receivedAt: receivedAt
                    )
                    Log.debug(.sse, "[\(logId)] Received message: \(ciphertext.count) bytes, seq=\(rawEvent.sequence ?? 0)")
                    return .message(message)
                }

            case "delivered":
                if let blobIds = rawEvent.blob_ids,
                   let deliveredAt = rawEvent.delivered_at {
                    let event = SSEDeliveredEvent(blobIds: blobIds, deliveredAt: deliveredAt)
                    Log.debug(.sse, "[\(logId)] Received delivery confirmation for \(blobIds.count) messages")
                    return .delivered(event)
                }

            case "burned":
                if let burnedAt = rawEvent.burned_at {
                    Log.warning(.sse, "[\(logId)] Received burn event")
                    return .burned(burnedAt)
                }

            case "ping":
                return .ping

            default:
                Log.warning(.sse, "[\(logId)] Unknown event type: \(rawEvent.type)")
            }
        } catch {
            Log.error(.sse, "[\(logId)] Failed to parse event: \(error)")
        }

        return nil
    }

    fileprivate func handleError(_ error: Error) {
        Log.error(.sse, "[\(logId)] Connection error: \(error.localizedDescription)")
        continuation?.yield(.error(error))
    }

    fileprivate func handleCompletion() {
        Log.info(.sse, "[\(logId)] Connection completed")
        continuation?.yield(.disconnected)
    }
}

private final class SSEDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    weak var service: SSEService?

    init(service: SSEService) {
        self.service = service
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        service?.processData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            service?.handleError(error)
        } else {
            service?.handleCompletion()
        }
    }
}

private struct RawSSEEvent: Decodable {
    let type: String
    let id: UUID?
    let sequence: UInt64?
    let ciphertext: String?
    let received_at: Date?
    let burned_at: Date?
    // For delivered events
    let blob_ids: [UUID]?
    let delivered_at: Date?
}
