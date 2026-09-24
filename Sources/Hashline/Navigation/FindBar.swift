import HashlineCore
import SwiftUI

/// The find and replace bar above the editor.
struct FindBar: View {
    @Bindable var find: FindController
    @FocusState private var focusedField: Field?

    private enum Field { case find, replace }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button { find.showsReplace.toggle() } label: {
                    Image(systemName: find.showsReplace ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.borderless)
                .help("Show Replace")
                TextField("Find", text: $find.query.text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .find)
                    .onSubmit { find.findNext(backwards: NSEvent.modifierFlags.contains(.shift)) }
                    .accessibilityIdentifier("findField")
                    .accessibilityLabel("Find")
                Text(find.summary)
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(find.errorMessage == nil ? Color.secondary : Color.red)
                    .frame(minWidth: 70, alignment: .trailing)
                    .accessibilityIdentifier("findSummary")
                option("Aa", isOn: $find.query.caseSensitive, help: "Match Case", id: "findCase")
                option("W", isOn: $find.query.wholeWords, help: "Whole Words", id: "findWords")
                option(".*", isOn: $find.query.isRegex, help: "Regular Expression", id: "findRegex")
                ControlGroup {
                    Button { find.findNext(backwards: true) } label: { Image(systemName: "chevron.left") }
                        .help("Previous (⇧⌘G)")
                    Button { find.findNext(backwards: false) } label: { Image(systemName: "chevron.right") }
                        .help("Next (⌘G)")
                }
                .frame(width: 60)
                Button("Done") { find.close() }
            }
            if find.showsReplace {
                HStack(spacing: 6) {
                    Color.clear.frame(width: 16, height: 1)
                    TextField(find.query.isRegex ? "Replace ($1 = group 1)" : "Replace", text: $find.replacement)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .replace)
                        .onSubmit { find.replaceCurrent(findNext: true) }
                        .accessibilityIdentifier("replaceField")
                    .accessibilityLabel("Replace with")
                    Button("Replace") { find.replaceCurrent(findNext: true) }
                    Button("All") { find.replaceAll() }
                        .help("Replace All")
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .onExitCommand { find.close() }
        .onAppear { focusedField = .find }
        .onChange(of: find.focusRequest) { focusedField = .find }
    }

    private func option(_ title: String, isOn: Binding<Bool>, help: LocalizedStringKey, id: String) -> some View {
        Toggle(isOn: isOn) { Text(verbatim: title) }
            .toggleStyle(.button)
            .font(.system(.caption, design: .monospaced))
            .help(help)
            .accessibilityIdentifier(id)
    }
}
