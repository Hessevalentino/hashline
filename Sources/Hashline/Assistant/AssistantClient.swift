import Foundation
import HashlineCore
import os

/// Network side of the assistant: streams one response and checks keys. Runs off the main thread;
/// nothing here keeps a connection or a timer once a response ends (idle CPU 0 %).
enum AssistantClient {
    static let logger = Logger(subsystem: Performance.subsystem, category: "assistant")

    /// Streams the events of one response. Cancelling the consuming task closes the connection.
    static func stream(_ request: AssistantRequest, apiKey: String) -> AsyncThrowingStream<AssistantEvent, Error> {
        #if DEBUG || HASHLINE_TEST_HOOKS
        if AssistantFake.isEnabled { return AssistantFake.stream(request) }
        #endif
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await run(request, apiKey: apiKey, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(_ request: AssistantRequest, apiKey: String,
                            into continuation: AsyncThrowingStream<AssistantEvent, Error>.Continuation) async throws {
        let wireProtocol = request.model.provider.wireProtocol
        let (bytes, response) = try await URLSession.shared.bytes(for: wireProtocol.urlRequest(request, apiKey: apiKey))
        try await checkStatus(response, bytes: bytes)
        var parser = ServerSentEventParser()
        var decoder = wireProtocol.makeDecoder()
        for try await line in bytes.lines {
            guard let event = parser.feed(line) else { continue }
            for decoded in try decoder.decode(event) { continuation.yield(decoded) }
        }
        if let event = parser.finish() {
            for decoded in try decoder.decode(event) { continuation.yield(decoded) }
        }
        continuation.yield(.assistantContent(decoder.content))
    }

    private static func checkStatus(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count > 16_384 { break }
        }
        let error = AssistantError(status: http.statusCode, body: String(bytes: body, encoding: .utf8) ?? "")
        logger.error("Assistant request failed: \(http.statusCode) \(error.message, privacy: .public)")
        throw error
    }

    /// Checks a key by listing the provider's models (no tokens are spent).
    static func verify(_ apiKey: String, provider: AssistantProvider) async -> Result<Void, AssistantError> {
        do {
            let (data, response) = try await URLSession.shared.data(for: provider.modelsRequest(apiKey: apiKey))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                return .failure(AssistantError(status: status, body: String(bytes: data, encoding: .utf8) ?? ""))
            }
            return .success(())
        } catch {
            return .failure(AssistantError(message: error.localizedDescription))
        }
    }
}
