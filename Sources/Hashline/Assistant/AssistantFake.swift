#if DEBUG || HASHLINE_TEST_HOOKS
import AppKit
import HashlineCore

/// `-HashlineAssistantFake YES`: a scripted provider without network or key, for UI tests.
/// `-HashlineAssistantSelfTest YES` (with the fake) runs the critical flow inside the app without
/// taking focus, logs `Assistant self-test: …` and quits.
/// First round: replaces “world” with “Hashline” (or reports that it is missing); second round: a summary.
enum AssistantFake {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "HashlineAssistantFake") }

    static func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        let events: [AssistantEvent]
        if request.continuation.isEmpty {
            let tool = request.tools.first { $0.name == DocumentEditTools.editName }
            events = tool == nil ? [.text("No tools."), .finished(.endTurn)] : [
                .text("Replacing the word."),
                .toolCall(id: "fake_1", name: DocumentEditTools.editName,
                          input: ["original": "world", "replacement": "Hashline"]),
                .usage(AssistantUsage(inputTokens: 100, outputTokens: 10)),
                .finished(.toolUse),
                .assistantContent([["type": "text", "text": "Replacing the word."]]),
            ]
        } else {
            events = [.text("Replaced one word."), .usage(AssistantUsage(inputTokens: 120, outputTokens: 5)),
                      .finished(.endTurn), .assistantContent([])]
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                for event in events {
                    try? await Task.sleep(for: .milliseconds(150))
                    if Task.isCancelled { break }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension AssistantFake {
    @MainActor
    static func runSelfTest() async {
        var failures: [String] = []
        defer {
            let result = failures.isEmpty ? "passed" : "FAILED: " + failures.joined(separator: "; ")
            Performance.logger.notice("Assistant self-test: \(result, privacy: .public)")
            NSApp.terminate(nil)
        }
        guard let window = NSApp.orderedWindows.first(where: { $0.firstResponder is EditorTextView }),
              let session = DocumentReveal.session(for: window), let textView = session.textView,
              let undoManager = textView.undoManager else {
            failures.append("no editor window")
            return
        }
        let original = "Hello world, again."
        textView.insertText(original, replacementRange: NSRange(location: 0, length: 0))
        textView.breakUndoCoalescing()
        let assistant = session.assistant

        // An instruction edits the document while it is read-only, then it is one undo step.
        assistant.draft = "Replace the word"
        assistant.send(using: AssistantKeys.shared.models)
        if textView.isEditable { failures.append("editable while working") }
        await waitUntilIdle(assistant)
        if textView.string != "Hello Hashline, again." { failures.append("text after edit: \(textView.string)") }
        if assistant.messages.last(where: { $0.role == .assistant })?.edits != 1 { failures.append("edit count") }
        if !textView.isEditable { failures.append("still read-only") }
        undoManager.undo()
        if textView.string != original { failures.append("text after one undo: \(textView.string)") }

        // Stop before the tool call arrives: nothing changes and the document is editable again.
        assistant.draft = "Replace the word"
        assistant.send(using: AssistantKeys.shared.models)
        try? await Task.sleep(for: .milliseconds(200))
        assistant.stop()
        await waitUntilIdle(assistant)
        if textView.string != original { failures.append("text after stop: \(textView.string)") }
        if !textView.isEditable { failures.append("read-only after stop") }
    }

    @MainActor
    private static func waitUntilIdle(_ assistant: AssistantSession) async {
        for _ in 0..<100 where assistant.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
#endif
