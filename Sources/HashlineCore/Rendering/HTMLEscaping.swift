import Foundation

func escape(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.utf8.count)
    for character in text {
        switch character {
        case "&": result += "&amp;"
        case "<": result += "&lt;"
        case ">": result += "&gt;"
        case "\"": result += "&quot;"
        default: result.append(character)
        }
    }
    return result
}

/// Percent-encodes URL characters like cmark's `houdini_escape_href`.
func escapeHref(_ url: String) -> String {
    var result = ""
    for byte in url.utf8 {
        switch byte {
        case UInt8(ascii: "&"): result += "&amp;"
        case UInt8(ascii: "'"): result += "&#x27;"
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"):
            result.unicodeScalars.append(UnicodeScalar(byte))
        default:
            if "-_.+!*(),%#@?=;:/,$~".utf8.contains(byte) {
                result.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
    }
    return result
}
