import AppKit
import HashlineCore
import Observation

extension Notification.Name {
    /// A theme, the theme choice or the editor font changed; editors and previews restyle.
    static let hashlineThemeChanged = Notification.Name("HashlineThemeChanged")
}

/// Theme and font settings (Settings ▸ Appearance).
enum AppearanceSettings {
    static let lightThemeKey = "lightTheme"
    static let darkThemeKey = "darkTheme"
    static let fontNameKey = "editorFontName"
    static let fontSizeKey = "editorFontSize"
    static let lineHeightKey = "editorLineHeight"
    static let defaultLight = "Paper"
    static let defaultDark = "Tomorrow Night"
    static let defaultFontSize = 14.0
    static let defaultLineHeight = 1.25

    static var fontName: String { UserDefaults.standard.string(forKey: fontNameKey) ?? "" }
    static var fontSize: Double {
        let value = UserDefaults.standard.double(forKey: fontSizeKey)
        return value > 0 ? min(max(value, 9), 36) : defaultFontSize
    }
    static var lineHeight: Double {
        let value = UserDefaults.standard.double(forKey: lineHeightKey)
        return value > 0 ? min(max(value, 1), 2.5) : defaultLineHeight
    }
}

/// Built-in themes (in the app) and the user's (Application Support/Hashline/Themes), one
/// `<Name>.hashlinetheme` folder each with `theme.json` and `theme.css`. The user's folder is
/// watched: saving a theme file restyles open windows without a restart.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    struct Theme: Identifiable, Equatable {
        let id: String
        let definition: ThemeDefinition
        let css: String
        let isBuiltIn: Bool
        let folder: URL

        var isDark: Bool { definition.appearance == .dark }
    }

    private(set) var themes: [Theme] = []
    /// Problems in user themes, shown in Settings (a broken file must not go unnoticed).
    private(set) var problems: [String] = []
    /// Changes whenever themes are reloaded; part of the editor theme cache key.
    private(set) var revision = 0

    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var editorThemes: [String: EditorTheme] = [:]
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var appliedSettings = ""

    let userFolder: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Hashline/Themes", isDirectory: true)
    }()

    private init() {
        reload()
        if FileManager.default.fileExists(atPath: userFolder.path) { watchUserFolder() }
        appliedSettings = settingsKey
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsMayHaveChanged() }
        }
    }

    // MARK: Choice

    func theme(dark: Bool) -> Theme {
        let key = dark ? AppearanceSettings.darkThemeKey : AppearanceSettings.lightThemeKey
        let chosen = UserDefaults.standard.string(forKey: key)
            ?? (dark ? AppearanceSettings.defaultDark : AppearanceSettings.defaultLight)
        return themes.first { $0.id == chosen && $0.isDark == dark }
            ?? themes.first { $0.id == (dark ? AppearanceSettings.defaultDark : AppearanceSettings.defaultLight) }
            ?? themes.first { $0.isDark == dark }
            ?? themes[0]
    }

    func theme(for appearance: NSAppearance) -> Theme {
        theme(dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    /// The resolved editor theme, cached per theme, font and revision (identity tells editors
    /// whether anything changed).
    func editorTheme(for appearance: NSAppearance) -> EditorTheme {
        let theme = theme(for: appearance)
        let key = "\(theme.id)|\(AppearanceSettings.fontName)|\(AppearanceSettings.fontSize)|"
            + "\(AppearanceSettings.lineHeight)|\(revision)"
        if let cached = editorThemes[key] { return cached }
        let editorTheme = EditorTheme(definition: theme.definition, fontName: AppearanceSettings.fontName,
                                      fontSize: AppearanceSettings.fontSize,
                                      lineHeight: AppearanceSettings.lineHeight)
        editorThemes[key] = editorTheme
        return editorTheme
    }

    /// Theme ids, fonts: what editors and previews depend on.
    private var settingsKey: String {
        let defaults = UserDefaults.standard
        return [AppearanceSettings.lightThemeKey, AppearanceSettings.darkThemeKey, AppearanceSettings.fontNameKey,
                AppearanceSettings.fontSizeKey, AppearanceSettings.lineHeightKey]
            .map { defaults.object(forKey: $0).map { "\($0)" } ?? "" }
            .joined(separator: "|")
    }

    private func settingsMayHaveChanged() {
        AppearanceMode.apply()
        let key = settingsKey
        guard key != appliedSettings else { return }
        appliedSettings = key
        NotificationCenter.default.post(name: .hashlineThemeChanged, object: nil)
    }

    // MARK: Loading

    func reload() {
        let signpost = Performance.signposter.beginInterval("LoadThemes")
        defer { Performance.signposter.endInterval("LoadThemes", signpost) }
        var loaded: [Theme] = []
        var problems: [String] = []
        if let builtIn = Bundle.main.url(forResource: "Themes", withExtension: nil) {
            loaded += Self.themes(in: builtIn, builtIn: true, problems: &problems)
        }
        let user = Self.themes(in: userFolder, builtIn: false, problems: &problems)
        // A user theme with a built-in name replaces it (an edited copy).
        loaded.removeAll { theme in user.contains { $0.id == theme.id } }
        loaded += user
        if loaded.isEmpty {
            Performance.logger.fault("No themes in the bundle")
            loaded = [Self.fallback]
        }
        themes = loaded.sorted { ($0.isDark ? 1 : 0, $0.id) < ($1.isDark ? 1 : 0, $1.id) }
        self.problems = problems
        revision += 1
        editorThemes = [:]
    }

    private static func themes(in folder: URL, builtIn: Bool, problems: inout [String]) -> [Theme] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return entries.filter { $0.pathExtension == "hashlinetheme" }.compactMap { url in
            let id = url.deletingPathExtension().lastPathComponent
            do {
                let data = try Data(contentsOf: url.appendingPathComponent("theme.json"))
                let definition = try ThemeDefinition.decode(data)
                let css = (try? String(contentsOf: url.appendingPathComponent("theme.css"), encoding: .utf8)) ?? ""
                return Theme(id: id, definition: definition, css: css, isBuiltIn: builtIn, folder: url)
            } catch {
                problems.append("\(id): \(error)")
                return nil
            }
        }
    }

    private static let fallback = Theme(
        id: "Plain",
        definition: ThemeDefinition(name: "Plain", appearance: .light,
                                    editor: .init(background: "#ffffff", foreground: "#000000", tokens: [:]),
                                    code: [:]),
        css: "", isBuiltIn: true, folder: URL(fileURLWithPath: "/"))

    // MARK: User folder

    private func watchUserFolder() {
        guard watcher == nil else { return }
        watcher = FolderWatcher(url: userFolder) { [weak self] in
            guard let self else { return }
            self.reload()
            NotificationCenter.default.post(name: .hashlineThemeChanged, object: nil)
        }
    }

    /// Copies `theme` into the user folder under a new name, to edit, and shows it in Finder.
    func duplicate(_ theme: Theme) {
        do {
            try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
            var name = theme.id + " Copy"
            var number = 2
            func exists(_ name: String) -> Bool {
                FileManager.default.fileExists(atPath: userFolder.appendingPathComponent(name + ".hashlinetheme").path)
            }
            while exists(name) {
                name = theme.id + " Copy \(number)"
                number += 1
            }
            let target = userFolder.appendingPathComponent(name + ".hashlinetheme", isDirectory: true)
            try FileManager.default.copyItem(at: theme.folder, to: target)
            var definition = theme.definition
            definition.name = name
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(definition).write(to: target.appendingPathComponent("theme.json"))
            watchUserFolder()
            reload()
            let key = theme.isDark ? AppearanceSettings.darkThemeKey : AppearanceSettings.lightThemeKey
            UserDefaults.standard.set(name, forKey: key)
            NSWorkspace.shared.activateFileViewerSelecting([target.appendingPathComponent("theme.json")])
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func revealUserFolder() {
        try? FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        watchUserFolder()
        NSWorkspace.shared.activateFileViewerSelecting([userFolder])
    }
}
