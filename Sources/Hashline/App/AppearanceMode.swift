import AppKit
import SwiftUI

/// Light or dark look for the whole app (editor, preview, themes follow), or the system's.
enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    static let key = "appearanceMode"

    static var current: AppearanceMode {
        UserDefaults.standard.string(forKey: key).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    var title: LocalizedStringResource {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Applies the stored mode; `nil` appearance lets windows follow System Settings.
    @MainActor
    static func apply() {
        let appearance: NSAppearance? = switch current {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if NSApp.appearance != appearance { NSApp.appearance = appearance }
    }

    /// The toolbar switch: dark on, light off. Flipping it pins the choice (no longer “system”).
    @MainActor
    static func set(dark: Bool) {
        UserDefaults.standard.set((dark ? AppearanceMode.dark : .light).rawValue, forKey: key)
        apply()
    }

    @MainActor
    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

/// ☀︎ [switch] ☾ in the toolbar. Follows the effective appearance, so it also moves when the
/// system switches while the mode is “Match System”.
@MainActor
final class AppearanceSwitchView: NSStackView {
    private let toggle = NSSwitch()
    private var observation: NSKeyValueObservation?

    init() {
        super.init(frame: .zero)
        let sun = NSImageView(image: NSImage(systemSymbolName: "sun.max.fill",
                                             accessibilityDescription: String(localized: "Light")) ?? NSImage())
        let moon = NSImageView(image: NSImage(systemSymbolName: "moon.fill",
                                              accessibilityDescription: String(localized: "Dark")) ?? NSImage())
        for icon in [sun, moon] {
            icon.contentTintColor = .secondaryLabelColor
            icon.setAccessibilityElement(false)
        }
        toggle.controlSize = .mini
        toggle.target = self
        toggle.action = #selector(toggled(_:))
        toggle.setAccessibilityLabel(String(localized: "Dark mode"))
        toggle.toolTip = String(localized: "Light or dark appearance")
        setViews([sun, toggle, moon], in: .center)
        spacing = 4
        orientation = .horizontal
        alignment = .centerY
        update()
        observation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func update() {
        toggle.state = AppearanceMode.isDark ? .on : .off
    }

    @objc private func toggled(_ sender: NSSwitch) {
        AppearanceMode.set(dark: sender.state == .on)
    }
}
