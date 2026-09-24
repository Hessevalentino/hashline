// Prints a PDF's page count, title and bookmark tree (used by verify-export.sh).
import PDFKit

guard CommandLine.arguments.count > 1,
      let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else { exit(1) }
print("pages", document.pageCount, "title", document.documentAttributes?[PDFDocumentAttribute.titleAttribute] ?? "-")
func walk(_ outline: PDFOutline, _ depth: Int) {
    for index in 0..<outline.numberOfChildren {
        guard let child = outline.child(at: index) else { continue }
        let page = child.destination?.page.map { document.index(for: $0) + 1 } ?? 0
        print(String(repeating: "  ", count: depth) + (child.label ?? "") + " -> p\(page)")
        walk(child, depth + 1)
    }
}
if let root = document.outlineRoot { walk(root, 0) }
