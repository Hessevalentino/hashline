import AppKit
import Observation
import Sparkle

/// Sparkle updates from the GitHub appcast, checked weekly (ADR 0018). Sparkle asks on the second
/// launch whether to check automatically; nothing is sent before that. Development and test builds
/// never check: they would try to replace themselves with a release.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    private(set) var canCheckForUpdates = false
    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var observation: NSKeyValueObservation?

    static var isEnabled: Bool {
        #if DEBUG || HASHLINE_TEST_HOOKS
        false
        #else
        true
        #endif
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func start() {
        guard Self.isEnabled else { return }
        controller.startUpdater()
        observation = controller.updater.observe(\.canCheckForUpdates,
                                                 options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            MainActor.assumeIsolated { self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        guard Self.isEnabled else { return }
        controller.checkForUpdates(nil)
    }
}
