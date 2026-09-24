import XCTest

/// Clicking a task checkbox in the preview toggles `[ ]` ↔ `[x]` in the source, as one undo step.
final class PreviewTaskUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCheckboxInPreviewTogglesSource() throws {
        let fileName = "tasks-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName,
                               "-showsPreview", "YES", "-showsLibrary", "NO"]
        app.launch()
        defer { app.terminate() }
        let window = app.windows[fileName]
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        // Typing "[" pairs to "[]", space goes inside, "]" steps over the closer.
        textView.typeText("- [ ] úkol")
        XCTAssertEqual(textView.value as? String, "- [ ] úkol")

        let checkbox = window.webViews.firstMatch.checkBoxes.firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5), "Preview did not render the task")
        checkbox.click()
        let toggled = NSPredicate { _, _ in (textView.value as? String) == "- [x] úkol" }
        wait(for: [expectation(for: toggled, evaluatedWith: nil)], timeout: 5)

        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(textView.value as? String, "- [ ] úkol")
    }
}
