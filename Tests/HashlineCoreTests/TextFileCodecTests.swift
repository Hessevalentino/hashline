import Foundation
import Testing
@testable import HashlineCore

struct TextFileCodecTests {
    @Test func decodesPlainUTF8() throws {
        let (text, format) = try TextFileCodec.decode(Data("# Příliš žluťoučký kůň".utf8))
        #expect(text == "# Příliš žluťoučký kůň")
        #expect(format == .utf8)
    }

    @Test func preservesLineEndingsOnRoundTrip() throws {
        let original = Data("a\r\nb\nc\r".utf8)
        let (text, format) = try TextFileCodec.decode(original)
        #expect(try TextFileCodec.encode(text, format: format) == original)
    }

    @Test func stripsAndRestoresUTF8BOM() throws {
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8)
        let (text, format) = try TextFileCodec.decode(original)
        #expect(text == "hello")
        #expect(format.hasByteOrderMark)
        #expect(try TextFileCodec.encode(text, format: format) == original)
    }

    @Test func roundTripsUTF16LittleEndian() throws {
        let original = Data([0xFF, 0xFE]) + (try #require("ahoj".data(using: .utf16LittleEndian)))
        let (text, format) = try TextFileCodec.decode(original)
        #expect(text == "ahoj")
        #expect(format.encoding == .utf16LittleEndian)
        #expect(try TextFileCodec.encode(text, format: format) == original)
    }

    @Test func fallsBackToWindows1250ForLegacyCzechFiles() throws {
        let original = try #require("Příliš žluťoučký kůň".data(using: .windowsCP1250))
        let (text, format) = try TextFileCodec.decode(original)
        #expect(text == "Příliš žluťoučký kůň")
        #expect(format.encoding == .windowsCP1250)
    }

    @Test func refusesLossyEncoding() {
        let format = TextFileFormat(encoding: .windowsCP1250, hasByteOrderMark: false)
        #expect(throws: TextFileCodec.CodecError.unencodable(.windowsCP1250)) {
            try TextFileCodec.encode("emoji 🙂", format: format)
        }
    }
}
