import Foundation
import Testing

@testable import NotedropCore

@Suite struct EventLogTests {
    private func makeLog(maxBytes: Int = 1_000_000) -> (FileEventLog, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notedrop-log-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("Logs/notedrop.log")
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        return (FileEventLog(url: url, maxBytes: maxBytes, now: { fixed }), dir)
    }

    @Test func appendsTimestampedLinesAndCreatesFolder() throws {
        let (log, dir) = makeLog()
        defer { try? FileManager.default.removeItem(at: dir) }
        log.log(.appStart(version: "1.2.0", build: "45", macOS: "15.1"))
        log.log(.error(code: "storage_unreadable"))
        log.log(.permission(item: "accessibility", status: "missing"))
        let lines = try String(contentsOf: log.url, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0] == "2023-11-14T22:13:20Z app_start version=1.2.0 build=45 macos=15.1")
        #expect(lines[1].hasSuffix(" error code=storage_unreadable"))
        #expect(lines[2].hasSuffix(" permission item=accessibility status=missing"))
    }

    @Test func rotatesKeepingOnePreviousFile() throws {
        let (log, dir) = makeLog(maxBytes: 200)
        defer { try? FileManager.default.removeItem(at: dir) }
        for _ in 0..<40 { log.log(.error(code: "save_failed")) }
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: log.previousURL.path))
        #expect(!fm.fileExists(atPath: log.url.appendingPathExtension("2").path))
        let current = try fm.attributesOfItem(atPath: log.url.path)[.size] as? Int ?? 0
        let previous = try fm.attributesOfItem(atPath: log.previousURL.path)[.size] as? Int ?? 0
        #expect(current > 0 && current < 400)
        #expect(previous > 0 && previous < 400)
    }

    @Test func failureToWriteIsSilent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notedrop-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // A regular file where the log folder should be: the folder cannot be created.
        let blocker = dir.appendingPathComponent("Logs")
        try Data("x".utf8).write(to: blocker)
        FileEventLog(url: blocker.appendingPathComponent("notedrop.log")).log(.error(code: "save_failed"))
        // The log path itself is a directory: it cannot be opened for writing.
        let asDirectory = dir.appendingPathComponent("dir.log")
        try FileManager.default.createDirectory(at: asDirectory, withIntermediateDirectories: true)
        FileEventLog(url: asDirectory).log(.error(code: "save_failed"))
    }

    @Test func concurrentWritesKeepEveryLineWhole() throws {
        let (log, dir) = makeLog()
        defer { try? FileManager.default.removeItem(at: dir) }
        DispatchQueue.concurrentPerform(iterations: 50) { _ in log.log(.error(code: "save_failed")) }
        let lines = try String(contentsOf: log.url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 50)
        #expect(lines.allSatisfy { $0.hasSuffix(" error code=save_failed") })
    }

    @Test func errorIsLoggedByCodeOnly() throws {
        let (log, dir) = makeLog()
        defer { try? FileManager.default.removeItem(at: dir) }
        let secret = "/Users/alice/Documents/Notedrop/My Diary https://example.com/secret #tag"
        log.log(error: NotedropError("storage_unreadable", detail: secret))
        // Foreign errors and codes that are not a plain token never reach the log either.
        log.log(error: NSError(domain: secret, code: 1, userInfo: [NSLocalizedDescriptionKey: secret]))
        log.log(error: NotedropError(secret))
        let text = try String(contentsOf: log.url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines[0].hasSuffix(" error code=storage_unreadable"))
        #expect(lines[1].hasSuffix(" error code=unknown"))
        #expect(lines[2].hasSuffix(" error code=invalid"))
        for word in ["alice", "Diary", "example", "secret", "#tag", "/Users"] {
            #expect(!text.contains(word), "\(word) leaked into the log")
        }
    }
}
