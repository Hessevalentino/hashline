import Foundation
import Testing
@testable import HashlineCore

struct ThemeTests {
    static let themesFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Hashline/Resources/Themes", isDirectory: true)

    @Test func builtInThemesAreValidAndComplete() throws {
        let folders = try FileManager.default
            .contentsOfDirectory(at: Self.themesFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "hashlinetheme" }
        #expect(folders.count >= 4)
        var appearances: [ThemeDefinition.Appearance] = []
        for folder in folders {
            let theme = try ThemeDefinition.decode(Data(contentsOf: folder.appendingPathComponent("theme.json")))
            appearances.append(theme.appearance)
            #expect(theme.name == folder.deletingPathExtension().lastPathComponent)
            #expect(theme.editor.tokens["H1"]?.size != nil, "\(theme.name) sizes headings")
            #expect(theme.code["keyword"] != nil, "\(theme.name) colours code")
            let css = try String(contentsOf: folder.appendingPathComponent("theme.css"), encoding: .utf8)
            #expect(css.contains("body"), "\(theme.name) styles the preview")
            #expect(css.contains(".hljs"), "\(theme.name) styles highlighted code")
            // Dark themes are dark, light themes light: the appearance picks them.
            #expect(theme.styleTheme.isDark == (theme.appearance == .dark), "\(theme.name) brightness")
        }
        #expect(appearances.filter { $0 == .light }.count >= 2)
        #expect(appearances.filter { $0 == .dark }.count >= 2)
    }

    @Test func conversionKeepsTokenStyles() throws {
        let json = """
            {"name": "T", "appearance": "light",
             "editor": {"background": "#ffffff", "foreground": "#111111", "selection": "#ccddeeff",
                        "tokens": {"H1": {"color": "#ff0000", "bold": true, "size": 22},
                                   "EMPH": {"italic": true}}},
             "code": {"keyword": "#0000ff"}}
            """
        let theme = try ThemeDefinition.decode(Data(json.utf8))
        let style = theme.styleTheme
        #expect(style.style(for: .heading1)?.isBold == true)
        #expect(style.style(for: .heading1)?.fontSize == 22)
        #expect(style.style(for: .heading1)?.foreground == StyleTheme.Color(hex: "ff0000"))
        #expect(style.style(for: .emphasis)?.isItalic == true)
        #expect(style.selection?.background?.alpha ?? 0 > 0.99)
        #expect(!style.isDark)
    }

    @Test func mistakesAreReported() {
        let base = ##"{"name": "T", "appearance": "dark", "code": {}, "editor": {"background": "#000000", "##
        #expect(throws: ThemeDefinition.Failure.invalidColor("red")) {
            try ThemeDefinition.decode(Data((base + ##""foreground": "red", "tokens": {}}}"##).utf8))
        }
        #expect(throws: ThemeDefinition.Failure.unknownToken("HEADING")) {
            try ThemeDefinition.decode(Data((base + ##""foreground": "#ffffff", "tokens": {"HEADING": {}}}}"##).utf8))
        }
        #expect {
            try ThemeDefinition.decode(Data("{".utf8))
        } throws: { error in
            if case .invalidJSON = error as? ThemeDefinition.Failure { return true }
            return false
        }
    }
}
