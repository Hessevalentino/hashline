import XCTest

/// View modes: the status bar counts, reading mode hides the editor without losing its text or caret.
final class ViewModesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testStatusBarAndReadingMode() throws {
        let fileName = "modes-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName]
        app.launch()
        defer { app.terminate() }

        let window = app.windows[fileName]
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.typeText("Jedna dva tři")

        let view = app.menuBars.menuBarItems["View"]
        view.click()
        view.menuItems["Show Status Bar"].click()
        XCTAssertTrue(window.staticTexts["3 words"].waitForExistence(timeout: 3))

        view.click()
        view.menuItems["Reading Mode"].click()
        XCTAssertFalse(textView.isHittable, "Reading mode shows only the preview")
        view.click()
        view.menuItems["Reading Mode"].click()
        XCTAssertTrue(textView.waitForExistence(timeout: 3))
        textView.typeText(" čtyři")
        XCTAssertEqual(textView.value as? String, "Jedna dva tři čtyři", "Caret and text survive reading mode")

        view.click()
        view.menuItems["Show Status Bar"].click()
    }
}
