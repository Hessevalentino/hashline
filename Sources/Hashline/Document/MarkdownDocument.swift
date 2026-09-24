import AppKit
import HashlineCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

/// A `.md` file on disk. The text storage is the single source of truth;
/// the editor displays it directly, so typing never copies the whole string.
@MainActor
final class MarkdownDocument: ReferenceFileDocument {
    nonisolated static let readableContentTypes: [UTType] = [.markdown, .plainText]
    nonisolated static let writableContentTypes: [UTType] = [.markdown]

    /// Created on first use on the main actor, because reading happens off it and
    /// NSTextStorage is not Sendable. The decoded string is released afterwards.
    var textStorage: NSTextStorage {
        if let storage { return storage }
        let created = NSTextStorage(string: loadedText ?? "")
        storage = created
        loadedText = nil
        return created
    }

    // nonisolated(unsafe): mutated only on the main actor; read off it only in
    // `snapshot(contentType:)`, while NSDocument keeps the main thread blocked.
    private nonisolated(unsafe) var storage: NSTextStorage?
    private nonisolated(unsafe) var loadedText: String?
    /// Hash of the text last read from or written to disk (this process only). Tells whether the
    /// editor has unsaved changes when another application changes the file.
    nonisolated(unsafe) var diskTextHash: Int?
    private let format: TextFileFormat
    let lineEnding: LineEnding
    /// Set when the document was read from disk; consumed by the editor to log open latency.
    private(set) var openStartedAt: ContinuousClock.Instant?

    nonisolated init() {
        loadedText = nil
        format = .utf8
        lineEnding = .lf
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        let startedAt = ContinuousClock.now
        let signpostState = Performance.signposter.beginInterval("ReadFile")
        defer { Performance.signposter.endInterval("ReadFile", signpostState) }

        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoded = try TextFileCodec.decode(data)
        loadedText = decoded.text
        diskTextHash = decoded.text.hashValue
        format = decoded.format
        lineEnding = LineEnding.detect(in: decoded.text)
        openStartedAt = startedAt
    }

    /// Called on a background queue during asynchronous saves (including autosave).
    /// NSDocument blocks the main thread in `_waitForUserInteractionUnblocking` until the
    /// snapshot is taken, so reading the storage here cannot race with editing.
    /// Bridging `NSTextStorage.string` to `String` copies the mutable backing store,
    /// so the encoding and write that follow run on an independent value.
    nonisolated func snapshot(contentType: UTType) throws -> Snapshot {
        let signpostState = Performance.signposter.beginInterval("Snapshot")
        defer { Performance.signposter.endInterval("Snapshot", signpostState) }
        return Snapshot(text: storage?.string ?? loadedText ?? "", format: format, takenAt: .now)
    }

    nonisolated func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        let signpostState = Performance.signposter.beginInterval("WriteFile")
        defer { Performance.signposter.endInterval("WriteFile", signpostState) }
        let data = try TextFileCodec.encode(snapshot.text, format: snapshot.format)
        diskTextHash = snapshot.text.hashValue
        let elapsed = (ContinuousClock.now - snapshot.takenAt).milliseconds
        Performance.logger.notice(
            "Save \(data.count) bytes: snapshot to encoded in \(elapsed, format: .fixed(precision: 1)) ms"
        )
        return FileWrapper(regularFileWithContents: data)
    }

    /// Returns the open start time once, so the latency is reported only for the first editor.
    func takeOpenStartedAt() -> ContinuousClock.Instant? {
        defer { openStartedAt = nil }
        return openStartedAt
    }

    struct Snapshot: Sendable {
        let text: String
        let format: TextFileFormat
        let takenAt: ContinuousClock.Instant
    }
}
