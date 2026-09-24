import Foundation
import Testing
@testable import HashlineCore

/// Timing of the per-keystroke core path on the 1 MB fixture. Opt-in:
/// `HASHLINE_PERF=1 swift test -c release --filter PerformanceProbeTests`
struct PerformanceProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HASHLINE_PERF"] != nil))
    func keystrokeCostOn1MB() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/generated/1mb.md")
        guard let source = try? String(contentsOf: root, encoding: .utf8) else { return }
        let text = NSMutableString(string: source)
        let clock = ContinuousClock()
        var map: BlockMap?
        let parse = clock.measure { map = BlockMap(text: source) }
        guard let map else { return }
        var location = text.length / 2
        var edits: [Duration] = []
        var spans: [Duration] = []
        for _ in 0..<200 {
            text.replaceCharacters(in: NSRange(location: location, length: 0), with: "a")
            edits.append(clock.measure {
                let replaced = map.applyEdit(editedRange: NSRange(location: location, length: 1), delta: 1,
                                             replacedText: "", in: text)
                spans.append(clock.measure {
                    for index in replaced { _ = Highlighter.spans(for: map.blocks[index], in: text) }
                })
            })
            location += 1
        }
        let renderer = PreviewRenderer()
        let firstPreview = clock.measure { _ = renderer.update(for: map.blocks) }
        let nextPreview = clock.measure { _ = renderer.update(for: map.blocks) }
        let validate = clock.measure { map.validateDefinitions(in: text) }
        let sorted = edits.sorted()
        print("PERF blocks \(map.blocks.count) parse \(parse)")
        print("PERF edit p50 \(sorted[100]) p95 \(sorted[190]) max \(sorted[199]) spans p50 \(spans.sorted()[100])")
        print("PERF preview first \(firstPreview) next \(nextPreview) validate \(validate)")
    }
}

extension PerformanceProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HASHLINE_PERF"] != nil))
    func statisticsOn1MB() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/generated/1mb.md")
        let text = try String(contentsOf: url, encoding: .utf8) as NSString
        let clock = ContinuousClock()
        var statistics: TextStatistics?
        let time = clock.measure { statistics = TextStatistics.of(text) }
        print("PERF statistics 1 MB: \(time) words \(statistics?.words ?? 0)")
    }
}
