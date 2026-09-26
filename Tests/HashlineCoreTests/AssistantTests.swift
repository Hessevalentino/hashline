import Foundation
import Testing
@testable import HashlineCore

struct AssistantTests {
    // MARK: Server-sent events

    /// `URLSession.bytes(for:).lines` drops the blank lines between events.
    @Test func parsesEventsWithoutBlankLines() {
        var parser = ServerSentEventParser()
        let lines = [
            "event: message_start", #"data: {"type":"message_start"}"#,
            ": keep-alive",
            "event: ping", #"data: {"type": "ping"}"#,
        ]
        let events = lines.compactMap { parser.feed($0) }
        #expect(events == [
            ServerSentEvent(event: "message_start", data: #"{"type":"message_start"}"#),
            ServerSentEvent(event: "ping", data: #"{"type": "ping"}"#),
        ])
        #expect(parser.finish() == nil)
    }

    @Test func joinsMultilineData() {
        var parser = ServerSentEventParser()
        #expect(parser.feed("data: first") == nil)
        #expect(parser.feed("data:second") == nil)
        #expect(parser.feed("") == ServerSentEvent(data: "first\nsecond"))
    }

    // MARK: Request

    static let opus = AssistantModel.model(forKey: "claude/claude-opus-5")
    static let deepSeek = AssistantModel.model(forKey: "deepseek/deepseek-v4-pro")

    @Test func bodyPutsTheDocumentFirstAndCachesIt() throws {
        let model = try #require(Self.opus)
        let request = AssistantRequest(
            model: model, instructions: "Help.", document: "# Notes",
            turns: [AssistantTurn(role: .user, text: "Shorten it."),
                    AssistantTurn(role: .assistant, text: "Done."),
                    AssistantTurn(role: .user, text: "Thanks")],
            webSearch: true)
        let body = AnthropicMessages.body(request)
        #expect(body["model"] == "claude-opus-5")
        #expect(body["stream"] == true)
        #expect(body["fallbacks"] == "default")
        let messages = try #require(body["messages"]?.array)
        #expect(messages.count == 3)
        let first = try #require(messages[0]["content"]?.array)
        #expect(first[0]["text"] == "<document>\n# Notes\n</document>")
        #expect(first[0]["cache_control"] == ["type": "ephemeral"])
        #expect(first[1]["text"] == "Shorten it.")
        #expect(messages[1]["content"]?.array?.count == 1)
        #expect(body["tools"]?.array?.first?["type"] == "web_search_20260209")

        let encoded = String(bytes: body.encoded(), encoding: .utf8) ?? ""
        #expect(encoded.contains(#""max_tokens":32000"#))
    }

    @Test func deepSeekGetsNoFallbacksAndNoSearch() throws {
        let model = try #require(Self.deepSeek)
        let request = AssistantRequest(model: model, instructions: "", document: "",
                                       turns: [AssistantTurn(role: .user, text: "Hi")], webSearch: true)
        let urlRequest = AnthropicMessages.urlRequest(request, apiKey: "sk-test")
        #expect(urlRequest.url?.absoluteString == "https://api.deepseek.com/anthropic/v1/messages")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let body = AnthropicMessages.body(request)
        #expect(body["fallbacks"] == nil)
        #expect(body["tools"] == nil)
    }

    // MARK: Stream

    /// Decodes a recorded stream from the test resources, line by line as `URLSession` delivers it
    /// (without blank lines).
    private func decode(_ name: String) throws -> (events: [AssistantEvent], decoder: AnthropicStreamDecoder) {
        try Self.decode(name, with: AnthropicStreamDecoder())
    }

    static func decode<Decoder: AssistantStreamDecoding>(_ name: String, with decoder: Decoder) throws
        -> (events: [AssistantEvent], decoder: Decoder) {
        var decoder = decoder
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "sse", subdirectory: "Resources"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        var parser = ServerSentEventParser()
        var events: [AssistantEvent] = []
        for line in lines {
            if let event = parser.feed(line) { events += try decoder.decode(event) }
        }
        if let event = parser.finish() { events += try decoder.decode(event) }
        return (events, decoder)
    }

    @Test func decodesTextUsageAndStop() throws {
        let (events, decoder) = try decode("anthropic-text")
        #expect(events == [
            .text("Ahoj"), .text(" světe"),
            .usage(AssistantUsage(inputTokens: 120, outputTokens: 7, cachedInputTokens: 100)),
            .finished(.endTurn),
        ])
        #expect(decoder.content == [["type": "text", "text": "Ahoj světe"]])
    }

    @Test func rebuildsThinkingAndToolCalls() throws {
        let (events, decoder) = try decode("anthropic-tool")
        let input: JSONValue = ["original": "a", "replacement": "b"]
        #expect(events.first == .toolCall(id: "toolu_1", name: "edit_document", input: input))
        #expect(decoder.stopReason == .toolUse)
        #expect(decoder.content == [
            ["type": "thinking", "thinking": "", "signature": "abc"],
            ["type": "tool_use", "id": "toolu_1", "name": "edit_document", "input": input],
        ])
    }

    @Test func reportsCutOffToolInput() throws {
        let (events, _) = try decode("anthropic-cut-tool")
        #expect(events == [.invalidToolCall(id: "t", name: "edit_document", input: #"{"original": "a"#)])
    }

    @Test func reportsSearchesAndCitations() throws {
        let (events, _) = try decode("anthropic-search")
        #expect(events == [.searching(query: "Brno population"),
                           .citation(title: "Brno", url: "https://example.com/brno")])
    }

    @Test func streamErrorThrows() {
        var decoder = AnthropicStreamDecoder()
        let data = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        let event = ServerSentEvent(event: "error", data: data)
        #expect(throws: AssistantError(message: "Overloaded")) { try decoder.decode(event) }
    }

    @Test func errorBodyMessage() {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        let error = AssistantError(status: 401, body: body)
        #expect(error.message == "invalid x-api-key")
        #expect(AssistantError(status: 502, body: "Bad Gateway").message == "Bad Gateway")
    }
}

struct DocumentEditToolTests {
    private typealias Outcome = Result<TextEdit, DocumentEditTools.Failure>

    private func edit(_ name: String, _ input: JSONValue, in text: String) -> Outcome {
        DocumentEditTools.edit(for: name, input: input, in: text as NSString)
    }

    @Test func replacesOnlyTheChangedCharacters() throws {
        let text = "# Title\n\nThe quick brown fox.\n"
        let result = try edit("edit_document", ["original": "quick brown fox", "replacement": "quick red fox"],
                              in: text).get()
        #expect(result.range == NSRange(location: 19, length: 5))
        #expect(result.replacement == "red")
        #expect(result.applied(to: text) == "# Title\n\nThe quick red fox.\n")
        #expect(result.selection == NSRange(location: 19, length: 3))
    }

    @Test func rewriteKeepsTheSharedStartAndEnd() throws {
        let text = "Intro.\n\nOld middle.\n\nOutro.\n"
        let result = try edit("rewrite_document", ["text": "Intro.\n\nNew middle part.\n\nOutro.\n"], in: text).get()
        #expect(result.applied(to: text) == "Intro.\n\nNew middle part.\n\nOutro.\n")
        #expect(result.range.length < 12)
    }

    @Test func neverSplitsComposedCharacters() throws {
        // "é" as e + combining acute: the shared "e" must not be cut off from its accent.
        let text = "cafe au lait"
        let result = try edit("edit_document", ["original": "cafe", "replacement": "cafe\u{301}"], in: text).get()
        #expect(result.applied(to: text) == "cafe\u{301} au lait")
        #expect(result.range == NSRange(location: 3, length: 1))
        let emoji = "Go 👍 now"
        let swap = try edit("edit_document", ["original": "👍", "replacement": "👎"], in: emoji).get()
        #expect(swap.range == NSRange(location: 3, length: 2))
        #expect(swap.applied(to: emoji) == "Go 👎 now")
    }

    @Test func refusesMissingOrAmbiguousPassages() {
        #expect(edit("edit_document", ["original": "absent", "replacement": "x"], in: "text") == .failure(.notFound))
        #expect(edit("edit_document", ["original": "a", "replacement": "b"], in: "a a a")
                == .failure(.ambiguous(count: 3)))
        #expect(edit("edit_document", ["original": "aa", "replacement": "b"], in: "aaa")
                == .failure(.ambiguous(count: 2)))
        #expect(edit("edit_document", ["replacement": "b"], in: "a") == .failure(.invalidInput))
        #expect(edit("delete_file", [:], in: "a") == .failure(.unknownTool("delete_file")))
    }

    @Test func deletion() throws {
        let text = "Keep. Drop this. Keep."
        let result = try edit("edit_document", ["original": " Drop this.", "replacement": ""], in: text).get()
        #expect(result.applied(to: text) == "Keep. Keep.")
    }

    @Test func continuationCarriesContentAndResults() {
        let messages = AnthropicMessages.continuation(
            content: [["type": "tool_use", "id": "t1", "name": "edit_document", "input": [:]]],
            results: [AssistantToolResult(callID: "t1", text: "not found", isError: true)])
        #expect(messages.count == 2)
        #expect(messages[1]["content"]?.array?.first == [
            "type": "tool_result", "tool_use_id": "t1", "content": "not found", "is_error": true,
        ])
        #expect(AnthropicMessages.continuation(content: [], results: []).count == 1)
    }
}

struct OpenAIResponsesTests {
    static let sol = AssistantModel.model(forKey: "openai/gpt-6-sol")

    @Test func bodyIsStatelessWithEncryptedReasoning() throws {
        let model = try #require(Self.sol)
        let request = AssistantRequest(
            model: model, instructions: "Help.", document: "# Notes",
            turns: [AssistantTurn(role: .user, text: "Hi"), AssistantTurn(role: .assistant, text: "Hello"),
                    AssistantTurn(role: .user, text: "Shorten")],
            tools: DocumentEditTools.all, webSearch: true,
            continuation: [["type": "function_call_output", "call_id": "c", "output": "ok"]])
        let urlRequest = OpenAIResponses.urlRequest(request, apiKey: "sk-x")
        #expect(urlRequest.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(urlRequest.value(forHTTPHeaderField: "authorization") == "Bearer sk-x")
        let body = OpenAIResponses.body(request)
        #expect(body["store"] == false)
        #expect(body["include"] == ["reasoning.encrypted_content"])
        #expect(body["instructions"] == "Help.")
        let input = try #require(body["input"]?.array)
        #expect(input.count == 4)
        #expect(input[0]["content"]?.array?.first?["text"] == "<document>\n# Notes\n</document>")
        #expect(input[1] == ["type": "message", "role": "assistant", "content": "Hello"])
        let tools = try #require(body["tools"]?.array)
        #expect(tools.map { $0["type"] } == ["function", "function", "web_search"])
        #expect(tools[0]["strict"] == true)
        #expect(tools[0]["parameters"]?["additionalProperties"] == false)
    }

    @Test func decodesTextSearchCitationAndUsage() throws {
        let (events, _) = try AssistantTests.decode("openai-text", with: OpenAIStreamDecoder())
        #expect(events == [
            .searching(query: "Brno population"),
            .text("Brno has "), .text("about 400 000 people."),
            .citation(title: "Brno", url: "https://example.com/brno"),
            .usage(AssistantUsage(inputTokens: 900, outputTokens: 20, cachedInputTokens: 800)),
            .finished(.endTurn),
        ])
    }

    @Test func toolCallContinuesWithReasoningItems() throws {
        let (events, decoder) = try AssistantTests.decode("openai-tool", with: OpenAIStreamDecoder())
        #expect(events.first == .toolCall(id: "call_1", name: "edit_document",
                                          input: ["original": "a", "replacement": "b"]))
        #expect(events.last == .finished(.toolUse))
        let continuation = OpenAIResponses.continuation(
            content: decoder.content, results: [AssistantToolResult(callID: "call_1", text: "absent", isError: true)])
        #expect(continuation.map { $0["type"] } == ["reasoning", "function_call", "function_call_output"])
        #expect(continuation[0]["encrypted_content"] == "gAAA")
        #expect(continuation[2]["output"] == "Error: absent")
    }

    @Test func incompleteAnswerStopsAtTheLimit() throws {
        let (events, _) = try AssistantTests.decode("openai-incomplete", with: OpenAIStreamDecoder())
        #expect(events.last == .finished(.maxTokens))
    }

    @Test func failureThrows() {
        var decoder = OpenAIStreamDecoder()
        let data = #"{"type":"response.failed","response":{"error":{"code":"server_error","message":"Boom"}}}"#
        #expect(throws: AssistantError(message: "Boom")) {
            try decoder.decode(ServerSentEvent(event: "response.failed", data: data))
        }
    }
}
