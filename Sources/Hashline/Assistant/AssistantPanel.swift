import AppKit
import HashlineCore
import SwiftUI

/// The chat beside the document (ADR 0019): the last split column, one conversation per document.
/// Answers are native text (no web view), links open in the browser only when clicked.
struct AssistantPanel: View {
    @Bindable var session: AssistantSession
    @State private var keys = AssistantKeys.shared

    var body: some View {
        let models = keys.models
        VStack(spacing: 0) {
            header(models: models)
            Divider()
            if models.isEmpty {
                NoKeyView()
            } else {
                MessageList(session: session)
                Divider()
                Composer(session: session, models: models)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .environment(\.openURL, OpenURLAction { url in
            ["http", "https"].contains(url.scheme?.lowercased()) ? .systemAction : .discarded
        })
    }

    private func header(models: [AssistantModel]) -> some View {
        HStack(spacing: 6) {
            Text("Assistant").font(.headline)
            Spacer()
            if !models.isEmpty {
                Picker("Model", selection: Binding(
                    get: { session.resolvedModel(from: models) },
                    set: { session.model = $0 })) {
                    ForEach(AssistantProvider.allCases, id: \.self) { provider in
                        let providerModels = models.filter { $0.provider == provider }
                        if !providerModels.isEmpty {
                            Section(provider.displayName) {
                                ForEach(providerModels) { model in
                                    Text(verbatim: model.name).tag(Optional(model))
                                }
                            }
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("The model that answers your next message")
            }
            Button { session.clear() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless)
                .help("New conversation")
                .accessibilityLabel("New conversation")
                .disabled(session.messages.isEmpty || session.isRunning)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }
}

private struct NoKeyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "key").font(.title2).foregroundStyle(.secondary)
            Text("Add an API key for Claude, OpenAI or DeepSeek in Settings ▸ General ▸ Advanced.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            SettingsLink { Text("Open Settings…") }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}

private struct MessageList: View {
    let session: AssistantSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if session.messages.isEmpty {
                        Text("""
                            Ask about this document, have it reviewed or research its topic. The assistant \
                            sees only this document.
                            """)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.messages) { message in
                        MessageView(message: message) { session.document.revealChanges() }.id(message.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(12)
            }
            .onChange(of: session.messages.last?.text) { _, _ in proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: session.messages.count) { _, _ in proxy.scrollTo(Self.bottom, anchor: .bottom) }
        }
    }

    private static let bottom = "bottom"
}

private struct MessageView: View {
    let message: AssistantMessage
    let revealChanges: () -> Void

    var body: some View {
        switch message.role {
        case .user:
            Text(verbatim: message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .error:
            Label { Text(verbatim: message.text) } icon: { Image(systemName: "exclamationmark.triangle") }
                .font(.callout)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(message.searches, id: \.self) { query in
                    Label { Text("Searched: \(query)") } icon: { Image(systemName: "magnifyingglass") }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if message.text.isEmpty, message.isStreaming {
                    ProgressView().controlSize(.small)
                } else {
                    Text(Self.markdown(message.text))
                        .textSelection(.enabled)
                }
                ForEach(message.citations, id: \.self) { citation in
                    Link(destination: citation.url) {
                        Label { Text(verbatim: citation.title).lineLimit(1) } icon: {
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                    .font(.caption)
                    .help(citation.url.absoluteString)
                }
                if message.edits > 0 {
                    HStack(spacing: 6) {
                        Label { Text("Places changed: \(message.edits)") } icon: { Image(systemName: "pencil.line") }
                        Button("Show", action: revealChanges)
                            .buttonStyle(.link)
                            .help("Select the first change in the document; ⌘Z undoes the whole instruction")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("assistantEdits")
                }
                if let usage = message.usage, !message.isStreaming {
                    Text("\(usage.inputTokens) tokens in, \(usage.outputTokens) out")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("Cached input tokens: \(usage.cachedInputTokens)")
                }
            }
        }
    }

    /// Inline Markdown (emphasis, code, links) with the line breaks kept; block syntax stays as text.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct Composer: View {
    @Bindable var session: AssistantSession
    let models: [AssistantModel]
    @FocusState private var isFocused: Bool
    /// Visible lines of the message field; the handle above it changes them.
    @AppStorage(AssistantSettings.inputLinesKey) private var lines = AssistantSettings.defaultInputLines
    @State private var dragStartLines: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResizeHandle(lines: $lines, dragStartLines: $dragStartLines)
            VStack(alignment: .leading, spacing: 6) {
                if let estimate = session.largeDocumentEstimate {
                    LargeDocumentNotice(session: session, models: models, estimate: estimate)
                }
                if session.isRunning {
                    Label("The document is read-only until the assistant finishes.", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                field
            }
            .padding([.horizontal, .bottom], 10)
        }
        .onAppear { isFocused = true }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // Return sends, ⌥Return starts a new line; longer text scrolls inside the field.
            TextField("Ask about this document…", text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(lines, reservesSpace: true)
                .focused($isFocused)
                .accessibilityIdentifier("assistantField")
                .onSubmit { session.send(using: models) }
                .disabled(session.isRunning)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            VStack(spacing: 8) {
                if session.resolvedModel(from: models)?.webSearch != nil {
                    Toggle(isOn: $session.searchesWeb) { Image(systemName: "globe") }
                        .toggleStyle(.button)
                        .help("Research on the web (each search costs extra)")
                        .accessibilityLabel("Research on the web")
                }
                if session.isRunning {
                    Button { session.stop() } label: { Image(systemName: "stop.circle.fill") }
                        .help("Stop")
                        .accessibilityLabel("Stop")
                        .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button { session.send(using: models) } label: { Image(systemName: "arrow.up.circle.fill") }
                        .help("Send (Return)")
                        .accessibilityLabel("Send")
                        .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.bottom, 4)
        }
        .buttonStyle(.borderless)
        .font(.body)
        .imageScale(.large)
    }
}

/// The top edge of the composer: dragging it up gives the message field more lines, down fewer.
private struct ResizeHandle: View {
    @Binding var lines: Int
    @Binding var dragStartLines: Int?
    /// Height of one line of the body font.
    private static let lineHeight = NSLayoutManager().defaultLineHeight(for: .preferredFont(forTextStyle: .body))

    var body: some View {
        Capsule()
            .fill(Color(nsColor: .tertiaryLabelColor))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 12)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStartLines ?? lines
                    dragStartLines = start
                    let change = Int((-drag.translation.height / Self.lineHeight).rounded())
                    lines = min(max(start + change, AssistantSettings.inputLines.lowerBound),
                                AssistantSettings.inputLines.upperBound)
                }
                .onEnded { _ in dragStartLines = nil })
            .help("Drag to resize the message field")
            .accessibilityElement()
            .accessibilityLabel("Message field height")
            .accessibilityValue(Text("\(lines) lines"))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1 : direction == .decrement ? -1 : 0
                lines = min(max(lines + step, AssistantSettings.inputLines.lowerBound),
                            AssistantSettings.inputLines.upperBound)
            }
    }
}

/// Every message sends the whole document; above about 100 000 tokens the user confirms once.
private struct LargeDocumentNotice: View {
    let session: AssistantSession
    let models: [AssistantModel]
    let estimate: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("""
                This document has about \(estimate) tokens, and every message sends it whole. \
                Check the provider's price list before you continue.
                """)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Send Anyway") { session.send(using: models, scope: .document) }
                if session.document.selection != nil {
                    Button("Send Selection Only") { session.send(using: models, scope: .selection) }
                }
                Button("Cancel", role: .cancel) { session.cancelLargeSend() }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}
