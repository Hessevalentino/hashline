import Foundation
import HashlineCore
import Observation

/// A message of the chat as the panel shows it.
struct AssistantMessage: Identifiable {
    enum Role { case user, assistant, error }

    struct Citation: Hashable {
        let title: String
        let url: URL
    }

    let id = UUID()
    let role: Role
    var text: String
    var citations: [Citation] = []
    var searches: [String] = []
    var usage: AssistantUsage?
    /// Places in the document changed by this answer (one undo step).
    var edits = 0
    var isStreaming = false
}

/// One document's conversation (ADR 0019): created when its panel first opens, kept in memory while
/// the document is open, never written to disk. The assistant sees and changes only this document;
/// while it works the document is read-only, and each instruction is one undo step.
@MainActor
@Observable
final class AssistantSession {
    private(set) var messages: [AssistantMessage] = []
    private(set) var isRunning = false
    var draft = ""
    /// Research on the web for the next messages (costs extra; off by default).
    var searchesWeb = false
    /// Set when a message waits for the user to confirm sending a large document.
    private(set) var largeDocumentEstimate: Int?
    @ObservationIgnored private var isLargeDocumentConfirmed = false
    var model: AssistantModel? {
        didSet {
            if let model { UserDefaults.standard.set(model.key, forKey: AssistantSettings.modelKey) }
        }
    }

    @ObservationIgnored let document: AssistantDocumentBridge
    /// Finished exchanges sent with the next question.
    @ObservationIgnored private var turns: [AssistantTurn] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Streamed text not yet shown; the panel redraws at most 30 times a second.
    @ObservationIgnored private var pendingText = ""
    @ObservationIgnored private var isFlushScheduled = false
    /// Starts a new paragraph before the text that follows a round of tool calls.
    @ObservationIgnored private var needsParagraphBreak = false
    private static let flushInterval: TimeInterval = 1.0 / 30
    /// Requests of one instruction at most (each tool round is one request).
    private static let maxRounds = 25

    /// A call of a document tool; `input` is nil when it did not arrive as valid JSON.
    private struct ToolCall {
        let id: String
        let name: String
        let input: JSONValue?
    }

    /// What one streamed response left for the next round.
    private struct Response {
        var calls: [ToolCall] = []
        var content: [JSONValue] = []
        var stop: AssistantStopReason?
        var usage: AssistantUsage?
    }

    init(document: AssistantDocumentBridge) {
        self.document = document
        let saved = UserDefaults.standard.string(forKey: AssistantSettings.modelKey)
        model = saved.flatMap(AssistantModel.model(forKey:))
    }

    /// The chosen model when its provider still has a key, otherwise the first available one.
    func resolvedModel(from available: [AssistantModel]) -> AssistantModel? {
        if let model, available.contains(model) { return model }
        return available.first
    }

    /// How the next message sends the document.
    enum Scope {
        case document
        /// Only the selection (a large document the user chose not to send whole).
        case selection
    }

    func send(using available: [AssistantModel], scope: Scope? = nil) {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isRunning, let model = resolvedModel(from: available) else { return }
        guard let apiKey = AssistantKeys.shared.key(for: model.provider) else {
            showError(String(localized: "The API key is missing in Settings."))
            return
        }
        let text = document.text
        let selection = document.selection
        // Each message sends the whole document: ask once per conversation before a large one goes out.
        // A local model costs nothing and the text stays on the user's server.
        let estimate = AssistantCost.estimatedTokens(text)
        if scope == nil, !model.provider.isLocal, estimate > AssistantCost.confirmationThreshold,
           !isLargeDocumentConfirmed {
            largeDocumentEstimate = estimate
            return
        }
        largeDocumentEstimate = nil
        let scope = scope ?? .document
        // A local send confirms nothing: switching to a cloud model later must still ask.
        if scope == .document, !model.provider.isLocal { isLargeDocumentConfirmed = true }
        let sendsSelection = scope == .selection && selection != nil

        draft = ""
        messages.append(AssistantMessage(role: .user, text: question))
        let userText = Self.userText(question, selection: sendsSelection ? nil : selection,
                                     selectionOnly: sendsSelection)
        turns.append(AssistantTurn(role: .user, text: userText))
        // The text as the model sees it for the whole instruction; its edits follow in the tool history.
        // With only the selection sent, a whole-document rewrite would drop the rest: that tool is left out.
        let request = AssistantRequest(
            model: model, instructions: AssistantInstructions.text,
            document: sendsSelection ? selection ?? "" : text, turns: turns,
            tools: sendsSelection ? DocumentEditTools.all.filter { $0.name == DocumentEditTools.editName }
                : DocumentEditTools.all,
            webSearch: searchesWeb && model.webSearch != nil,
            server: AssistantKeys.shared.servers[model.provider])
        messages.append(AssistantMessage(role: .assistant, text: "", isStreaming: true))
        isRunning = true
        document.lock()
        task = Task { [weak self] in
            await self?.run(request, apiKey: apiKey)
        }
    }

    func cancelLargeSend() {
        largeDocumentEstimate = nil
    }

    func stop() {
        task?.cancel()
    }

    /// Starts over; the document is untouched.
    func clear() {
        guard !isRunning else { return }
        messages = []
        turns = []
        largeDocumentEstimate = nil
        isLargeDocumentConfirmed = false
        document.clearHighlights()
    }

    private func run(_ request: AssistantRequest, apiKey: String) async {
        var request = request
        var failure: String?
        do {
            for _ in 0..<Self.maxRounds {
                var response = Response()
                for try await event in AssistantClient.stream(request, apiKey: apiKey) {
                    handle(event, into: &response)
                }
                if let usage = response.usage { addUsage(usage) }
                // Stopped by the user: the calls of a cut-off response never run.
                try Task.checkCancellation()
                guard response.stop == .toolUse || response.stop == .pauseTurn else { break }
                let results = response.stop == .toolUse ? response.calls.map(perform) : []
                request.continuation += request.model.provider.wireProtocol.continuation(
                    content: response.content, results: results)
                needsParagraphBreak = true
            }
        } catch is CancellationError {
        } catch let error as AssistantError {
            failure = error.message
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            failure = error.localizedDescription
        }
        finishTurn(failure: failure)
    }

    /// Runs one of the document tools; the result tells the model what happened.
    private func perform(_ call: ToolCall) -> AssistantToolResult {
        guard let input = call.input else {
            return AssistantToolResult(callID: call.id, text: DocumentEditTools.Failure.invalidInput.message,
                                       isError: true)
        }
        switch document.apply(tool: call.name, input: input) {
        case .success:
            updateLast { $0.edits += 1 }
            return AssistantToolResult(callID: call.id, text: "Done. The document now contains the change.")
        case .failure(let refusal):
            return AssistantToolResult(callID: call.id, text: refusal.message, isError: true)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handle(_ event: AssistantEvent, into response: inout Response) {
        switch event {
        case .text(let text):
            if needsParagraphBreak {
                needsParagraphBreak = false
                let shown = (messages.last(where: { $0.role == .assistant })?.text ?? "") + pendingText
                if !shown.isEmpty { pendingText += "\n\n" }
            }
            pendingText += text
            scheduleFlush()
        case .citation(let title, let url):
            guard let url = URL(string: url), ["http", "https"].contains(url.scheme?.lowercased()) else { return }
            updateLast { message in
                let citation = AssistantMessage.Citation(title: title, url: url)
                if !message.citations.contains(citation) { message.citations.append(citation) }
            }
        case .searching(let query):
            updateLast { $0.searches.append(query) }
        case .usage(let usage):
            response.usage = usage
        case .toolCall(let id, let name, let input):
            response.calls.append(ToolCall(id: id, name: name, input: input))
        case .invalidToolCall(let id, let name, _):
            response.calls.append(ToolCall(id: id, name: name, input: nil))
        case .assistantContent(let content):
            response.content = content
        case .finished(let stop):
            response.stop = stop
            if stop == .refusal || stop == .maxTokens { flush() }
            if stop == .refusal { showError(String(localized: "The model declined this request.")) }
            if stop == .maxTokens { showError(String(localized: "The answer reached the length limit.")) }
        }
    }

    private func finishTurn(failure: String?) {
        flush()
        task = nil
        isRunning = false
        let edits = document.unlock()
        updateLast { $0.isStreaming = false }
        let answer = messages.last(where: { $0.role == .assistant })?.text ?? ""
        if answer.isEmpty && edits == 0 {
            // Nothing came back: drop both halves so the next question does not follow an unanswered one.
            if messages.last?.role == .assistant, messages.last?.text.isEmpty == true { messages.removeLast() }
            if turns.last?.role == .user { turns.removeLast() }
        } else {
            // Later questions see the edited document itself; the history keeps only the words.
            turns.append(AssistantTurn(role: .assistant, text: answer.isEmpty ? "(I edited the document.)" : answer))
        }
        if let failure { showError(failure) }
    }

    /// Tokens of all requests of one instruction.
    private func addUsage(_ usage: AssistantUsage) {
        updateLast { message in
            var total = message.usage ?? AssistantUsage()
            total.inputTokens += usage.inputTokens
            total.outputTokens += usage.outputTokens
            total.cachedInputTokens += usage.cachedInputTokens
            message.usage = total
        }
    }

    private func showError(_ text: String) {
        messages.append(AssistantMessage(role: .error, text: text))
    }

    private func scheduleFlush() {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flushInterval) { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    private func flush() {
        isFlushScheduled = false
        guard !pendingText.isEmpty else { return }
        let text = pendingText
        pendingText = ""
        updateLast { $0.text += text }
    }

    /// Changes the answer being streamed.
    private func updateLast(_ change: (inout AssistantMessage) -> Void) {
        guard let index = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        change(&messages[index])
    }

    private static func userText(_ question: String, selection: String?, selectionOnly: Bool) -> String {
        if selectionOnly {
            return "(Only the selected part of a longer document was sent; it is the <document> above.)\n\n\(question)"
        }
        guard let selection, !selection.isEmpty else { return question }
        return "<selection>\n\(selection)\n</selection>\n\n\(question)"
    }
}
