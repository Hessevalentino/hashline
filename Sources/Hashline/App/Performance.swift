import CoreFoundation
import Darwin
import os

/// Signpost intervals and one-off timing logs for the performance budget.
/// View in Instruments (Points of Interest) or `log stream --predicate 'subsystem == "cz.hashline.Hashline"'`.
enum Performance {
    static let subsystem = "cz.hashline.Hashline"
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
    static let logger = Logger(subsystem: subsystem, category: "performance")

    /// Wall-clock time since the kernel started this process, in milliseconds.
    /// Covers dyld and static initialisation, which a signpost in `App.init` would miss.
    static func millisecondsSinceProcessStart() -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        var now = timeval()
        gettimeofday(&now, nil)
        let seconds = Double(now.tv_sec - start.tv_sec) + Double(now.tv_usec - start.tv_usec) / 1_000_000
        return seconds * 1000
    }
}

/// Measures cold start: process start → first editable text view on screen.
@MainActor
enum LaunchMetrics {
    private static var launchState: OSSignpostIntervalState?
    private static var hasReported = false

    static func begin() {
        launchState = Performance.signposter.beginInterval("Launch")
    }

    static func editorBecameEditable() {
        guard !hasReported else { return }
        hasReported = true
        if let launchState {
            Performance.signposter.endInterval("Launch", launchState)
        }
        if let elapsed = Performance.millisecondsSinceProcessStart() {
            Performance.logger.notice("Cold start to editable window: \(elapsed, format: .fixed(precision: 1)) ms")
        }
    }
}

/// Keypress → frame committed. Ends in a run loop observer that fires after
/// AppKit's Core Animation commit, so text processing, layout and drawing are included;
/// compositor latency (up to one display refresh) is not.
@MainActor
enum TypingLatency {
    struct Keystroke {
        let startedAt: ContinuousClock.Instant
        let signpost: OSSignpostIntervalState
    }

    private static var samples: [Double] = []
    /// Time spent in the highlighter per keystroke, reported next to the total.
    static var highlightSamples: [Double] = []
    /// Synchronous keystroke handling (keyDown until it returns): CPU work, without waiting for
    /// the next display refresh.
    static var processingSamples: [Double] = []
    private static let reportEvery = 100

    static func begin() -> Keystroke {
        Keystroke(startedAt: .now, signpost: Performance.signposter.beginInterval("Keystroke"))
    }

    static func endAfterFrameCommit(_ keystroke: Keystroke) {
        let observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max
        ) { _, _ in
            MainActor.assumeIsolated { record(keystroke) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func record(_ keystroke: Keystroke) {
        Performance.signposter.endInterval("Keystroke", keystroke.signpost)
        samples.append((ContinuousClock.now - keystroke.startedAt).milliseconds)
        guard samples.count >= reportEvery else { return }
        let sorted = samples.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let max = sorted[sorted.count - 1]
        Performance.logger.notice("""
            Typing latency n=\(sorted.count): p50 \(p50, format: .fixed(precision: 2)) ms, \
            p95 \(p95, format: .fixed(precision: 2)) ms, max \(max, format: .fixed(precision: 2)) ms
            """)
        if !processingSamples.isEmpty {
            let processing = processingSamples.sorted()
            let median = processing[processing.count / 2]
            let p95 = processing[Int(Double(processing.count - 1) * 0.95)]
            Performance.logger.notice("""
                Keystroke processing n=\(processing.count): p50 \(median, format: .fixed(precision: 2)) ms, \
                p95 \(p95, format: .fixed(precision: 2)) ms
                """)
            processingSamples.removeAll(keepingCapacity: true)
        }
        if !highlightSamples.isEmpty {
            let highlight = highlightSamples.sorted()
            let median = highlight[highlight.count / 2]
            let longest = highlight[highlight.count - 1]
            Performance.logger.notice("""
                Highlight per edit n=\(highlight.count): p50 \(median, format: .fixed(precision: 2)) ms, \
                max \(longest, format: .fixed(precision: 2)) ms
                """)
            highlightSamples.removeAll(keepingCapacity: true)
        }
        samples.removeAll(keepingCapacity: true)
    }
}

extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}
