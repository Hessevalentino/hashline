import Foundation
import Markdown

/// Image references in a document and how their sources resolve.
public enum ImageLinks {
    /// URL scheme the preview uses for local files; the app serves it from folders it may read.
    public static let assetScheme = "hashline-asset"

    /// A local image source as a preview URL: `hashline-asset:///absolute/path`.
    public static func assetURL(for fileURL: URL) -> String {
        var components = URLComponents()
        components.scheme = assetScheme
        components.host = ""
        components.path = fileURL.standardizedFileURL.path
        return components.string ?? "\(assetScheme):///"
    }

    /// The file path inside a `hashline-asset:` URL.
    public static func filePath(fromAssetURL url: URL) -> String? {
        guard url.scheme == assetScheme else { return nil }
        let path = url.path(percentEncoded: false)
        return path.isEmpty ? nil : path
    }

    /// How an image source should be loaded.
    public enum Source: Equatable, Sendable {
        case remote(URL)
        case local(URL)
        case data
        case unresolved
    }

    /// Resolves `src`: remote URLs stay, `data:` stays, absolute and relative paths become file URLs.
    /// Relative paths are resolved against `base` (the front matter `hashline-root-url` or the
    /// document's folder).
    public static func resolve(_ source: String, base: URL?) -> Source {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .unresolved }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("data:") { return .data }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: trimmed).map(Source.remote) ?? .unresolved
        }
        let path = trimmed.removingPercentEncoding ?? trimmed
        if lower.hasPrefix("file://") {
            return URL(string: trimmed).map { .local($0.standardizedFileURL) } ?? .unresolved
        }
        if path.hasPrefix("/") { return .local(URL(fileURLWithPath: path).standardizedFileURL) }
        if path.hasPrefix("~/") {
            return .local(URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL)
        }
        guard let base else { return .unresolved }
        if base.isFileURL {
            return .local(URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL)
        }
        return URL(string: path, relativeTo: base).map { .remote($0.absoluteURL) } ?? .unresolved
    }

    /// The `src` the preview uses: remote and data URLs unchanged, local files via the asset scheme.
    public static func previewSource(_ source: String, base: URL?) -> String {
        switch resolve(source, base: base) {
        case .local(let url): return assetURL(for: url)
        case .remote(let url): return url.absoluteString
        case .data, .unresolved: return source
        }
    }

    /// Base for relative image paths: `hashline-root-url` in the front matter (a URL or a path
    /// relative to the document), otherwise the document's folder.
    public static func base(documentURL: URL?, text: NSString?) -> URL? {
        let folder = documentURL?.deletingLastPathComponent()
        guard let text, let frontMatter = FrontMatter.detect(in: text) else { return folder }
        let yaml = text.substring(with: frontMatter.contentRange)
        for line in yaml.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "hashline-root-url" else { continue }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if value.hasPrefix("http://") || value.hasPrefix("https://") {
                return URL(string: value.hasSuffix("/") ? value : value + "/")
            }
            if value.hasPrefix("/") { return URL(fileURLWithPath: value, isDirectory: true) }
            if let folder {
                return URL(fileURLWithPath: value, isDirectory: true, relativeTo: folder).standardizedFileURL
            }
        }
        return folder
    }

    /// Whether `file` lies inside one of `roots` after `..` and symbolic links are resolved, so a link
    /// in an allowed folder cannot point the preview at a file elsewhere.
    public static func isInside(_ file: URL, roots: [URL]) -> Bool {
        let path = file.standardizedFileURL.resolvingSymlinksInPath().path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        }
    }

    /// File types the preview's asset scheme serves: images only.
    public static func isServableImage(_ file: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "ico", "avif", "svg"]
            .contains(file.pathExtension.lowercased())
    }

    /// An image reference in the source: the whole `![alt](src)` range and the `src` range.
    public struct Reference: Equatable, Sendable {
        public let range: NSRange
        public let sourceRange: NSRange
        public let source: String
    }

    /// Markdown image references (`![alt](src)`) in document order, with UTF-16 ranges.
    public static func references(in blocks: [MarkdownBlock], text: NSString) -> [Reference] {
        var result: [Reference] = []
        for block in blocks {
            var walker = ImageCollector(block: block, text: text)
            walker.visit(block.markup)
            result += walker.references
        }
        return result
    }

    /// Folder for pasted and dropped images, per setting: `assets` or `<document name>.assets`.
    public static func assetsFolder(for documentURL: URL, perDocument: Bool) -> URL {
        let folder = documentURL.deletingLastPathComponent()
        let name = perDocument ? documentURL.deletingPathExtension().lastPathComponent + ".assets" : "assets"
        return folder.appendingPathComponent(name, isDirectory: true)
    }

    /// Relative link from the document to a file, percent-encoded where Markdown needs it.
    public static func relativeLink(from documentURL: URL, to fileURL: URL) -> String {
        let base = documentURL.deletingLastPathComponent().standardizedFileURL.pathComponents
        let target = fileURL.standardizedFileURL.pathComponents
        var common = 0
        while common < min(base.count, target.count), base[common] == target[common] { common += 1 }
        let parts = Array(repeating: "..", count: base.count - common) + target[common...]
        let path = parts.joined(separator: "/")
        // Parentheses would end the Markdown link destination.
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "()"))
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}

private struct ImageCollector: MarkupWalker {
    let block: MarkdownBlock
    let text: NSString
    var references: [ImageLinks.Reference] = []

    mutating func visitImage(_ image: Image) {
        guard let range = block.range(of: image), let source = image.source, NSMaxRange(range) <= text.length else {
            return
        }
        // The source is inside the last `(…)` of `![alt](src "title")`.
        let whole = text.substring(with: range) as NSString
        let open = whole.range(of: "](", options: .backwards)
        guard open.location != NSNotFound else { return }
        let inner = NSRange(location: open.location + 2, length: whole.length - open.location - 3)
        let innerText = whole.substring(with: inner) as NSString
        var sourceRange = innerText.range(of: source)
        if sourceRange.location == NSNotFound,
           let encoded = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            sourceRange = innerText.range(of: encoded)
        }
        if sourceRange.location == NSNotFound {
            // `<path with spaces>` or escaped: use the first token.
            let token = innerText.range(of: #"^\s*<?[^\s>]+"#, options: .regularExpression)
            sourceRange = token
        }
        guard sourceRange.location != NSNotFound else { return }
        let absolute = NSRange(location: range.location + inner.location + sourceRange.location,
                               length: sourceRange.length)
        references.append(ImageLinks.Reference(range: range, sourceRange: absolute, source: source))
    }
}
