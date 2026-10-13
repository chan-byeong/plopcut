import Foundation
import Testing
@testable import PlopcutCore

@Suite struct StorageFolderCheckTests {
    private func makeTemp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("folder-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func existingWritableFolderHasNoProblem() throws {
        let dir = try makeTemp()
        #expect(StorageFolderCheck.problem(for: dir) == nil)
    }

    @Test func missingFolderThatCanBeCreatedHasNoProblem() throws {
        let dir = try makeTemp().appendingPathComponent("a/b/plopcut")
        #expect(StorageFolderCheck.problem(for: dir) == nil)
    }

    @Test func aFileInsteadOfAFolderIsRejected() throws {
        let file = try makeTemp().appendingPathComponent("plain.txt")
        try Data("x".utf8).write(to: file)
        #expect(StorageFolderCheck.problem(for: file)?.code == "invalid_storage_folder")
    }

    @Test func readOnlyFolderIsRejected() throws {
        let dir = try makeTemp()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        #expect(StorageFolderCheck.problem(for: dir)?.code == "storage_unwritable")
    }

    @Test func missingFolderUnderAReadOnlyAncestorIsRejected() throws {
        let dir = try makeTemp()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        #expect(StorageFolderCheck.problem(for: dir.appendingPathComponent("x/plopcut"))?.code == "storage_unwritable")
    }

    @Test func ensureUsableThrowsTheProblem() throws {
        let file = try makeTemp().appendingPathComponent("plain.txt")
        try Data("x".utf8).write(to: file)
        #expect(throws: PlopcutError.self) { try StorageFolderCheck.ensureUsable(file) }
    }

    @Test func prepareCreatesAMissingFolder() throws {
        let dir = try makeTemp().appendingPathComponent("plopcut")
        try StorageFolderCheck.prepare(dir)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }
}
