import XCTest

/// Settings ▸ Appearance: choosing a dark theme restyles the open editor without a restart.
final class AppearanceUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testThemePickersListBuiltInThemes() throws {
        let fileName = "theme-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows[fileName].textViews.firstMatch.waitForExistence(timeout: 5))

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.toolbars.buttons["Appearance"].click()
        let dark = settings.popUpButtons["darkThemePicker"]
        XCTAssertTrue(dark.waitForExistence(timeout: 3))
        dark.click()
        XCTAssertTrue(dark.menuItems["Solarized Dark"].exists)
        XCTAssertTrue(dark.menuItems["Tomorrow Night"].exists)
        dark.typeKey(.escape, modifierFlags: [])
        let light = settings.popUpButtons["lightThemePicker"]
        light.click()
        XCTAssertTrue(light.menuItems["Paper"].exists)
        XCTAssertTrue(light.menuItems["Solarized Light"].exists)
        light.typeKey(.escape, modifierFlags: [])
    }

    /// The ☀︎/☾ switch in the toolbar pins light or dark; View ▸ Appearance ▸ Match System undoes it.
    @MainActor
    func testToolbarSwitchesLightAndDark() throws {
        let fileName = "mode-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName]
        app.launch()
        defer { app.terminate() }
        let window = app.windows[fileName]
        XCTAssertTrue(window.textViews.firstMatch.waitForExistence(timeout: 5))
        let toggle = window.toolbars.switches["Dark mode"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Appearance switch in the toolbar")
        let before = toggle.value as? Int ?? -1
        toggle.click()
        XCTAssertNotEqual(toggle.value as? Int ?? -1, before, "The switch flips the appearance")
        toggle.click()
        XCTAssertEqual(toggle.value as? Int ?? -1, before)

        let view = app.menuBars.menuBarItems["View"]
        view.click()
        view.menuItems["Appearance"].click()
        view.menuItems["Match System"].click()
    }
}
