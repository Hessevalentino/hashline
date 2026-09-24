import Foundation
import Testing
@testable import HashlineCore

struct ImageLinksTests {
    let folder = URL(fileURLWithPath: "/Users/me/Notes/Kniha", isDirectory: true)
    var document: URL { folder.appendingPathComponent("kapitola.md") }

    @Test func resolveSources() {
        let asset = folder.appendingPathComponent("assets/a.png")
        #expect(ImageLinks.resolve("assets/a.png", base: folder) == .local(asset))
        #expect(ImageLinks.resolve("../img/b%20c.png", base: folder)
                == .local(URL(fileURLWithPath: "/Users/me/Notes/img/b c.png")))
        #expect(ImageLinks.resolve("/tmp/x.png", base: folder) == .local(URL(fileURLWithPath: "/tmp/x.png")))
        #expect(ImageLinks.resolve("https://x.cz/a.png", base: folder) == .remote(URL(string: "https://x.cz/a.png")!))
        #expect(ImageLinks.resolve("data:image/png;base64,AA", base: folder) == .data)
        #expect(ImageLinks.resolve("a.png", base: nil) == .unresolved)
    }

    @Test func previewSourceUsesAssetScheme() throws {
        let source = ImageLinks.previewSource("assets/obr á.png", base: folder)
        #expect(source.hasPrefix("hashline-asset:///Users/me/Notes/Kniha/assets/obr%20"))
        // File URLs decompose "á" (NFD); APFS treats both forms as the same name.
        let url = try #require(URL(string: source))
        let path = try #require(ImageLinks.filePath(fromAssetURL: url))
        #expect(path.precomposedStringWithCanonicalMapping == "/Users/me/Notes/Kniha/assets/obr á.png")
    }

    @Test func rootURLFromFrontMatter() {
        let web = "---\nhashline-root-url: https://blog.cz/static\n---\n![a](a.png)" as NSString
        #expect(ImageLinks.base(documentURL: document, text: web) == URL(string: "https://blog.cz/static/"))
        let relative = "---\nhashline-root-url: ../public\n---\n" as NSString
        #expect(ImageLinks.base(documentURL: document, text: relative)
                == URL(fileURLWithPath: "/Users/me/Notes/public", isDirectory: true))
        #expect(ImageLinks.base(documentURL: document, text: "no front matter") == folder)
    }

    @Test func relativeLinks() {
        #expect(ImageLinks.relativeLink(from: document, to: folder.appendingPathComponent("assets/a b.png"))
                == "assets/a%20b.png")
        #expect(ImageLinks.relativeLink(from: document, to: URL(fileURLWithPath: "/Users/me/Pictures/x.png"))
                == "../../Pictures/x.png")
        #expect(ImageLinks.assetsFolder(for: document, perDocument: true).lastPathComponent == "kapitola.assets")
    }

    @Test func referencesWithSourceRanges() {
        let text = "Text ![a](assets/a.png) and ![b](https://x.cz/b.png \"title\").\n" as NSString
        let references = ImageLinks.references(in: BlockMap(text: text as String).blocks, text: text)
        #expect(references.map(\.source) == ["assets/a.png", "https://x.cz/b.png"])
        #expect(references.map { text.substring(with: $0.sourceRange) } == ["assets/a.png", "https://x.cz/b.png"])
    }

    @Test func rendererRewritesImagesAndHTMLImages() {
        var options = HTMLRenderer.Options.preview
        options.highlightCode = false
        options.imageBase = folder
        let html = HTMLRenderer.body(for: BlockMap(text: "![a](a.png)\n\n<img src=\"b.png\" width=\"100\">\n").blocks,
                                     options: options)
        #expect(html.contains("<img src=\"hashline-asset:///Users/me/Notes/Kniha/a.png\" alt=\"a\" loading=\"lazy\""))
        #expect(html.contains("<img src=\"hashline-asset:///Users/me/Notes/Kniha/b.png\" width=\"100\">"))
    }
}

extension ImageLinksTests {
    @Test func accessCheckResolvesDotsAndSymlinks() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("access-\(UUID().uuidString)")
        let library = base.appendingPathComponent("library")
        let outside = base.appendingPathComponent("outside")
        try manager.createDirectory(at: library, withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: base) }
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.png"))
        try manager.createSymbolicLink(at: library.appendingPathComponent("link.png"),
                                       withDestinationURL: outside.appendingPathComponent("secret.png"))
        try Data("img".utf8).write(to: library.appendingPathComponent("ok.png"))

        #expect(ImageLinks.isInside(library.appendingPathComponent("ok.png"), roots: [library]))
        #expect(!ImageLinks.isInside(library.appendingPathComponent("../outside/secret.png"), roots: [library]))
        #expect(!ImageLinks.isInside(library.appendingPathComponent("link.png"), roots: [library]),
                "A symlink out of the library is outside it")
        #expect(!ImageLinks.isInside(URL(fileURLWithPath: library.path + "-evil/x.png"), roots: [library]),
                "A sibling with the same prefix is not inside")
        #expect(ImageLinks.isServableImage(URL(fileURLWithPath: "/a/b.JPG")))
        #expect(!ImageLinks.isServableImage(URL(fileURLWithPath: "/a/b.md")))
        #expect(!ImageLinks.isServableImage(URL(fileURLWithPath: "/a/id_rsa")))
    }

    @Test func markdownLinksWithUnsafeSchemesLoseTheirTarget() {
        let blocks = BlockMap(text: "[x](javascript:alert(1)) ![y](javascript:alert(1)) [ok](https://a.cz)").blocks
        let html = HTMLRenderer.body(for: blocks, options: .export)
        #expect(html.contains("<a>x</a>"))
        #expect(html.contains("<img src=\"\""))
        #expect(html.contains("<a href=\"https://a.cz\">ok</a>"))
        #expect(!html.contains("javascript"))
    }
}
