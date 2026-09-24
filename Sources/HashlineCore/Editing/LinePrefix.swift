import Foundation

/// The Markdown prefix of a line: indentation, blockquote markers and a list or heading marker.
struct LinePrefix: Equatable {
    enum Marker: Equatable {
        case none
        case heading(Int)
        case bullet(Character)
        case ordered(Int, Character)
        case task(checked: Bool)
    }

    /// Leading spaces or tabs.
    var indent: String
    /// `> ` markers, possibly nested.
    var quote: String
    var marker: Marker
    /// Length of the whole prefix (indent + quote + marker + following space), UTF-16.
    var length: Int

    static func parse(_ line: String) -> LinePrefix {
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
        let indent = String(characters[0..<index])

        var quoteEnd = index
        var scan = index
        while scan < characters.count, characters[scan] == ">" {
            scan += 1
            if scan < characters.count, characters[scan] == " " { scan += 1 }
            quoteEnd = scan
        }
        let quote = String(characters[index..<quoteEnd])
        index = quoteEnd

        var marker = Marker.none
        var markerEnd = index
        if index < characters.count {
            let rest = String(characters[index...])
            if let level = headingLevel(rest), quote.isEmpty {
                marker = .heading(level)
                markerEnd = min(index + level + 1, characters.count)
            } else if "-*+".contains(characters[index]), index + 1 < characters.count, characters[index + 1] == " " {
                let bullet = characters[index]
                let content = Array(characters[(index + 2)...])
                let box = String(content.prefix(3)).lowercased()
                if (box == "[ ]" || box == "[x]") && (content.count == 3 || content[3] == " ") {
                    marker = .task(checked: box == "[x]")
                    markerEnd = index + 2 + min(content.count, 4)
                } else {
                    marker = .bullet(bullet)
                    markerEnd = index + 2
                }
            } else {
                var digitsEnd = index
                while digitsEnd < characters.count, digitsEnd - index < 9, characters[digitsEnd].isASCII,
                      characters[digitsEnd].isNumber { digitsEnd += 1 }
                if digitsEnd > index, digitsEnd < characters.count, ".)".contains(characters[digitsEnd]),
                   digitsEnd + 1 == characters.count || characters[digitsEnd + 1] == " ",
                   let number = Int(String(characters[index..<digitsEnd])) {
                    marker = .ordered(number, characters[digitsEnd])
                    markerEnd = min(digitsEnd + 2, characters.count)
                }
            }
        }
        let prefix = String(characters[0..<markerEnd])
        return LinePrefix(indent: indent, quote: quote, marker: marker, length: (prefix as NSString).length)
    }

    private static func headingLevel(_ text: String) -> Int? {
        var level = 0
        for character in text {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let after = text.dropFirst(level).first
        return after == nil || after == " " ? level : nil
    }

    var isListItem: Bool {
        switch marker {
        case .bullet, .ordered, .task: true
        default: false
        }
    }

    /// Marker text for the next list item (Return continues the list).
    var continuation: String? {
        switch marker {
        case .bullet(let character): "\(character) "
        case .ordered(let number, let delimiter): "\(number + 1)\(delimiter) "
        case .task: "- [ ] "
        case .none: quote.isEmpty ? nil : ""
        case .heading: nil
        }
    }

    /// Width to indent a nested item so it lines up with this item's content.
    var nestingWidth: Int {
        switch marker {
        case .ordered(let number, _): String(number).count + 2
        default: 2
        }
    }
}
