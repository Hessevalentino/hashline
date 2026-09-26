import Foundation

/// OpenAI Responses: request body and stream decoding (shapes from the official SDK's types,
/// 2026-09-26). Stateless: `store: false`, and reasoning comes back encrypted so a turn can
/// continue after tool calls without OpenAI keeping the conversation.
public enum OpenAIResponses {
    static let maxOutputTokens = 32_000

    public static func urlRequest(_ request: AssistantRequest, apiKey: String) -> URLRequest {
        let provider = request.model.provider
        var urlRequest = URLRequest(url: provider.baseURL.appending(path: "v1/responses"))
        urlRequest.httpMethod = "POST"
        for (field, value) in provider.headers(apiKey: apiKey) {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = body(request).encoded()
        urlRequest.timeoutInterval = 120
        return urlRequest
    }

    public static func body(_ request: AssistantRequest) -> JSONValue {
        var input: [JSONValue] = []
        for (index, turn) in request.turns.enumerated() {
            switch turn.role {
            case .user:
                var content: [JSONValue] = []
                // The document first: the automatic prompt cache keeps the shared prefix.
                if index == 0 {
                    content.append(["type": "input_text",
                                    "text": .string(AnthropicMessages.documentBlock(request.document))])
                }
                content.append(["type": "input_text", "text": .string(turn.text)])
                input.append(["type": "message", "role": "user", "content": .array(content)])
            case .assistant:
                input.append(["type": "message", "role": "assistant", "content": .string(turn.text)])
            }
        }
        input += request.continuation

        var body: [String: JSONValue] = [
            "model": .string(request.model.id),
            "instructions": .string(request.instructions),
            "input": .array(input),
            "stream": true,
            "store": false,
            "include": ["reasoning.encrypted_content"],
            "max_output_tokens": .number(Double(maxOutputTokens)),
        ]
        var tools: [JSONValue] = request.tools.map { tool in
            [
                "type": "function",
                "name": .string(tool.name),
                "description": .string(tool.description),
                "parameters": tool.inputSchema,
                "strict": true,
            ]
        }
        if request.webSearch, request.model.webSearch == .openAI { tools.append(["type": "web_search"]) }
        if !tools.isEmpty { body["tools"] = .array(tools) }
        return .object(body)
    }

    /// The response's output items, then the results of the app's tools.
    public static func continuation(content: [JSONValue], results: [AssistantToolResult]) -> [JSONValue] {
        content + results.map { result in
            [
                "type": "function_call_output",
                "call_id": .string(result.callID),
                // The protocol has no error flag; the prefix tells the model.
                "output": .string(result.isError ? "Error: \(result.text)" : result.text),
            ]
        }
    }
}

/// Decodes one streamed Responses answer into events and keeps its output items for a continuation.
public struct OpenAIStreamDecoder: AssistantStreamDecoding {
    private var items: [Int: JSONValue] = [:]
    private var hasToolCalls = false

    public init() {}

    public var content: [JSONValue] {
        items.keys.sorted().compactMap { items[$0] }
    }

    public mutating func decode(_ event: ServerSentEvent) throws -> [AssistantEvent] {
        guard let json = try? JSONValue.parse(event.data), let type = json["type"]?.string else { return [] }
        switch type {
        case "response.output_text.delta", "response.refusal.delta":
            let text = json["delta"]?.string ?? ""
            return text.isEmpty ? [] : [.text(text)]
        case "response.output_text.annotation.added":
            let annotation = json["annotation"]
            guard annotation?["type"]?.string == "url_citation", let url = annotation?["url"]?.string else { return [] }
            return [.citation(title: annotation?["title"]?.string ?? url, url: url)]
        case "response.output_item.done":
            guard let index = json["output_index"]?.int, let item = json["item"] else { return [] }
            items[index] = item
            return events(forFinished: item)
        case "response.completed", "response.incomplete":
            return finish(json["response"])
        case "response.failed":
            let message = json["response"]?["error"]?["message"]?.string ?? "The response failed."
            throw AssistantError(message: message)
        case "error":
            throw AssistantError(message: json["message"]?.string ?? event.data)
        default:
            return []
        }
    }

    private mutating func events(forFinished item: JSONValue) -> [AssistantEvent] {
        switch item["type"]?.string {
        case "function_call":
            hasToolCalls = true
            let id = item["call_id"]?.string ?? ""
            let name = item["name"]?.string ?? ""
            let arguments = item["arguments"]?.string ?? ""
            guard let input = try? JSONValue.parse(arguments), case .object = input else {
                return [.invalidToolCall(id: id, name: name, input: arguments)]
            }
            return [.toolCall(id: id, name: name, input: input)]
        case "web_search_call":
            let action = item["action"]
            guard action?["type"]?.string == "search" else { return [] }
            let queries = action?["queries"]?.array?.compactMap(\.string).joined(separator: ", ")
            let query = action?["query"]?.string ?? queries
            return [.searching(query: query ?? "")]
        default:
            return []
        }
    }

    private func finish(_ response: JSONValue?) -> [AssistantEvent] {
        let usage = response?["usage"]
        let stop: AssistantStopReason
        switch response?["incomplete_details"]?["reason"]?.string {
        case "max_output_tokens": stop = .maxTokens
        case "content_filter": stop = .refusal
        case let reason?: stop = .other(reason)
        case nil: stop = hasToolCalls ? .toolUse : .endTurn
        }
        return [
            .usage(AssistantUsage(inputTokens: usage?["input_tokens"]?.int ?? 0,
                                  outputTokens: usage?["output_tokens"]?.int ?? 0,
                                  cachedInputTokens: usage?["input_tokens_details"]?["cached_tokens"]?.int ?? 0)),
            .finished(stop),
        ]
    }
}
