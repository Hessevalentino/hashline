import HashlineCore
import UniformTypeIdentifiers
import WebKit

/// Serves `hashline-asset:///path` to the preview from folders the app may read. Files outside
/// them are refused and reported, so the preview can offer to grant access to that folder.
@MainActor
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    /// A local image could not be shown: its folder is not accessible.
    var onBlockedFolder: ((URL) -> Void)?
    private var stoppedTasks: Set<ObjectIdentifier> = []

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let path = ImageLinks.filePath(fromAssetURL: url) else {
            return fail(task, status: 400)
        }
        let file = URL(fileURLWithPath: path)
        // Images only: the preview has no use for anything else, and nothing else should leak into it.
        guard ImageLinks.isServableImage(file) else { return fail(task, status: 415) }
        guard FolderAccess.shared.canAccess(file) else {
            onBlockedFolder?(file.deletingLastPathComponent())
            return fail(task, status: 403)
        }
        let taskID = ObjectIdentifier(task)
        Task { @MainActor [weak self] in
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: file, options: .mappedIfSafe)
            }.value
            guard let self, !self.stoppedTasks.contains(taskID) else { return }
            guard let data else { return self.fail(task, status: 404) }
            let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": type, "Content-Length": "\(data.count)"])
            if let response { task.didReceive(response) }
            task.didReceive(data)
            task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        stoppedTasks.insert(ObjectIdentifier(task))
    }

    private func fail(_ task: any WKURLSchemeTask, status: Int) {
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
        else { return }
        task.didReceive(response)
        task.didFinish()
    }
}
