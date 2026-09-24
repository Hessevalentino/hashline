import Foundation
import Testing
@testable import HashlineCore

/// Every fixture must survive decode → encode byte for byte.
struct FixtureRoundTripTests {
    static let fixtures: [URL] = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "md" }
            .sorted { $0.path < $1.path }
    }()

    @Test func corpusIsPresent() {
        #expect(Self.fixtures.count >= 10, "Run scripts/make-fixtures.py")
    }

    @Test(arguments: fixtures)
    func roundTripsByteForByte(file: URL) throws {
        let original = try Data(contentsOf: file)
        let (text, format) = try TextFileCodec.decode(original)
        #expect(try TextFileCodec.encode(text, format: format) == original)
    }
}
