import Foundation

/// Turns the events of one streamed response into assistant events.
public protocol AssistantStreamDecoding: Sendable {
    mutating func decode(_ event: ServerSentEvent) throws -> [AssistantEvent]
    /// The response's provider-native content, for continuing the turn after tool calls.
    var content: [JSONValue] { get }
}

extension AnthropicStreamDecoder: AssistantStreamDecoding {}

/// One entry point per wire protocol, so the app does not branch on the provider.
extension AssistantProtocol {
    public func urlRequest(_ request: AssistantRequest, apiKey: String) -> URLRequest {
        switch self {
        case .anthropicMessages: AnthropicMessages.urlRequest(request, apiKey: apiKey)
        case .openAIResponses: OpenAIResponses.urlRequest(request, apiKey: apiKey)
        }
    }

    public func makeDecoder() -> any AssistantStreamDecoding {
        switch self {
        case .anthropicMessages: AnthropicStreamDecoder()
        case .openAIResponses: OpenAIStreamDecoder()
        }
    }

    public func continuation(content: [JSONValue], results: [AssistantToolResult]) -> [JSONValue] {
        switch self {
        case .anthropicMessages: AnthropicMessages.continuation(content: content, results: results)
        case .openAIResponses: OpenAIResponses.continuation(content: content, results: results)
        }
    }
}
