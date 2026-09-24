import XCTest

/// F0 acceptance, driven by scripts/verify-f0.sh which copies the fixtures into the app
/// container and compares the saved files byte for byte afterwards.
/// Skipped unless the script provides the file list.
final class RoundTripUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Opens each file, types a character and deletes it (document becomes dirty
    /// with unchanged content), saves and quits.
    @MainActor
    func testEditAndSaveKeepsBytes() throws {
        let files = try environmentList("HASHLINE_ROUNDTRIP_FILES")
        for file in files {
            let app = launch(opening: file)
            let textView = app.windows[file].textViews.firstMatch
            XCTAssertTrue(textView.waitForExistence(timeout: 10), "\(file) did not open")
            textView.typeText("x")
            textView.typeKey(.delete, modifierFlags: [])
            app.typeKey("s", modifierFlags: .command)
            Thread.sleep(forTimeInterval: 1.5)
            XCTAssertEqual(app.state, .runningForeground, "App terminated while saving \(file)")
            app.terminate()
        }
    }

    /// Types enough keystrokes for one latency report (see TypingLatency).
    @MainActor
    func testTypingLatencyInLargeFile() throws {
        let files = try environmentList("HASHLINE_LATENCY_FILE")
        let file = try XCTUnwrap(files.first)
        let app = launch(opening: file)
        let textView = app.windows[file].textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        for _ in 0..<4 {
            textView.typeText("Příliš žluťoučký kůň úpěl ďábelské ódy. ")
        }
        textView.typeText("\n")
        Thread.sleep(forTimeInterval: 1)
        app.terminate()
    }

    private func environmentList(_ key: String) throws -> [String] {
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
            throw XCTSkip("\(key) not set; run scripts/verify-f0.sh")
        }
        return value.split(separator: ",").map(String.init)
    }

    @MainActor
    private func launch(opening fileName: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName]
        // Extra launch arguments, e.g. "-showsPreview NO" to measure the editor alone.
        if let extra = ProcessInfo.processInfo.environment["HASHLINE_LAUNCH_ARGUMENTS"] {
            app.launchArguments += extra.split(separator: " ").map(String.init)
        }
        app.launch()
        return app
    }
}
