import XCTest

/// Critical flow: open → type → undo/redo → save → relaunch → text is back from disk.
/// Uses `-HashlineUITestDocument` (DEBUG only) because the sandbox save panel runs out of process.
final class EditingFlowUITests: XCTestCase {
    private let content = "# Hello Hashline\nPříliš žluťoučký kůň"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTypeUndoSaveAndReopen() throws {
        let fileName = "uitest-\(UUID().uuidString.prefix(8)).md"

        let app = launch(opening: fileName)
        let textView = app.windows[fileName].textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        XCTAssertEqual(textView.value as? String, "")

        textView.click()
        textView.typeText(content)
        XCTAssertEqual(textView.value as? String, content)

        app.typeKey("z", modifierFlags: .command)
        XCTAssertNotEqual(textView.value as? String, content, "Undo did nothing")
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(textView.value as? String, content)

        app.typeKey("s", modifierFlags: .command)
        // Saving runs on a background queue; give it time, then make sure the app survived.
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.state, .runningForeground, "App terminated while saving")
        app.terminate()

        let relaunched = launch(opening: fileName)
        let reopened = relaunched.windows[fileName].textViews.firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.value as? String, content)
        relaunched.terminate()
    }

    @MainActor
    private func launch(opening fileName: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName]
        app.launch()
        return app
    }
}
