import Foundation
import JavaScriptCore

/// A highlighted token inside a code block: UTF-16 range relative to the code, highlight.js scope
/// (e.g. `keyword`, `title.function`).
public struct CodeToken: Equatable, Sendable {
    public let range: NSRange
    public let scope: String
}

/// Syntax highlighting of fenced code blocks with highlight.js (ADR 0008), in JavaScriptCore on a
/// private serial queue: no WebView, no page, only tokenizing. Loaded on first use.
public final class CodeHighlighter: @unchecked Sendable {
    // @unchecked: the JSContext is created and used only on `queue`.
    public static let shared = CodeHighlighter()

    /// Larger blocks stay unhighlighted: about 0.15 ms per line.
    public static let maximumLength = 60_000

    private let queue = DispatchQueue(label: "cz.hashline.code-highlighter", qos: .userInitiated)
    private var context: JSContext?
    private var tokensFunction: JSValue?
    private var htmlFunction: JSValue?

    private init() {}

    /// Tokens for the editor. Blocking; call off the main thread or use `tokens(_:language:completion:)`.
    public func tokens(code: String, language: String) -> [CodeToken]? {
        guard code.utf16.count <= Self.maximumLength else { return nil }
        return queue.sync { () -> [CodeToken]? in
            guard let function = loadedFunctions()?.tokens,
                  let values = function.call(withArguments: [code, language])?.toArray() else { return nil }
            var tokens: [CodeToken] = []
            tokens.reserveCapacity(values.count / 3)
            var index = 0
            while index + 2 < values.count {
                if let start = values[index] as? Int, let length = values[index + 1] as? Int,
                   let scope = values[index + 2] as? String {
                    tokens.append(CodeToken(range: NSRange(location: start, length: length), scope: scope))
                }
                index += 3
            }
            return tokens
        }
    }

    /// Asynchronous variant; `completion` runs on the main queue.
    public func tokens(code: String, language: String,
                       completion: @escaping @Sendable @MainActor ([CodeToken]?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.tokens(code: code, language: language)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(result) } }
        }
    }

    /// Highlighted HTML (escaped, `<span class="hljs-…">`) for the preview and export.
    public func html(code: String, language: String) -> String? {
        guard code.utf16.count <= Self.maximumLength else { return nil }
        return queue.sync {
            guard let function = loadedFunctions()?.html,
                  let value = function.call(withArguments: [code, language]), value.isString else { return nil }
            return value.toString()
        }
    }

    /// Whether highlight.js knows the language or alias (e.g. `js`, `sh`, `yml`).
    public func supports(_ language: String) -> Bool {
        queue.sync {
            loadedFunctions()?.supports.call(withArguments: [language])?.toBool() ?? false
        }
    }

    private struct Functions {
        let tokens: JSValue
        let html: JSValue
        let supports: JSValue
    }

    private func loadedFunctions() -> Functions? {
        dispatchPrecondition(condition: .onQueue(queue))
        if context == nil {
            guard let url = Bundle.module.url(forResource: "highlight.min", withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  let context = JSContext() else { return nil }
            context.evaluateScript(source)
            context.evaluateScript(Self.helpers)
            self.context = context
        }
        guard let context,
              let tokens = context.objectForKeyedSubscript("hashlineTokens"), !tokens.isUndefined,
              let html = context.objectForKeyedSubscript("hashlineHTML"), !html.isUndefined,
              let supports = context.objectForKeyedSubscript("hashlineSupports"), !supports.isUndefined else {
            return nil
        }
        return Functions(tokens: tokens, html: html, supports: supports)
    }

    private static let helpers = """
        function hashlineSupports(lang) { return !!hljs.getLanguage(lang); }
        function hashlineTokens(code, lang) {
            if (!hljs.getLanguage(lang)) { return null; }
            const result = hljs.highlight(code, { language: lang, ignoreIllegals: true });
            const out = [];
            let position = 0;
            (function walk(node, scope) {
                if (typeof node === 'string') {
                    if (scope) { out.push(position, node.length, scope); }
                    position += node.length;
                    return;
                }
                const inner = node.scope || scope;
                for (const child of node.children) { walk(child, inner); }
            })(result._emitter.rootNode, null);
            return out;
        }
        function hashlineHTML(code, lang) {
            if (!hljs.getLanguage(lang)) { return null; }
            return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
        }
        """
}
