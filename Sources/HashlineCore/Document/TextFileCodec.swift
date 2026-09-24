import Foundation

/// How a text file is stored on disk, so it can be written back byte-compatible.
public struct TextFileFormat: Equatable, Sendable {
    public var encoding: String.Encoding
    public var hasByteOrderMark: Bool

    public init(encoding: String.Encoding, hasByteOrderMark: Bool) {
        self.encoding = encoding
        self.hasByteOrderMark = hasByteOrderMark
    }

    public static let utf8 = TextFileFormat(encoding: .utf8, hasByteOrderMark: false)
}

/// Converts between file bytes and editor text without touching the content
/// (line endings and trailing whitespace are preserved as-is).
public enum TextFileCodec {
    public enum CodecError: Error, Equatable {
        case undecodable
        case unencodable(String.Encoding)
    }

    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LEBOM: [UInt8] = [0xFF, 0xFE]
    private static let utf16BEBOM: [UInt8] = [0xFE, 0xFF]

    /// Legacy encodings tried when the file is not valid UTF-8, in order.
    private static let legacyEncodings: [String.Encoding] = [.windowsCP1250, .isoLatin2, .windowsCP1252]

    public static func decode(_ data: Data) throws -> (text: String, format: TextFileFormat) {
        if data.starts(with: utf8BOM) {
            guard let text = String(data: data.dropFirst(utf8BOM.count), encoding: .utf8) else {
                throw CodecError.undecodable
            }
            return (text, TextFileFormat(encoding: .utf8, hasByteOrderMark: true))
        }
        for (bom, encoding) in [(utf16LEBOM, String.Encoding.utf16LittleEndian), (utf16BEBOM, .utf16BigEndian)]
        where data.starts(with: bom) {
            guard let text = String(data: data.dropFirst(bom.count), encoding: encoding) else {
                throw CodecError.undecodable
            }
            return (text, TextFileFormat(encoding: encoding, hasByteOrderMark: true))
        }
        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }
        for encoding in legacyEncodings {
            if let text = String(data: data, encoding: encoding) {
                return (text, TextFileFormat(encoding: encoding, hasByteOrderMark: false))
            }
        }
        throw CodecError.undecodable
    }

    public static func encode(_ text: String, format: TextFileFormat) throws -> Data {
        guard let body = text.data(using: format.encoding, allowLossyConversion: false) else {
            throw CodecError.unencodable(format.encoding)
        }
        guard format.hasByteOrderMark else { return body }
        let bom: [UInt8] = switch format.encoding {
        case .utf16LittleEndian: utf16LEBOM
        case .utf16BigEndian: utf16BEBOM
        case .utf8: utf8BOM
        default: []
        }
        return Data(bom) + body
    }
}
