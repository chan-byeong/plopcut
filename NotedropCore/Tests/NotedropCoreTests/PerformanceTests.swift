import Foundation
import Testing
@testable import NotedropCore

/// Large-library measurements (STA-80). Skipped unless `NOTEDROP_PERF_LIBRARY` points at a folder made by
/// `scripts/generate-perf-library.py`; run them with `scripts/measure-performance.sh`.
@Suite struct PerformanceTests {
    private static let root: URL? = ProcessInfo.processInfo.environment["NOTEDROP_PERF_LIBRARY"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }

    private func milliseconds(_ label: String, _ body: () throws -> Int) rethrows -> Double {
        let clock = ContinuousClock()
        var result = 0
        let elapsed = try clock.measure { result = try body() }
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        print("PERF \(label): \(String(format: "%.1f", ms)) ms (\(result) results)")
        return ms
    }

    @Test(.enabled(if: PerformanceTests.root != nil)) func scanAndSearch() throws {
        let store = DropStore(root: Self.root!)
        var drops: [Drop] = []
        let scan = milliseconds("scan") { drops = try! store.scan().drops; return drops.count }
        #expect(drops.count >= 5000)
        #expect(scan < 5000)

        let now = Date()
        var index = SearchIndex()
        _ = milliseconds("build search index") { index = SearchIndex(drops); return drops.count }
        for (label, filter) in [
            ("search common word 'alpha'", LibraryFilter(search: "alpha")),
            ("search rare word 'drop-04999'", LibraryFilter(search: "drop-04999")),
            ("search no match 'zzzzqq'", LibraryFilter(search: "zzzzqq")),
            ("search Korean '라이브러리'", LibraryFilter(search: "라이브러리")),
            ("tag+type+search", LibraryFilter(search: "echo", type: .text, tag: "swift")),
        ] {
            _ = milliseconds(label + " (no index)") { filter.apply(drops, now: now).count }
            let ms = milliseconds(label + " (indexed)") { filter.apply(drops, now: now, index: index).count }
            #expect(ms < 100)
        }
        _ = milliseconds("group by date") { DateGroup.group(drops, now: now).count }
    }
}
