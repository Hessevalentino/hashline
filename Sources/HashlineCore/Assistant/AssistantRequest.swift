/// One finished exchange of the conversation, kept provider-neutral so the user can switch models
/// between questions.
public struct AssistantTurn: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant }
    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// A tool the app runs itself (the document edits, ADR 0019).
public struct AssistantTool: Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// What the app answers to one tool call.
public struct AssistantToolResult: Sendable, Equatable {
    public var callID: String
    public var text: String
    public var isError: Bool

    public init(callID: String, text: String, isError: Bool = false) {
        self.callID = callID
        self.text = text
        self.isError = isError
    }
}

/// Everything one request sends.
public struct AssistantRequest: Sendable {
    public var model: AssistantModel
    public var instructions: String
    /// The document's text, sent as data (never as instructions) before the conversation.
    public var document: String
    /// Finished turns; the last one is the user's new message.
    public var turns: [AssistantTurn]
    public var tools: [AssistantTool]
    public var webSearch: Bool
    /// Provider-native messages of the running turn (tool calls and their results), appended
    /// after `turns`.
    public var continuation: [JSONValue]

    public init(model: AssistantModel, instructions: String, document: String, turns: [AssistantTurn],
                tools: [AssistantTool] = [], webSearch: Bool = false, continuation: [JSONValue] = []) {
        self.model = model
        self.instructions = instructions
        self.document = document
        self.turns = turns
        self.tools = tools
        self.webSearch = webSearch
        self.continuation = continuation
    }
}

public enum AssistantStopReason: Sendable, Equatable {
    case endTurn
    case maxTokens
    case toolUse
    /// The server paused a long server-tool turn; sending the response back continues it.
    case pauseTurn
    case refusal
    case other(String)

    init(anthropic value: String) {
        switch value {
        case "end_turn", "stop_sequence": self = .endTurn
        case "max_tokens", "model_context_window_exceeded": self = .maxTokens
        case "tool_use": self = .toolUse
        case "pause_turn": self = .pauseTurn
        case "refusal": self = .refusal
        default: self = .other(value)
        }
    }
}

public struct AssistantUsage: Sendable, Equatable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cachedInputTokens = 0

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cachedInputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
    }
}

/// What a streamed response reports, in order.
public enum AssistantEvent: Sendable, Equatable {
    case text(String)
    /// A source the answer cites (shown as a clickable link).
    case citation(title: String, url: String)
    /// The model searches the web.
    case searching(query: String)
    /// A complete call of one of the request's tools.
    case toolCall(id: String, name: String, input: JSONValue)
    /// A tool call whose input is not valid JSON (cut off or malformed); it must not run.
    case invalidToolCall(id: String, name: String, input: String)
    case usage(AssistantUsage)
    case finished(AssistantStopReason)
    /// The response's provider-native content, last in the stream; sent back to continue the
    /// turn after tool calls.
    case assistantContent([JSONValue])
}

public struct AssistantError: Error, Sendable, Equatable {
    public var status: Int?
    public var message: String

    public init(status: Int? = nil, message: String) {
        self.status = status
        self.message = message
    }

    /// The provider's error body (`{"error": {"message": …}}` in both protocols), or the raw text.
    public init(status: Int?, body: String) {
        let message = (try? JSONValue.parse(body))?["error"]?["message"]?.string
        self.init(status: status, message: message ?? String(body.prefix(300)))
    }
}
