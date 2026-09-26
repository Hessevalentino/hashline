import HashlineCore
import SwiftUI

/// Settings ▸ General ▸ Advanced: the hidden switch for the AI assistant and its keys (ADR 0019).
struct AdvancedSettings: View {
    @AppStorage(AssistantSettings.enabledKey) private var assistantEnabled = false
    @State private var isExpanded = AssistantSettings.isEnabled

    var body: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable the AI assistant", isOn: $assistantEnabled)
                    if assistantEnabled {
                        ForEach(AssistantProvider.allCases, id: \.self) { provider in
                            APIKeyRow(provider: provider)
                        }
                        Text("""
                            The document's text and your messages are sent to the provider of the model you \
                            choose in the chat. You pay according to its price list. DeepSeek processes data \
                            in China. Keys are stored only in the Keychain of this Mac.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

/// A provider's key: pasted once, stored in the Keychain and never shown again.
private struct APIKeyRow: View {
    let provider: AssistantProvider
    @State private var keys = AssistantKeys.shared
    @State private var draft = ""
    @State private var status: Status?

    private enum Status {
        case checking, valid, failed(String)
    }

    var body: some View {
        LabeledContent {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if keys.configured.contains(provider) {
                        Text("Key saved").foregroundStyle(.secondary)
                        Button("Verify") { verify() }
                        Button("Remove") {
                            keys.remove(provider)
                            status = nil
                        }
                    } else {
                        SecureField("API key", text: $draft, prompt: Text("Paste key"))
                            .labelsHidden()
                            .frame(maxWidth: 220)
                            .onSubmit(save)
                        Button("Save") { save() }
                            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                HStack(spacing: 10) {
                    statusView
                    Link("Get a key", destination: provider.keysURL)
                    Link("Prices", destination: provider.pricingURL)
                }
                .font(.caption)
            }
        } label: {
            Text(verbatim: "\(provider.displayName):")
        }
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .checking: ProgressView().controlSize(.mini)
        case .valid: Label("Key works", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .failed(let message):
            Label { Text(verbatim: message).lineLimit(2) } icon: { Image(systemName: "xmark.circle") }
                .foregroundStyle(.red)
        case nil: EmptyView()
        }
    }

    private func save() {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard keys.save(key, for: provider) else {
            status = .failed(String(localized: "The key could not be saved in the Keychain."))
            return
        }
        draft = ""
        verify()
    }

    private func verify() {
        guard let key = keys.key(for: provider) else { return }
        status = .checking
        Task {
            switch await AssistantClient.verify(key, provider: provider) {
            case .success: status = .valid
            case .failure(let error): status = .failed(error.message)
            }
        }
    }
}
