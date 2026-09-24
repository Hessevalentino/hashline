import XCTest

/// The app in Czech: menus, toolbar, find bar and Settings come from the String Catalog.
final class LocalizationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCzechInterface() throws {
        let fileName = "cs-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(cs)",
                               "-AppleLocale", "cs_CZ", "-HashlineUITestDocument", fileName]
        app.launch()
        defer { app.terminate() }
        let window = app.windows[fileName]
        XCTAssertTrue(window.textViews.firstMatch.waitForExistence(timeout: 5))

        XCTAssertTrue(window.toolbars.buttons["Tučně"].waitForExistence(timeout: 5), "Toolbar in Czech")
        let format = app.menuBars.menuBarItems["Formát"]
        format.click()
        XCTAssertTrue(format.menuItems["Kurzíva"].exists)
        XCTAssertTrue(format.menuItems["Odrážkový seznam"].exists)
        format.typeKey(.escape, modifierFlags: [])

        let view = app.menuBars.menuBarItems["Zobrazení"]
        view.click()
        XCTAssertTrue(view.menuItems["Režim čtení"].exists)
        XCTAssertTrue(view.menuItems["Zobrazit stavový řádek"].exists)
        view.typeKey(.escape, modifierFlags: [])

        app.typeKey("f", modifierFlags: [.command, .option])
        XCTAssertTrue(window.buttons["Hotovo"].waitForExistence(timeout: 3), "Find bar in Czech")

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        for tab in ["Obecné", "Editor", "Vzhled", "Obrázky", "Export"] {
            XCTAssertTrue(settings.toolbars.buttons[tab].exists, "Settings tab \(tab)")
        }
    }
}
