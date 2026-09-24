import XCTest

/// Toolbar and typing behaviour in the real editor: each command is one undo step.
final class FormattingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testToolbarBoldListContinuationAndUndo() throws {
        let fileName = "format-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName]
        app.launch()
        defer { app.terminate() }

        let window = app.windows[fileName]
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        textView.typeText("slovo")
        textView.typeKey("a", modifierFlags: .command)
        window.toolbars.buttons["Bold"].click()
        XCTAssertEqual(textView.value as? String, "**slovo**")

        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(textView.value as? String, "slovo", "Bold must undo in one step")

        textView.typeKey(.rightArrow, modifierFlags: .command)
        textView.typeText("\n- a\n")
        XCTAssertEqual(textView.value as? String, "slovo\n- a\n- ")
        textView.typeText("\n")
        XCTAssertEqual(textView.value as? String, "slovo\n- a\n", "Return on an empty item ends the list")

        XCTAssertEqual(app.menuBars.menuBarItems.matching(identifier: "Format").count, 1, "One Format menu")
        // Heading via the Format menu: ⌘1 depends on the keyboard layout (on a Czech layout
        // the synthesized "1" carries Shift), so it is checked manually.
        app.menuBars.menuBarItems["Format"].click()
        app.menuBars.menuBarItems["Format"].menuItems["Heading 1"].click()
        textView.typeText("Nadpis")
        XCTAssertEqual(textView.value as? String, "slovo\n- a\n# Nadpis")

        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey("b", modifierFlags: .command)
        XCTAssertEqual(textView.value as? String, "**slovo**\n- **a**\n# **Nadpis**",
                       "Bold over lines keeps list and heading markers outside")
    }
}
