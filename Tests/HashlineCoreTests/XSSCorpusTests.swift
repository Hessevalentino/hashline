import Foundation
import Testing
@testable import HashlineCore

/// F10: attack vectors (OWASP XSS filter evasion and Markdown-specific ones) rendered the way the
/// preview, export and Quick Look render them. No output may contain anything that could run script.
struct XSSCorpusTests {
    static let vectors: [String] = [
        // Script and event handlers in raw HTML
        "<script>alert(1)</script>",
        "<SCRIPT SRC=http://x/xss.js></SCRIPT>",
        "<<script>script>alert(1)<</script>/script>",
        "<scr<script>ipt>alert(1)</scr</script>ipt>",
        "<img src=x onerror=alert(1)>",
        "<IMG SRC=\"javascript:alert('XSS');\">",
        "<IMG SRC=JaVaScRiPt:alert('XSS')>",
        "<IMG SRC=`javascript:alert(\"RSnake says, 'XSS'\")`>",
        "<img src=x:alert(alt) onerror=eval(src) alt=0>",
        "<img \"\"\"><script>alert(1)</script>\">",
        "<img src=\"x\" style=\"background:url(javascript:alert(1))\">",
        "<img src=\"x\" style=\"width: expression(alert(1))\">",
        "<img src=\"data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoMSk+\">",
        "<img src=\"data:text/html,<script>alert(1)</script>\">",
        "<img/src=x/onerror=alert(1)>",
        "<img src=x onerror\t=alert(1)>",
        "<svg onload=alert(1)>",
        "<svg><script>alert(1)</script></svg>",
        "<math><mtext><table><mglyph><style><img src=x onerror=alert(1)>",
        "<details open ontoggle=alert(1)>x</details>",
        "<body onload=alert(1)>",
        "<iframe src=javascript:alert(1)></iframe>",
        "<iframe srcdoc=\"<script>alert(1)</script>\"></iframe>",
        "<object data=javascript:alert(1)></object>",
        "<embed src=javascript:alert(1)>",
        "<link rel=stylesheet href=javascript:alert(1)>",
        "<meta http-equiv=\"refresh\" content=\"0;url=javascript:alert(1)\">",
        "<base href=\"javascript:alert(1)//\">",
        "<form><button formaction=javascript:alert(1)>x</button></form>",
        "<input autofocus onfocus=alert(1)>",
        "<style>@import 'javascript:alert(1)';</style>",
        "<div style=\"background:url(javascript:alert(1))\">x</div>",
        "<a href=\"javascript:alert(1)\">x</a>",
        "<a href=\"JaVaScRiPt:alert(1)\">x</a>",
        "<a href=\"  javascript:alert(1)\">x</a>",
        "<a href=\"jav&#x09;ascript:alert(1)\">x</a>",
        "<a href=\"jav\tascript:alert(1)\">x</a>",
        "<a href=\"&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;alert(1)\">x</a>",
        "<a href=javascript&colon;alert(1)>x</a>",
        "<a href=\"vbscript:msgbox(1)\">x</a>",
        "<a href=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==\">x</a>",
        "<a href=\"x\" onmouseover=\"alert(1)\">x</a>",
        "<a title='x' onclick='alert(1)' href='#'>x</a>",
        "<kbd onclick=alert(1)>x</kbd>",
        "<!--<img src=x onerror=alert(1)>-->",
        "<!-- --!><img src=x onerror=alert(1)> -->",
        "<img src=x onerror=&#97;&#108;&#101;&#114;&#116;&#40;&#49;&#41;>",
        "<xss onafterscriptexecute=alert(1)><script>1</script>",
        "<a href=\"#\" xlink:href=\"javascript:alert(1)\">x</a>",
        // Markdown syntax
        "[x](javascript:alert(1))",
        "[x](JaVaScRiPt:alert(1))",
        "[x](  javascript:alert(1)  )",
        "[x](javascript&#58;alert(1))",
        "[x](&#x6A;avascript:alert(1))",
        "[x](<javascript:alert(1)>)",
        "[x](vbscript:alert(1))",
        "[x](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)",
        "<javascript:alert(1)>",
        "[x][r]\n\n[r]: javascript:alert(1)",
        "![x](javascript:alert(1))",
        "![x](data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoMSk+)",
        "[a](http://x \"\\\" onmouseover=\\\"alert(1)\")",
        "![a\" onerror=\"alert(1)](x.png)",
        "# <img src=x onerror=alert(1)>",
        "| a |\n|---|\n| <img src=x onerror=alert(1)> |",
        "Text[^1]\n\n[^1]: <img src=x onerror=alert(1)>",
        "`<script>alert(1)</script>`",
        "```html\n<script>alert(1)</script>\n```",
        "```mermaid\ngraph TD; A[\"<img src=x onerror=alert(1)>\"]-->B\n```",
        "$\\href{javascript:alert(1)}{x}$",
        "$$\n\\url{javascript:alert(1)}\n$$",
        "---\ntitle: </code></pre><script>alert(1)</script>\n---\n\nx",
        ":rocket:<script>alert(1)</script>",
        "==<img src=x onerror=alert(1)>==",
        "www.example.com/\"><script>alert(1)</script>",
        "- [ ] <img src=x onerror=alert(1)>",
        "> <iframe src=javascript:alert(1)>",
    ]

    /// Output for every renderer configuration that shows untrusted Markdown.
    static func renders(_ markdown: String) -> [String] {
        let blocks = BlockMap(text: markdown).blocks
        var preview = HTMLRenderer.Options.preview
        preview.extensions = InlineExtensionSettings(highlight: true, superscript: true, subscriptText: true,
                                                     math: true)
        preview.imageBase = URL(fileURLWithPath: "/tmp/")
        let export = HTMLRenderer.Options.export
        return [preview, export].map { ExportDocument.body(blocks: blocks, text: markdown as NSString, options: $0) }
            + [PreviewRenderer.renderAll(blocks, text: markdown as NSString, options: preview).map(\.html).joined()]
    }

    /// Real tags in the output (text that looks like a tag is escaped and does not match).
    static func tags(in html: String) -> [String] {
        guard let pattern = try? NSRegularExpression(pattern: #"<[a-zA-Z][^>]*>"#) else { return [] }
        let text = html as NSString
        return pattern.matches(in: html, range: NSRange(location: 0, length: text.length))
            .map { text.substring(with: $0.range) }
    }

    static let forbiddenTags: Set<String> = ["script", "iframe", "object", "embed", "link", "meta", "base", "form",
                                             "button", "textarea", "style", "svg", "frame", "frameset", "applet"]

    /// Attributes of a tag as a browser parses them: name → raw value (quoted values stay whole, so
    /// `title="&quot; onclick=…"` is one title, not an event handler).
    static func attributes(of tag: String) -> [(name: String, value: String)] {
        guard let pattern = try? NSRegularExpression(
            pattern: #"\s([^\s"'>/=]+)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s"'>]+))?"#) else { return [] }
        let text = tag as NSString
        let body = NSRange(location: 1, length: max(text.length - 1, 0))
        return pattern.matches(in: tag, range: body).map { match in
            let name = text.substring(with: match.range(at: 1)).lowercased()
            var value = match.range(at: 2).location == NSNotFound ? "" : text.substring(with: match.range(at: 2))
            if value.hasPrefix("\"") || value.hasPrefix("'") { value = String(value.dropFirst().dropLast()) }
            return (name, value)
        }
    }

    /// What makes one output unsafe, or nil.
    static func problem(in html: String) -> String? {
        for tag in tags(in: html) {
            let lower = tag.lowercased()
            let name = String(lower.dropFirst().prefix { $0.isLetter || $0.isNumber })
            if forbiddenTags.contains(name) { return "forbidden tag \(tag)" }
            let attributes = attributes(of: tag)
            if name == "input", !attributes.contains(where: { $0.name == "type" && $0.value == "checkbox" }) {
                return "input \(tag)"
            }
            for (attribute, rawValue) in attributes {
                if attribute.hasPrefix("on") { return "event handler \(tag)" }
                if ["srcdoc", "formaction", "xlink:href"].contains(attribute) { return "dangerous attribute \(tag)" }
                let value = decodeEntities(rawValue).lowercased()
                if attribute == "style", value.contains("expression(") || value.contains("url(") {
                    return "style \(tag)"
                }
                guard ["href", "src", "action", "data"].contains(attribute) else { continue }
                let compact = value.filter { !$0.isWhitespace && $0 != "\u{0}" }
                for scheme in ["javascript:", "vbscript:", "data:text", "data:image/svg", "livescript:"]
                where compact.hasPrefix(scheme) {
                    return "\(scheme) URL in \(tag)"
                }
            }
        }
        return nil
    }

    /// How a browser reads an attribute value: each entity once (`&amp;#58;` stays the text `&#58;`).
    static func decodeEntities(_ value: String) -> String {
        let named = ["colon": ":", "tab": "\t", "newline": "\n", "amp": "&", "quot": "\"", "lt": "<", "gt": ">",
                     "apos": "'"]
        guard let pattern = try? NSRegularExpression(pattern: #"&(#x[0-9a-f]+|#[0-9]+|[a-z]+);?"#,
                                                     options: .caseInsensitive) else { return value }
        let text = value as NSString
        var output = ""
        var cursor = 0
        for match in pattern.matches(in: value, range: NSRange(location: 0, length: text.length)) {
            output += text.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let entity = text.substring(with: match.range(at: 1)).lowercased()
            if entity.hasPrefix("#") {
                let hex = entity.hasPrefix("#x")
                let digits = entity.dropFirst(hex ? 2 : 1)
                if let number = UInt32(digits, radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) {
                    output.unicodeScalars.append(scalar)
                }
            } else {
                output += named[entity] ?? text.substring(with: match.range)
            }
            cursor = NSMaxRange(match.range)
        }
        return output + text.substring(from: cursor)
    }

    @Test(arguments: vectors)
    func vectorIsInert(_ vector: String) {
        for html in Self.renders(vector) {
            let problem = Self.problem(in: html)
            #expect(problem == nil, "\(vector)\n→ \(problem ?? "")\n\(html)")
        }
    }

    @Test func checkerCatchesUnsafeOutput() {
        #expect(Self.problem(in: "<a href=\"javascript:alert(1)\">x</a>") != nil)
        #expect(Self.problem(in: "<a href=\"&#106;avascript:alert(1)\">x</a>") != nil)
        #expect(Self.problem(in: "<img src=\"x\" onerror=\"alert(1)\">") != nil)
        #expect(Self.problem(in: "<script>alert(1)</script>") != nil)
        #expect(Self.problem(in: "&lt;script&gt;alert(1)&lt;/script&gt;") == nil)
        #expect(Self.problem(in: "<a href=\"x\" title=\"&quot; onclick=&quot;alert(1)\">x</a>") == nil)
        #expect(Self.problem(in: "<a href=\"x\" onclick=\"alert(1)\">x</a>") != nil)
        #expect(Self.problem(in: "<a href=\"jav&#x09;ascript:alert(1)\">x</a>") != nil)
        #expect(Self.problem(in: "<a href=\"jav&amp;#x09;ascript:alert(1)\">x</a>") == nil)
        #expect(Self.problem(in: "<a href=\"https://example.com\">x</a>") == nil)
    }

    @Test func exportedPageForbidsScripts() {
        let page = ExportDocument.html(body: Self.renders(Self.vectors.joined(separator: "\n\n"))[1], title: "x",
                                       stylesheet: "")
        #expect(page.contains("default-src 'none'"))
        #expect(!page.lowercased().contains("<script"))
    }
}

/// Denial of service: hostile documents must not freeze rendering.
struct HostileInputTests {
    @Test func mathMacroBombStopsQuickly() {
        let bombs = [#"$\def\a{\a\a}\a$"#,
                     #"$\def\x{xxxxxxxxxx}\def\y{\x\x\x\x\x\x\x\x\x\x}\def\z{\y\y\y\y\y\y\y\y\y\y}\z\z\z\z$"#,
                     "$" + String(repeating: "{", count: 5_000) + "x" + String(repeating: "}", count: 5_000) + "$"]
        for bomb in bombs {
            let clock = ContinuousClock()
            let elapsed = clock.measure {
                _ = ExportDocument.body(blocks: BlockMap(text: bomb).blocks, text: bomb as NSString, options: .export)
            }
            #expect(elapsed < .seconds(2), "\(bomb.prefix(40))… took \(elapsed)")
        }
    }

    @Test func deepNestingRendersQuickly() {
        let inputs = [String(repeating: "> ", count: 1_000) + "x",
                      String(repeating: "*", count: 20_000) + "x" + String(repeating: "*", count: 20_000),
                      String(repeating: "[", count: 20_000) + "x" + String(repeating: "](y)", count: 20_000),
                      (0..<1_000).map { String(repeating: "  ", count: $0) + "- item" }.joined(separator: "\n")]
        for input in inputs {
            let clock = ContinuousClock()
            let elapsed = clock.measure {
                _ = ExportDocument.body(blocks: BlockMap(text: input).blocks, text: input as NSString, options: .export)
            }
            #expect(elapsed < .seconds(2), "\(input.prefix(20))… took \(elapsed)")
        }
    }
}

struct NestingGuardTests {
    @Test func ordinaryTextIsUntouched() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        for name in ["small.md", "extended.md", "math-mermaid.md", "code.md"] {
            let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
            #expect(NestingGuard.defused(text) == text, "\(name) changed")
        }
        let sample = "> > quote\n\n- a\n  - b\n    - c\n\n**bold** *em* ~~s~~ [link](x) [[wiki]]\n"
        #expect(NestingGuard.defused(sample) == sample)
    }

    @Test func deepNestingIsLimitedWithoutMovingText() {
        let inputs = [String(repeating: "> ", count: 200) + "x",
                      String(repeating: "*", count: 500) + "x" + String(repeating: "*", count: 500),
                      (0..<200).map { String(repeating: "  ", count: $0) + "- item" }.joined(separator: "\n"),
                      String(repeating: "*a ", count: 300) + String(repeating: "a* ", count: 300),
                      String(repeating: "![", count: 300) + "x" + String(repeating: "](y)", count: 300)]
        for input in inputs {
            let output = NestingGuard.defused(input)
            #expect(output != input)
            #expect(output.utf8.count == input.utf8.count)
            #expect(output.utf16.count == input.utf16.count)
        }
    }
}
