import Foundation

/// A GFM table as cells. Parsing and formatting work on the source lines; the editor only sees
/// `TextEdit`s, so every table command is one undo step.
public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Sendable, Equatable {
        case none, left, center, right
    }

    public var header: [String]
    public var alignments: [Alignment]
    public var rows: [[String]]

    public var columnCount: Int { max(header.count, alignments.count, rows.map(\.count).max() ?? 0) }

    /// `lines[0]` is the header, `lines[1]` the delimiter row.
    public static func parse(_ lines: [String]) -> MarkdownTable? {
        guard lines.count >= 2, TableCommand.isDelimiterRow(lines[1]) else { return nil }
        let alignments = cells(of: lines[1]).map { cell -> Alignment in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            switch (trimmed.hasPrefix(":"), trimmed.hasSuffix(":")) {
            case (true, true): return .center
            case (true, false): return .left
            case (false, true): return .right
            default: return .none
            }
        }
        return MarkdownTable(header: cells(of: lines[0]), alignments: alignments, rows: lines.dropFirst(2).map(cells))
    }

    /// Cells of a row: split on unescaped `|`, outer pipes optional, content trimmed.
    static func cells(of line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|"), !content.hasSuffix("\\|") { content.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        var inCode = false
        for character in content {
            if character == "|", !escaped, !inCode {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                if character == "`", !escaped { inCode.toggle() }
                current.append(character)
            }
            escaped = character == "\\" && !escaped
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// Source lines with pipes aligned in a grid.
    public func formatted() -> [String] {
        let columns = max(columnCount, 1)
        func padded(_ row: [String]) -> [String] { row + Array(repeating: "", count: max(columns - row.count, 0)) }
        let header = padded(self.header)
        let body = rows.map(padded)
        let aligns = alignments + Array(repeating: .none, count: max(columns - alignments.count, 0))
        let widths = (0..<columns).map { column in
            max(3, ([header] + body).map { $0[column].count }.max() ?? 0)
        }
        func line(_ cells: [String]) -> String {
            "| " + (0..<columns).map { column -> String in
                let cell = cells[column]
                let space = widths[column] - cell.count
                switch aligns[column] {
                case .right: return String(repeating: " ", count: space) + cell
                case .center:
                    let left = space / 2
                    return String(repeating: " ", count: left) + cell + String(repeating: " ", count: space - left)
                default: return cell + String(repeating: " ", count: space)
                }
            }.joined(separator: " | ") + " |"
        }
        let delimiter = "|" + (0..<columns).map { column -> String in
            let dashes = widths[column]
            switch aligns[column] {
            case .left: return ":" + String(repeating: "-", count: dashes + 1)
            case .center: return ":" + String(repeating: "-", count: dashes) + ":"
            case .right: return String(repeating: "-", count: dashes + 1) + ":"
            case .none: return String(repeating: "-", count: dashes + 2)
            }
        }.joined(separator: "|") + "|"
        return [line(header), delimiter] + body.map(line)
    }
}

/// Table editing commands around the caret.
public enum TableCommand {
    /// Where the caret is inside a table.
    struct Location {
        let range: NSRange          // all table lines, without the final line break
        let lines: [String]
        let table: MarkdownTable
        let row: Int                // index into `lines` (0 header, 1 delimiter, 2… body)
        let column: Int
        /// Caret position within the cell's trimmed content.
        let offsetInCell: Int
    }

    private static let delimiterPattern = try? NSRegularExpression(
        pattern: #"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"#
    )

    static func isDelimiterRow(_ line: String) -> Bool {
        line.contains("-") && delimiterPattern?.firstMatch(
            in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    static func locate(in text: NSString, at location: Int) -> Location? {
        var lineRanges: [NSRange] = []
        // Expand up and down over lines containing a pipe.
        var current = text.lines(in: NSRange(location: location, length: 0))[0].content
        guard text.substring(with: current).contains("|") else { return nil }
        lineRanges.append(current)
        while current.location > 0 {
            let previous = text.lines(in: NSRange(location: current.location - 1, length: 0))[0].content
            guard text.substring(with: previous).contains("|") else { break }
            lineRanges.insert(previous, at: 0)
            current = previous
        }
        current = lineRanges[lineRanges.count - 1]
        while true {
            let next = text.lines(in: NSRange(location: current.location, length: 0))[0]
            let nextStart = NSMaxRange(next.terminator)
            guard next.terminator.length > 0, nextStart < text.length else { break }
            let following = text.lines(in: NSRange(location: nextStart, length: 0))[0].content
            guard text.substring(with: following).contains("|") else { break }
            lineRanges.append(following)
            current = following
        }
        // The table starts at the header right above its delimiter row.
        let lines = lineRanges.map { text.substring(with: $0) }
        guard let delimiter = lines.firstIndex(where: isDelimiterRow), delimiter > 0 else { return nil }
        let start = delimiter - 1
        let tableRanges = Array(lineRanges[start...])
        let tableLines = Array(lines[start...])
        guard let table = MarkdownTable.parse(tableLines),
              let row = tableRanges.firstIndex(where: { NSLocationInRange(location, $0) || NSMaxRange($0) == location })
        else { return nil }
        let offset = location - tableRanges[row].location
        let rowText = tableLines[row] as NSString
        let before = rowText.substring(to: max(0, min(offset, rowText.length)))
        let pipes = before.filter { $0 == "|" }.count
        let leadingPipe = tableLines[row].trimmingCharacters(in: .whitespaces).hasPrefix("|")
        let column = max(0, pipes - (leadingPipe ? 1 : 0))
        // Offset from the start of the cell's content (after the pipe and leading spaces).
        let cellText = before.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let offsetInCell = (cellText.drop { $0 == " " } as Substring).utf16.count
        let range = NSRange(location: tableRanges[0].location,
                            length: NSMaxRange(tableRanges[tableRanges.count - 1]) - tableRanges[0].location)
        return Location(range: range, lines: tableLines, table: table, row: row, column: column,
                        offsetInCell: offsetInCell)
    }

    /// Reformats the table under the caret; the caret stays in the same cell.
    public static func format(in text: NSString, selection: NSRange, lineEnding: String = "\n") -> TextEdit? {
        guard let location = locate(in: text, at: selection.location) else { return nil }
        let target = Target(row: location.row, column: location.column, caretInCell: location.offsetInCell)
        return edit(location, table: location.table, target: target, lineEnding: lineEnding)
    }

    /// Tab / Shift-Tab: formats the table and moves to the next / previous cell. Tab in the last
    /// cell adds a row.
    public static func moveCell(in text: NSString, selection: NSRange, backwards: Bool,
                                lineEnding: String = "\n") -> TextEdit? {
        guard let location = locate(in: text, at: selection.location) else { return nil }
        var table = location.table
        let columns = table.columnCount
        // Positions in reading order, skipping the delimiter row (line 1).
        var row = location.row == 1 ? 2 : location.row
        var column = min(location.column, columns - 1)
        if backwards {
            column -= 1
            if column < 0 {
                row = row == 2 ? 0 : row - 1
                column = columns - 1
                if location.row == 0 { return nil }
            }
        } else {
            column += 1
            if column >= columns {
                column = 0
                row = row == 0 ? 2 : row + 1
            }
            if row - 2 >= table.rows.count {
                table.rows.append(Array(repeating: "", count: columns))
            }
        }
        return edit(location, table: table, target: Target(row: row, column: column, selectCell: true),
                    lineEnding: lineEnding)
    }

    public static func insertRow(in text: NSString, selection: NSRange, below: Bool,
                                 lineEnding: String = "\n") -> TextEdit? {
        guard let location = locate(in: text, at: selection.location) else { return nil }
        var table = location.table
        let bodyIndex = max(location.row - 2, -1)
        let insertAt = below ? bodyIndex + 1 : max(bodyIndex, 0)
        table.rows.insert(Array(repeating: "", count: table.columnCount), at: min(insertAt, table.rows.count))
        let target = Target(row: insertAt + 2, column: 0, selectCell: true)
        return edit(location, table: table, target: target, lineEnding: lineEnding)
    }

    public static func deleteRow(in text: NSString, selection: NSRange, lineEnding: String = "\n") -> TextEdit? {
        guard let location = locate(in: text, at: selection.location), location.row >= 2 else { return nil }
        var table = location.table
        table.rows.remove(at: location.row - 2)
        let row = min(location.row, table.rows.count + 1)
        let target = Target(row: row < 2 ? 0 : row, column: location.column)
        return edit(location, table: table, target: target, lineEnding: lineEnding)
    }

    public static func insertColumn(in text: NSString, selection: NSRange, right: Bool,
                                    lineEnding: String = "\n") -> TextEdit? {
        guard let location = locate(in: text, at: selection.location) else { return nil }
        var table = location.table
        let columns = table.columnCount
        let index = min(right ? location.column + 1 : location.column, columns)
        func inserting(_ row: [String]) -> [String] {
            var padded = row + Array(repeating: "", count: max(columns - row.count, 0))
            padded.insert("", at: index)
            return padded
        }
        table.header = inserting(table.header)
        table.rows = table.rows.map(inserting)
        var aligns = table.alignments + Array(repeating: .none, count: max(columns - table.alignments.count, 0))
        aligns.insert(.none, at: index)
        table.alignments = aligns
        let target = Target(row: location.row == 1 ? 0 : location.row, column: index, selectCell: true)
        return edit(location, table: table, target: target, lineEnding: lineEnding)
    }

    public static func deleteColumn(in text: NSString, selection: NSRange, lineEnding: String = "\n") -> TextEdit? {
        guard let location = locate(in: text, at: selection.location), location.table.columnCount > 1 else {
            return nil
        }
        var table = location.table
        let index = min(location.column, table.columnCount - 1)
        func removing(_ row: [String]) -> [String] {
            var copy = row
            if index < copy.count { copy.remove(at: index) }
            return copy
        }
        table.header = removing(table.header)
        table.rows = table.rows.map(removing)
        if index < table.alignments.count { table.alignments.remove(at: index) }
        let target = Target(row: location.row == 1 ? 0 : location.row, column: min(index, table.columnCount - 1))
        return edit(location, table: table, target: target, lineEnding: lineEnding)
    }

    public static func align(_ alignment: MarkdownTable.Alignment, in text: NSString, selection: NSRange,
                             lineEnding: String = "\n") -> TextEdit? {
        guard let location = locate(in: text, at: selection.location) else { return nil }
        var table = location.table
        let columns = table.columnCount
        var aligns = table.alignments + Array(repeating: .none, count: max(columns - table.alignments.count, 0))
        aligns[min(location.column, columns - 1)] = alignment
        table.alignments = aligns
        let target = Target(row: location.row, column: location.column, caretInCell: location.offsetInCell)
        return edit(location, table: table, target: target, lineEnding: lineEnding)
    }

    /// Replaces the table with the formatted `table` and puts the caret into a cell
    /// (selecting its content when `selectCell`).
    /// Where the caret goes after a table edit.
    private struct Target {
        let row: Int
        let column: Int
        var selectCell = false
        var caretInCell = 0
    }

    private static func edit(_ location: Location, table: MarkdownTable, target: Target,
                             lineEnding: String) -> TextEdit {
        let targetRow = target.row, targetColumn = target.column
        let selectCell = target.selectCell, caretInCell = target.caretInCell
        let lines = table.formatted()
        let replacement = lines.joined(separator: lineEnding)
        let row = min(max(targetRow, 0), lines.count - 1)
        var offset = lines[..<row].reduce(0) { $0 + ($1 as NSString).length + (lineEnding as NSString).length }
        let line = lines[row] as NSString
        // Cell `c` starts after the (c + 1)-th pipe plus one space.
        var pipes = 0
        var cellStart = 2
        for index in 0..<line.length where line.character(at: index) == 0x7C {
            if pipes == targetColumn { cellStart = index + 2; break }
            pipes += 1
        }
        cellStart = min(cellStart, line.length)
        var cellEnd = cellStart
        while cellEnd < line.length, line.character(at: cellEnd) != 0x7C { cellEnd += 1 }
        let content = line.substring(with: NSRange(location: cellStart, length: max(cellEnd - cellStart, 0)))
        let value = content.trimmingCharacters(in: .whitespaces)
        let trimmedLeading = value.isEmpty ? 0 : content.prefix { $0 == " " }.count
        offset += cellStart + trimmedLeading + min(caretInCell, (value as NSString).length)
        let length = selectCell ? (value as NSString).length : 0
        return TextEdit(range: location.range, replacement: replacement,
                        selection: NSRange(location: location.range.location + offset, length: length))
    }
}
