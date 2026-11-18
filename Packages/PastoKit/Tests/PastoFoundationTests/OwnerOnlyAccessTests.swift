import Foundation
import PastoFoundation
import Testing

struct OwnerOnlyAccessTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "PastoAccess-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func permissions(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    private func write(_ name: String, in folder: URL, mode: Int) throws -> URL {
        let file = folder.appending(path: name)
        try Data("history".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
        return file
    }

    @Test func aFolderAndEverythingInItBecomeTheUsersAlone() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "jnjambrino.Pasto", directoryHint: .isDirectory)
        let external = folder.appending(path: ".Pasto_SUPPORT/_EXTERNAL_DATA", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        let store = try write("Pasto.sqlite", in: folder, mode: 0o644)
        let blob = try write("ABC", in: external, mode: 0o644)
        let journal = try write("paste-journal.jsonl", in: folder, mode: 0o600)

        let changed = try OwnerOnlyAccess.restrict(folder)

        #expect(try permissions(of: folder) == 0o700)
        #expect(try permissions(of: external) == 0o700)
        #expect(try permissions(of: external.deletingLastPathComponent()) == 0o700)
        #expect(try permissions(of: store) == 0o600)
        #expect(try permissions(of: blob) == 0o600)
        #expect(try permissions(of: journal) == 0o600)
        // The journal already had its mode.
        #expect(changed == 5)
        #expect(try OwnerOnlyAccess.restrict(folder) == 0)
    }

    @Test func aMissingFolderIsCreatedForTheUserAlone() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "new/jnjambrino.Pasto", directoryHint: .isDirectory)

        try OwnerOnlyAccess.restrict(folder)

        #expect(try permissions(of: folder) == 0o700)
    }

    @Test func symbolicLinksAreNeitherFollowedNorChanged() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "jnjambrino.Pasto", directoryHint: .isDirectory)
        let elsewhere = root.appending(path: "elsewhere", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let outside = try write("outside.txt", in: elsewhere, mode: 0o644)
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "link"), withDestinationURL: elsewhere)

        try OwnerOnlyAccess.restrict(folder)

        #expect(try permissions(of: outside) == 0o644)
    }
}
