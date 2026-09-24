/// Converts swift-markdown source locations (1-based line, 1-based UTF-8 byte column)
/// to UTF-16 offsets, the unit of NSString and NSRange.
struct LineIndex {
    private let bytes: [UInt8]
    private var lineStartBytes: [Int] = [0]
    private var lineStartUTF16: [Int] = [0]
    let utf16Length: Int

    init(_ text: String) {
        bytes = Array(text.utf8)
        var utf16 = 0
        var index = 0
        let count = bytes.count
        while index < count {
            let byte = bytes[index]
            utf16 += Self.utf16Width(leadByte: byte)
            index += 1
            // CommonMark line endings: LF, CRLF, CR.
            if byte == 0x0A || (byte == 0x0D && (index == count || bytes[index] != 0x0A)) {
                lineStartBytes.append(index)
                lineStartUTF16.append(utf16)
            }
        }
        utf16Length = utf16
    }

    var lineCount: Int { lineStartBytes.count }

    /// Source text between two swift-markdown locations.
    func text(fromLine startLine: Int, column startColumn: Int, toLine endLine: Int, column endColumn: Int) -> String {
        guard startLine >= 1, endLine >= 1, startLine <= lineStartBytes.count, endLine <= lineStartBytes.count else {
            return ""
        }
        let start = min(lineStartBytes[startLine - 1] + max(startColumn - 1, 0), bytes.count)
        let end = min(lineStartBytes[endLine - 1] + max(endColumn - 1, 0), bytes.count)
        guard end > start else { return "" }
        return String(bytes: bytes[start..<end], encoding: .utf8) ?? ""
    }

    /// Text of a 1-based line without its line break.
    func text(ofLine line: Int) -> String {
        guard line >= 1, line <= lineStartBytes.count else { return "" }
        let start = lineStartBytes[line - 1]
        var end = line < lineStartBytes.count ? lineStartBytes[line] : bytes.count
        while end > start, bytes[end - 1] == 0x0A || bytes[end - 1] == 0x0D { end -= 1 }
        return String(bytes: bytes[start..<end], encoding: .utf8) ?? ""
    }

    func utf16Offset(line: Int, column: Int) -> Int {
        guard line >= 1 else { return 0 }
        guard line <= lineStartBytes.count else { return utf16Length }
        let start = lineStartBytes[line - 1]
        let end = min(start + max(column - 1, 0), bytes.count)
        var offset = lineStartUTF16[line - 1]
        for index in start..<end {
            offset += Self.utf16Width(leadByte: bytes[index])
        }
        return offset
    }

    /// 1-based line containing the UTF-16 offset.
    func line(containingUTF16 offset: Int) -> Int {
        var low = 0
        var high = lineStartUTF16.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartUTF16[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    func utf16Offset(ofLineStart line: Int) -> Int {
        guard line >= 1 else { return 0 }
        return line <= lineStartUTF16.count ? lineStartUTF16[line - 1] : utf16Length
    }

    /// UTF-16 units a UTF-8 byte contributes: continuation bytes 0, 4-byte leads 2 (surrogate pair).
    private static func utf16Width(leadByte byte: UInt8) -> Int {
        if byte < 0x80 { return 1 }
        if byte < 0xC0 { return 0 }
        if byte < 0xF0 { return 1 }
        return 2
    }
}
