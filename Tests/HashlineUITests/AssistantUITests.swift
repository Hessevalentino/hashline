import XCTest

/// The assistant's critical flow with the scripted provider (`-HashlineAssistantFake`, no network):
/// a message edits the document, the change is reported, and one ⌘Z undoes the whole instruction.
final class AssistantUITests: XCTestCase {
    @MainActor
    func testInstructionEditsDocumentAndUndoesInOneStep() throws {
        let name = "assistant-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-assistantEnabled", "YES", "-showsAssistant", "YES",
                               "-HashlineAssistantFake", "YES", "-HashlineUITestDocument", name]
        app.launch()
        defer { app.terminate() }
        let window = app.windows[name]
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        let untitled = app.windows["Untitled"]
        if untitled.exists { untitled.buttons["_XCUI:CloseWindow"].click() }
        textView.click()
        textView.typeText("Hello world, again.")

        let field = window.descendants(matching: .any)["assistantField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeText("Replace the word\r")

        let edited = NSPredicate(format: "value == %@", "Hello Hashline, again.")
        expectation(for: edited, evaluatedWith: textView)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(window.descendants(matching: .any)["assistantEdits"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["Replaced one word."].waitForExistence(timeout: 5))

        textView.click()
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(textView.value as? String, "Hello world, again.")
        // The typing before it is a separate step.
        app.typeKey("z", modifierFlags: .command)
        XCTAssertNotEqual(textView.value as? String, "Hello world, again.")
    }
}
