import Foundation
@testable import PlopcutCore

enum Fixtures {
    /// docs/swift-migration/fixtures, located relative to this source file.
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/swift-migration/fixtures")

    /// Copies the storage fixtures into a fresh temp directory and returns it.
    static func copyStorage() throws -> URL {
        let dest = try tempDir()
        try FileManager.default.copyItem(
            at: root.appendingPathComponent("storage/drops"),
            to: dest.appendingPathComponent("drops"))
        return dest
    }
}

func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("plopcut-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// 2026-10-02T06:31:29.850365000Z
let sampleDate = Date(timeIntervalSince1970: 1_790_922_689.850365)

let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])

func expectCode(_ code: String, _ body: () throws -> some Any) -> Bool {
    do { _ = try body(); return false } catch let e as PlopcutError { return e.code == code } catch { return false }
}
