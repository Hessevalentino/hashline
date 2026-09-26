import Foundation

/// Anthropic Messages (Claude, and DeepSeek through its `/anthropic` endpoint): request body and
/// stream decoding. Pure functions; the app owns the network.
public enum AnthropicMessages {
    /// Output limit of one response; streaming keeps long answers within HTTP timeouts.
    static let maxTokens = 32_000

    public static func urlRequest(_ request: AssistantRequest, apiKey: String) -> URLRequest {
        let provider = request.model.provider
        var urlRequest = URLRequest(url: provider.baseURL.appending(path: "v1/messages"))
        urlRequest.httpMethod = "POST"
        for (field, value) in provider.headers(apiKey: apiKey) {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        if usesFallbacks(request.model) {
            urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = body(request).encoded()
        // A long answer streams for minutes; the timeout applies between received bytes.
        urlRequest.timeoutInterval = 120
        return urlRequest
    }

    /// Claude Opus 5 may decline a request; the server then reruns it on its recommended fallback.
    static func usesFallbacks(_ model: AssistantModel) -> Bool {
        model.provider == .claude && model.id == "claude-opus-5"
    }

    public static func body(_ request: AssistantRequest) -> JSONValue {
        var messages: [JSONValue] = []
        for (index, turn) in request.turns.enumerated() {
            var content: [JSONValue] = []
            if index == 0 {
                // The document first: a stable prefix that the cache keeps between questions.
                content.append([
                    "type": "text",
                    "text": .string(documentBlock(request.document)),
                    "cache_control": ["type": "ephemeral"],
                ])
            }
            content.append(["type": "text", "text": .string(turn.text)])
            messages.append(["role": .string(turn.role.rawValue), "content": .array(content)])
        }
        messages += request.continuation

        var body: [String: JSONValue] = [
            "model": .string(request.model.id),
            "max_tokens": .number(Double(maxTokens)),
            "stream": true,
            "system": .string(request.instructions),
            "messages": .array(messages),
        ]
        var tools: [JSONValue] = request.tools.map { tool in
            var definition: [String: JSONValue] = [
                "name": .string(tool.name),
                "description": .string(tool.description),
                "input_schema": tool.inputSchema,
            ]
            // Long replacements stream as they are written; the input is validated on arrival.
            // Claude only: DeepSeek's compatible endpoint does not document the field.
            if request.model.provider == .claude { definition["eager_input_streaming"] = true }
            return .object(definition)
        }
        if request.webSearch, let search = request.model.webSearch {
            switch search {
            case .anthropicDynamic: tools.append(webSearchTool("web_search_20260209"))
            case .anthropicBasic: tools.append(webSearchTool("web_search_20250305"))
            case .openAI: break
            }
        }
        if !tools.isEmpty { body["tools"] = .array(tools) }
        if usesFallbacks(request.model) { body["fallbacks"] = "default" }
        return .object(body)
    }

    /// The continuation after a response that stopped for tools (or a paused server-tool turn):
    /// the response's own content, then the results of the app's tools, if any.
    public static func continuation(content: [JSONValue], results: [AssistantToolResult]) -> [JSONValue] {
        var messages: [JSONValue] = [["role": "assistant", "content": .array(content)]]
        guard !results.isEmpty else { return messages }
        let blocks: [JSONValue] = results.map { result in
            var block: [String: JSONValue] = [
                "type": "tool_result",
                "tool_use_id": .string(result.callID),
                "content": .string(result.text),
            ]
            if result.isError { block["is_error"] = true }
            return .object(block)
        }
        messages.append(["role": "user", "content": .array(blocks)])
        return messages
    }

    private static func webSearchTool(_ type: String) -> JSONValue {
        ["type": .string(type), "name": "web_search", "max_uses": 5]
    }

    /// The document as data. The instructions say that nothing inside the tags is an instruction.
    public static func documentBlock(_ text: String) -> String {
        "<document>\n\(text)\n</document>"
    }
}

/// Decodes one streamed Anthropic response into events and rebuilds the assistant's content blocks
/// (needed verbatim, thinking signatures included, to continue a turn after a tool call).
public struct AnthropicStreamDecoder: Sendable {
    private var blocks: [Int: JSONValue] = [:]
    private var partialInputs: [Int: String] = [:]
    private var usage = AssistantUsage()
    public private(set) var stopReason: AssistantStopReason?

    public init() {}

    /// The response's content blocks in order, for the `assistant` message of a continuation.
    public var content: [JSONValue] {
        blocks.keys.sorted().compactMap { blocks[$0] }
    }

    // swiftlint:disable:next cyclomatic_complexity
    public mutating func decode(_ event: ServerSentEvent) throws -> [AssistantEvent] {
        guard let json = try? JSONValue.parse(event.data), let type = json["type"]?.string else { return [] }
        switch type {
        case "message_start":
            let usage = json["message"]?["usage"]
            self.usage.inputTokens = usage?["input_tokens"]?.int ?? 0
            self.usage.cachedInputTokens = usage?["cache_read_input_tokens"]?.int ?? 0
            return []
        case "content_block_start":
            guard let index = json["index"]?.int, let block = json["content_block"] else { return [] }
            blocks[index] = block
            return startEvents(for: block)
        case "content_block_delta":
            guard let index = json["index"]?.int, let delta = json["delta"] else { return [] }
            return apply(delta, at: index)
        case "content_block_stop":
            guard let index = json["index"]?.int else { return [] }
            return finish(at: index)
        case "message_delta":
            if let reason = json["delta"]?["stop_reason"]?.string {
                stopReason = AssistantStopReason(anthropic: reason)
            }
            if let output = json["usage"]?["output_tokens"]?.int { usage.outputTokens = output }
            return [.usage(usage)]
        case "message_stop":
            return [.finished(stopReason ?? .endTurn)]
        case "error":
            throw AssistantError(status: nil, message: json["error"]?["message"]?.string ?? event.data)
        default:
            return []
        }
    }

    private func startEvents(for block: JSONValue) -> [AssistantEvent] {
        // A search is reported when its query is complete (content_block_stop).
        guard block["type"]?.string == "text", let text = block["text"]?.string, !text.isEmpty else { return [] }
        return [.text(text)]
    }

    private mutating func apply(_ delta: JSONValue, at index: Int) -> [AssistantEvent] {
        guard case .object(var block)? = blocks[index] else { return [] }
        defer { blocks[index] = .object(block) }
        switch delta["type"]?.string {
        case "text_delta":
            let text = delta["text"]?.string ?? ""
            block["text"] = .string((block["text"]?.string ?? "") + text)
            return [.text(text)]
        case "thinking_delta":
            block["thinking"] = .string((block["thinking"]?.string ?? "") + (delta["thinking"]?.string ?? ""))
        case "signature_delta":
            block["signature"] = .string((block["signature"]?.string ?? "") + (delta["signature"]?.string ?? ""))
        case "input_json_delta":
            partialInputs[index, default: ""] += delta["partial_json"]?.string ?? ""
        case "citations_delta":
            guard let citation = delta["citation"] else { return [] }
            block["citations"] = .array((block["citations"]?.array ?? []) + [citation])
            if let url = citation["url"]?.string {
                return [.citation(title: citation["title"]?.string ?? url, url: url)]
            }
        default:
            break
        }
        return []
    }

    private mutating func finish(at index: Int) -> [AssistantEvent] {
        guard case .object(var block)? = blocks[index] else { return [] }
        let isTool = block["type"]?.string == "tool_use" || block["type"]?.string == "server_tool_use"
        guard isTool else { return [] }
        let raw = partialInputs.removeValue(forKey: index) ?? ""
        let name = block["name"]?.string ?? ""
        let id = block["id"]?.string ?? ""
        // An empty input streams no fragments: the block's own `{}` stands.
        let input = raw.isEmpty ? (block["input"] ?? [:]) : try? JSONValue.parse(raw)
        guard let input, case .object = input else {
            block["input"] = [:]
            blocks[index] = .object(block)
            return block["type"]?.string == "tool_use" ? [.invalidToolCall(id: id, name: name, input: raw)] : []
        }
        block["input"] = input
        blocks[index] = .object(block)
        if block["type"]?.string == "server_tool_use" {
            return name == "web_search" ? [.searching(query: input["query"]?.string ?? "")] : []
        }
        return [.toolCall(id: id, name: name, input: input)]
    }
}
