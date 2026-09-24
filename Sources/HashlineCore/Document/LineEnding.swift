/// Line break style of a document; new line breaks typed by the user follow it,
/// so a CRLF file does not turn into a file with mixed endings.
public enum LineEnding: String, Sendable {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"

    /// The first line break decides. Text without any line break defaults to LF.
    public static func detect(in text: String) -> LineEnding {
        let utf8 = text.utf8
        guard let index = utf8.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) else { return .lf }
        guard utf8[index] == 0x0D else { return .lf }
        let next = utf8.index(after: index)
        return next < utf8.endIndex && utf8[next] == 0x0A ? .crlf : .cr
    }
}
