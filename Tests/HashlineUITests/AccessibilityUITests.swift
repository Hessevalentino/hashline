import XCTest

/// The automated accessibility audit (the checks of Accessibility Inspector) on a document window
/// with the sidebar, the find bar, the preview and the status bar, and on Settings.
final class AccessibilityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testDocumentWindowPassesAudit() throws {
        let library = "a11y-\(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineLibraryFolder", library,
                               "-showsLibrary", "YES", "-showsStatusBar", "YES", "-sidebarTab", "outline",
                               "-HashlineUITestDocument", "\(library)/audit.md"]
        app.launch()
        defer { app.terminate() }
        let window = app.windows["audit.md"]
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.typeText("# Nadpis\n\nOdstavec s **tučným** textem.\n\n## Druhý\n")
        // SwiftUI opens an untitled window at launch next to the hook's document; audit only ours.
        let untitled = app.windows["Untitled"]
        if untitled.exists { untitled.buttons["_XCUI:CloseWindow"].click() }
        window.click()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(window.textFields["findField"].waitForExistence(timeout: 3))

        let titles = Set(app.windows.allElementsBoundByIndex.map(\.title))
        try app.performAccessibilityAudit { issue in
            Self.isSystemElement(issue, windowTitles: titles)
        }
    }

    @MainActor
    func testSettingsPassAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", "audit-settings.md"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["audit-settings.md"].textViews.firstMatch.waitForExistence(timeout: 5))
        let untitled = app.windows["Untitled"]
        if untitled.exists { untitled.buttons["_XCUI:CloseWindow"].click() }
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        for tab in ["General", "Editor", "Appearance", "Images", "Export"] {
            settings.toolbars.buttons[tab].click()
            sleep(2)  // the tab switch cross-fades and resizes; mid-animation colours fail the contrast check
            let titles = Set(app.windows.allElementsBoundByIndex.map(\.title))
            try app.performAccessibilityAudit { issue in
                Self.isSystemElement(issue, windowTitles: titles)
            }
        }
    }

    /// Elements AppKit and SwiftUI own and Hashline cannot change: the Touch Bar (its emoji picker),
    /// SwiftUI menu pickers without AXPress, dimmed disabled labels,
    /// the window title, the title-bar internals (parent/child mismatches in every SwiftUI app) and
    /// the unlabelled container groups of `HSplitView` (labels set on the panes do not reach them).
    static func isSystemElement(_ issue: XCUIAccessibilityAuditIssue, windowTitles: Set<String>) -> Bool {
        guard let element = issue.element else { return issue.auditType == .parentChild }
        let description = element.debugDescription
        if description.contains("TouchBar") || element.label == "emoji & symbols" { return true }
        if issue.auditType == .contrast, let value = element.value as? String, windowTitles.contains(value) {
            return true
        }
        if issue.auditType == .sufficientElementDescription, element.elementType == .group, !element.isEnabled {
            return true
        }
        // Dimmed labels of disabled controls are exempt from contrast requirements (WCAG 1.4.3).
        if issue.auditType == .contrast, !element.isEnabled { return true }
        // SwiftUI menu pickers do not expose AXPress (the Touch Bar's own emoji picker neither);
        // they open with a click, keyboard and VoiceOver (VO-Space) all the same.
        if issue.auditType == .action, element.elementType == .popUpButton { return true }
        return issue.auditType == .parentChild && element.elementType == .group && element.frame.width <= 20
    }
}
