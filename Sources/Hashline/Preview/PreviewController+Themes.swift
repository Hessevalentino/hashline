import AppKit
import HashlineCore
import WebKit

/// The page's themes and Content Security Policy, and reloading it when they change.
extension PreviewController {
    func themedPage() -> String {
        let store = ThemeStore.shared
        let light = store.theme(dark: false), dark = store.theme(dark: true)
        appliedThemes = "\(light.id)|\(dark.id)|\(store.revision)"
        appliedRemoteImages = ImageSettings.loadsRemoteImages
        return Self.page(light: light.css, dark: dark.css, remoteImages: appliedRemoteImages)
    }

    /// Swaps the theme CSS in the loaded page (Settings ▸ Appearance, edited theme files).
    func updateThemeStyles() {
        let store = ThemeStore.shared
        let light = store.theme(dark: false), dark = store.theme(dark: true)
        let key = "\(light.id)|\(dark.id)|\(store.revision)"
        guard key != appliedThemes, let webView else { return }
        appliedThemes = key
        webView.callAsyncJavaScript(Self.themeScript, arguments: ["light": light.css, "dark": dark.css], in: nil,
                                    in: .defaultClient, completionHandler: nil)
    }

    /// A new page (new CSP or newly readable images); the current blocks render again once it loaded.
    func reloadPage() {
        guard let webView else { return }
        isLoaded = false
        if pendingBlocks == nil, !latestBlocks.isEmpty { pendingBlocks = latestBlocks }
        webView.loadHTMLString(themedPage(), baseURL: nil)
    }
}
