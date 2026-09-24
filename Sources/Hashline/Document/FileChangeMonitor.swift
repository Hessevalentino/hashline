import AppKit
import HashlineCore
import Observation

/// Watches the open file for changes made by other applications (vnode events). Editors that
/// save atomically replace the file, so after a rename or delete the watch is re-armed on the path.
@MainActor
final class FileChangeMonitor {
    private let url: URL
    private let onChange: @MainActor () -> Void
    // Created and cancelled on the main actor; deinit only cancels (thread-safe).
    nonisolated(unsafe) private var source: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    deinit {
        source?.cancel()
    }

    private func arm() {
        source?.cancel()
        source = nil
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .extend, .delete, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self, weak source] in
            let events = source?.data ?? []
            MainActor.assumeIsolated { self?.handle(events) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func handle(_ events: DispatchSource.FileSystemEvent) {
        pending?.cancel()
        pending = Task { [weak self] in
            // Coalesce the burst of events of one save; give atomic replacements time to finish.
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            if events.contains(.delete) || events.contains(.rename) { self.arm() }
            self.onChange()
        }
    }
}

/// A version of the file on disk that differs from the edited text.
@MainActor
@Observable
final class DiskConflict {
    private(set) var diskText: String?
    @ObservationIgnored private(set) var diskDate: Date?

    func set(_ text: String?, date: Date?) {
        diskText = text
        diskDate = date
    }
}

extension EditorSession {
    /// Compares the file on disk with the editor. Without unsaved changes the editor follows the
    /// disk silently; with them a banner offers Reload / Keep Mine. (NSDocument's edited state is
    /// not reliable here: SwiftUI documents often report false right after typing.)
    func checkDiskVersion() {
        guard let url = documentURL else { return }
        let date = (try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        // Our own saves (and autosaves) leave NSDocument with the file's date: nothing to compare.
        if let date, date == nsDocument?.fileModificationDate, conflict.diskText == nil { return }
        guard let data = try? Data(contentsOf: url), let decoded = try? TextFileCodec.decode(data) else { return }
        let edited = document.textStorage.string
        guard decoded.text != edited else {
            conflict.set(nil, date: nil)
            document.diskTextHash = edited.hashValue
            nsDocument?.fileModificationDate = date
            return
        }
        if edited.hashValue != document.diskTextHash {
            conflict.set(decoded.text, date: date)
            Performance.logger.notice("File changed on disk while edited")
        } else {
            reload(decoded.text, date: date)
        }
    }

    func reloadFromDisk() {
        guard let text = conflict.diskText else { return }
        reload(text, date: conflict.diskDate)
    }

    /// Keeps the edited text; the next save overwrites the disk version without asking again.
    func keepEditedVersion() {
        nsDocument?.fileModificationDate = conflict.diskDate
        document.diskTextHash = conflict.diskText?.hashValue
        conflict.set(nil, date: nil)
    }

    /// The window's NSDocument (SwiftUI creates it; looking it up by URL can miss symlinked paths).
    private var nsDocument: NSDocument? {
        textView?.window?.windowController?.document as? NSDocument
            ?? documentURL.flatMap { NSDocumentController.shared.document(for: $0) }
    }

    private func reload(_ text: String, date: Date?) {
        let storage = document.textStorage
        let selection = textView?.selectedRange() ?? NSRange(location: 0, length: 0)
        let undoManager = textView?.undoManager
        undoManager?.disableUndoRegistration()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        undoManager?.enableUndoRegistration()
        // The old undo steps refer to text that no longer exists.
        undoManager?.removeAllActions()
        let location = min(selection.location, storage.length)
        textView?.setSelectedRange(NSRange(location: location, length: 0))
        document.diskTextHash = text.hashValue
        nsDocument?.fileModificationDate = date
        nsDocument?.updateChangeCount(.changeCleared)
        conflict.set(nil, date: nil)
        Performance.logger.notice("Reloaded \(text.utf16.count) characters changed on disk")
    }
}
