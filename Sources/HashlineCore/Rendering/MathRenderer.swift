import Foundation
import JavaScriptCore

/// TeX → HTML with KaTeX in JavaScriptCore (no WebView, no DOM needed), on a private serial queue.
/// Loaded on first use; results are cached. `trust` stays off, so `\href` and friends cannot
/// inject links or scripts; errors render as the source in red instead of throwing.
public final class MathRenderer: @unchecked Sendable {
    // @unchecked: the JSContext and the cache are used only on `queue`.
    public static let shared = MathRenderer()

    private let queue = DispatchQueue(label: "cz.hashline.math", qos: .userInitiated)
    private var context: JSContext?
    private var render: JSValue?
    private var cache: [String: String] = [:]
    private static let cacheLimit = 2_000

    private init() {}

    public func html(tex: String, displayMode: Bool) -> String? {
        let key = (displayMode ? "D" : "I") + tex
        return queue.sync {
            if let cached = cache[key] { return cached }
            guard let render = loadedRender(),
                  let value = render.call(withArguments: [tex, displayMode]), value.isString,
                  let html = value.toString() else { return nil }
            if cache.count >= Self.cacheLimit { cache.removeAll(keepingCapacity: true) }
            cache[key] = html
            return html
        }
    }

    private func loadedRender() -> JSValue? {
        dispatchPrecondition(condition: .onQueue(queue))
        if let render { return render }
        guard let url = Bundle.module.url(forResource: "katex.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { return nil }
        context.evaluateScript(source)
        context.evaluateScript("""
            function hashlineMath(tex, display) {
                return katex.renderToString(tex, {
                    displayMode: display, throwOnError: false, trust: false, strict: 'ignore',
                    output: 'htmlAndMathml'
                });
            }
            """)
        self.context = context
        render = context.objectForKeyedSubscript("hashlineMath").flatMap { $0.isUndefined ? nil : $0 }
        return render
    }
}

/// Where math appears in Markdown source.
public enum MathSyntax {
    /// `$…$`: the opening `$` is followed and the closing `$` preceded by a non-space, and the
    /// closing one is not followed by a digit (so "$5 and $10" stays text). `$$` is not inline math.
    static let inlinePattern = try? NSRegularExpression(
        pattern: #"(?<![\\$])\$(?=[^\s$])([^$\n]*?[^\s$\\])\$(?![\d$])"#
    )

    /// A paragraph that is `$$ … $$` as a whole: the TeX between the delimiters.
    public static func displayMath(inParagraphSource source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 else { return nil }
        return String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
