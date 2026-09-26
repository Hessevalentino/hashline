/// One server-sent event (https://html.spec.whatwg.org/multipage/server-sent-events.html).
public struct ServerSentEvent: Sendable, Equatable {
    public var event: String?
    public var data: String

    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }
}

/// Turns the lines of an event stream into events; fed line by line (`URLSession.bytes(for:).lines`).
public struct ServerSentEventParser: Sendable {
    private var event: String?
    private var data: [String] = []

    public init() {}

    /// The event completed by `line`, if any. `lines` of `URLSession` drops empty lines, so a new
    /// `event:` field also completes the previous event.
    public mutating func feed(_ line: String) -> ServerSentEvent? {
        if line.isEmpty { return flush() }
        if line.hasPrefix(":") { return nil }
        let (field, value) = Self.split(line)
        switch field {
        case "event":
            let completed = data.isEmpty ? nil : flush()
            event = value
            return completed
        case "data":
            data.append(value)
            // Providers send one JSON object per data line; a complete object ends the event
            // without waiting for the blank line (which `lines` never delivers).
            return value.hasPrefix("{") && value.hasSuffix("}") || value == "[DONE]" ? flush() : nil
        default:
            return nil
        }
    }

    /// The pending event at the end of the stream.
    public mutating func finish() -> ServerSentEvent? { flush() }

    private mutating func flush() -> ServerSentEvent? {
        defer {
            event = nil
            data = []
        }
        guard !data.isEmpty else { return nil }
        return ServerSentEvent(event: event, data: data.joined(separator: "\n"))
    }

    private static func split(_ line: String) -> (Substring, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line[...], "") }
        var value = line[line.index(after: colon)...]
        if value.first == " " { value = value.dropFirst() }
        return (line[..<colon], String(value))
    }
}
