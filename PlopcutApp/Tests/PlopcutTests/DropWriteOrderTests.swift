import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

/// Holds the first save that asks for the time, after it has read drop.json and before it writes it back,
/// so a test can start another write of the same drop in that window.
final class HeldClock: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var calls = 0
    private var entered = false

    func now() -> Date {
        let isFirst = lock.withLock {
            calls += 1
            if calls == 1 { entered = true }
            return calls == 1
        }
        if isFirst { gate.wait() }
        return Date()
    }

    func release() { gate.signal() }

    /// Waits until the held save is parked inside the clock.
    func waitUntilHeld() async {
        while true {
            if lock.withLock({ entered }) { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// Every write of a drop goes through one queue, so pin, format, autosave and content saves never overwrite one another
/// in drop.json and reach the list in the order they were written (PLO-100 review).
@MainActor
@Suite struct DropWriteOrderTests {
    private static let textID = "2026-01-01_090000_000000001_example-app"

    private func copyStorage() throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/swift-migration/fixtures/storage")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }

    private func meta(_ root: URL) throws -> [String: Any] {
        let url = root.appendingPathComponent("drops/\(Self.textID)/drop.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }

    /// Starts a note autosave that stops inside the store, runs `other` meanwhile, then lets the autosave finish.
    private func interleave(
        _ other: @escaping @MainActor (LibraryModel) async -> Void
    ) async throws -> (LibraryModel, URL) {
        let root = try copyStorage()
        let clock = HeldClock()
        let model = LibraryModel(storageRoot: { root }, clock: { clock.now() }, openURL: { _ in })
        await model.reload()
        model.selectedID = Self.textID
        model.editor.setNote("typed note")
        let autosave = Task { await model.editor.flush() }
        await clock.waitUntilHeld()
        let second = Task { await other(model) }
        // Without the queue the second write finishes here, before the autosave writes its stale copy back.
        try await Task.sleep(for: .milliseconds(150))
        clock.release()
        await autosave.value
        await second.value
        return (model, root)
    }

    @Test func aPinDuringAnAutosaveKeepsBoth() async throws {
        let (model, root) = try await interleave { await $0.togglePin(id: Self.textID) }
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = try meta(root)
        #expect(saved["pinnedAt"] is String)
        let note = try String(contentsOf: root.appendingPathComponent("drops/\(Self.textID)/note.md"), encoding: .utf8)
        #expect(note == "typed note")
        let drop = try #require(model.drops.first { $0.id == Self.textID })
        #expect(drop.isPinned && drop.note == "typed note")
    }

    @Test func aFormatChangeDuringAnAutosaveKeepsBoth() async throws {
        let (model, root) = try await interleave { await $0.setFormat(.set(.markdown, codeLanguage: nil), for: Self.textID) }
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try meta(root)["format"] as? String == "markdown")
        let drop = try #require(model.drops.first { $0.id == Self.textID })
        #expect(drop.format == .markdown && drop.note == "typed note")
    }

    // Two quick toggles: the second sees the first one's result, so the drop ends where it started.
    @Test func twoQuickTogglesEndUnpinned() async throws {
        let root = try copyStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(storageRoot: { root }, openURL: { _ in })
        await model.reload()
        let first = Task { await model.togglePin(id: Self.textID) }
        let second = Task { await model.togglePin(id: Self.textID) }
        await first.value
        await second.value
        #expect(model.drops.first { $0.id == Self.textID }?.isPinned == false)
        #expect(try meta(root)["pinnedAt"] is NSNull)
    }
}
