import Foundation
import Testing

@testable import Shellhand

/// Folders carried whole, against OpenSSH's own `sftp-server`.
///
/// `downloadDirectory` and `uploadDirectory` run whenever a folder is dragged
/// between the SFTP window's panes, and until these nothing called them at
/// all. A folder is where carrying goes wrong in ways a single file cannot: the
/// recursion, the nesting, a folder with nothing in it, and a tree that has to
/// come out the far side as the same tree. So each test plants a real one and
/// compares what arrived file by file and folder by folder — kept apart, so a
/// failure says which went missing.
@Suite("Folders, against OpenSSH's sftp-server", .timeLimit(.minutes(1)))
nonisolated struct SFTPFolderTests {
    /// A tree as it sits on disk: every folder under its root, and every file
    /// with its bytes, by path relative to that root.
    struct Tree: Equatable {
        var folders: Set<String> = []
        var files: [String: Data] = [:]
    }

    /// Nested two deep, with folders that hold nothing — one at the top, one
    /// beside a file — a dotfile, a file of no bytes, and one long enough to
    /// take several pipelined windows with a ragged end.
    static let sample = Tree(
        folders: ["sub", "sub/deeper", "sub/also-empty", "empty"],
        files: [
            "a.txt": Data("alpha".utf8),
            "zero.bin": Data(),
            ".hidden": Data("dotfile".utf8),
            "sub/b.bin": SFTPRealServerTests.bytes(600_001),
            "sub/deeper/c.txt": Data("gamma".utf8),
        ])

    static func plant(_ tree: Tree, at root: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(atPath: root, withIntermediateDirectories: true)
        for folder in tree.folders {
            try manager.createDirectory(
                atPath: root + "/" + folder, withIntermediateDirectories: true)
        }
        for (path, bytes) in tree.files {
            manager.createFile(atPath: root + "/" + path, contents: bytes)
        }
    }

    static func snapshot(_ root: String) -> Tree {
        var tree = Tree()
        let manager = FileManager.default
        guard let walker = manager.enumerator(atPath: root) else { return tree }
        while let relative = walker.nextObject() as? String {
            var isFolder: ObjCBool = false
            let path = root + "/" + relative
            guard manager.fileExists(atPath: path, isDirectory: &isFolder) else { continue }
            if isFolder.boolValue {
                tree.folders.insert(relative)
            } else {
                tree.files[relative] = manager.contents(atPath: path)
            }
        }
        return tree
    }

    static func isFolder(_ path: String) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && isFolder.boolValue
    }

    // MARK: down

    @Test("a folder downloads whole: every file, byte for byte, and every folder")
    func downloadsWhole() async throws {
        let server = try RealSFTPServer(readOnly: true) { root in
            try Self.plant(Self.sample, at: root + "/tree")
        }
        defer { server.stop() }
        let local = TestScratch.directory("folder-down") + "/tree"

        let client = try await server.client()
        try await client.downloadDirectory(server.root + "/tree", to: local)

        let arrived = Self.snapshot(local)
        #expect(arrived.files == Self.sample.files)
        #expect(
            arrived.folders == Self.sample.folders,
            "folders that never arrived: \(Self.sample.folders.subtracting(arrived.folders).sorted())")
    }

    /// The whole of an empty folder is the folder. Nothing arriving, with the
    /// transfer reporting success, is the worst way for this to go wrong.
    @Test("an empty folder downloads as an empty folder, not as nothing")
    func downloadsEmpty() async throws {
        let server = try RealSFTPServer(readOnly: true) { root in
            try FileManager.default.createDirectory(
                atPath: root + "/nothing", withIntermediateDirectories: false)
        }
        defer { server.stop() }
        let local = TestScratch.directory("folder-down-empty") + "/nothing"

        let client = try await server.client()
        try await client.downloadDirectory(server.root + "/nothing", to: local)

        #expect(Self.isFolder(local), "nothing arrived at \(local)")
        #expect(Self.snapshot(local) == Tree())
    }

    // MARK: up

    @Test("a folder uploads whole: every file, byte for byte, and every folder")
    func uploadsWhole() async throws {
        let local = TestScratch.directory("folder-up") + "/tree"
        try Self.plant(Self.sample, at: local)
        let server = try RealSFTPServer()
        defer { server.stop() }

        let client = try await server.client()
        try await client.uploadDirectory(local, to: server.root)

        let arrived = Self.snapshot(server.root + "/tree")
        #expect(arrived.files == Self.sample.files)
        #expect(
            arrived.folders == Self.sample.folders,
            "folders that never arrived: \(Self.sample.folders.subtracting(arrived.folders).sorted())")
    }

    @Test("an empty folder uploads as an empty folder, not as nothing")
    func uploadsEmpty() async throws {
        let local = TestScratch.directory("folder-up-empty") + "/nothing"
        try FileManager.default.createDirectory(atPath: local, withIntermediateDirectories: true)
        let server = try RealSFTPServer()
        defer { server.stop() }

        let client = try await server.client()
        try await client.uploadDirectory(local, to: server.root)

        #expect(Self.isFolder(server.root + "/nothing"))
        #expect(Self.snapshot(server.root + "/nothing") == Tree())
    }

    // MARK: there and back

    /// The test that matters most, since it is what someone does: a folder
    /// sent up and brought back down must be the folder they started with.
    @Test("a folder carried up and brought back down is the folder it was")
    func roundTrip() async throws {
        let original = TestScratch.directory("folder-there") + "/tree"
        try Self.plant(Self.sample, at: original)
        let server = try RealSFTPServer()
        defer { server.stop() }
        let back = TestScratch.directory("folder-back") + "/tree"

        let client = try await server.client()
        try await client.uploadDirectory(original, to: server.root)
        try await client.downloadDirectory(server.root + "/tree", to: back)

        let returned = Self.snapshot(back)
        #expect(returned.files == Self.sample.files)
        #expect(
            returned.folders == Self.sample.folders,
            "folders lost on the way: \(Self.sample.folders.subtracting(returned.folders).sorted())")
    }
}
