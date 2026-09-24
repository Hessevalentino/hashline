import Foundation

/// Formats written through Pandoc (an external program the user installs and chooses).
public enum PandocFormat: String, CaseIterable, Sendable, Identifiable {
    case docx, odt, rtf, epub, latex, mediawiki, rst

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .docx: "Word (DOCX)"
        case .odt: "OpenDocument (ODT)"
        case .rtf: "Rich Text (RTF)"
        case .epub: "ePub"
        case .latex: "LaTeX"
        case .mediawiki: "MediaWiki"
        case .rst: "reStructuredText"
        }
    }

    public var fileExtension: String {
        switch self {
        case .latex: "tex"
        case .mediawiki: "wiki"
        default: rawValue
        }
    }
}

public enum Pandoc {
    /// Markdown as Hashline understands it: GFM plus math, footnotes, front matter.
    static let markdownReader = "gfm+tex_math_dollars+footnotes+yaml_metadata_block"

    /// Arguments for exporting Markdown (from standard input) to `outputPath`. Passed as an array to
    /// the process, never through a shell.
    public static func exportArguments(format: PandocFormat, outputPath: String, resourcePath: URL?) -> [String] {
        var arguments = ["--from", markdownReader, "--to", format.rawValue, "--standalone",
                         "--output", outputPath]
        if let resourcePath { arguments += ["--resource-path", resourcePath.path] }
        return arguments
    }

    private static let readers = ["docx": "docx", "odt": "odt", "rtf": "rtf", "epub": "epub", "html": "html",
                                  "htm": "html", "tex": "latex", "latex": "latex", "rst": "rst",
                                  "wiki": "mediawiki", "mediawiki": "mediawiki", "org": "org", "textile": "textile"]

    /// Reader for an imported file, by extension; nil when Pandoc cannot read it.
    public static func reader(forExtension fileExtension: String) -> String? {
        readers[fileExtension.lowercased()]
    }

    public static let importExtensions = ["docx", "odt", "rtf", "epub", "html", "htm", "tex", "rst", "wiki", "org"]

    /// Arguments for converting the file at `inputPath` (read as `fileExtension`) to GitHub Markdown
    /// on standard output.
    public static func importArguments(fileExtension: String, inputPath: String) -> [String]? {
        guard let reader = reader(forExtension: fileExtension) else { return nil }
        return ["--from", reader, "--to", "gfm-tex_math_gfm+tex_math_dollars", "--wrap", "none", inputPath]
    }
}
