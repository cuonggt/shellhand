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
        /// Path to the target string **as stored** — relative or absolute,
        /// resolved or dangling. What a link points at is not followed here,
        /// because the transfer does not follow it either.
        var links: [String: String] = [:]
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

    /// Every shape of link worth carrying: one to a file, one to a folder,
    /// one that points nowhere, and one written absolute — the target is
    /// copied as a string, so none of them is resolved on the way.
    static let linked = Tree(
        folders: ["real"],
        files: ["real/f.txt": Data("bytes".utf8)],
        links: [
            "to-file": "real/f.txt",
            "to-dir": "real",
            "dangling": "nowhere",
            "absolute": "/etc/hosts",
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
        // Last, so a link may sit inside a folder this just made.
        for (path, target) in tree.links {
            try manager.createSymbolicLink(
                atPath: root + "/" + path, withDestinationPath: target)
        }
    }

    /// Asks `lstat`, not `stat`. The first version used
    /// `fileExists(atPath:isDirectory:)`, which **follows** a symlink: a link
    /// to a folder was recorded as a folder and a link to a file as that
    /// file's bytes, so a snapshot could not have told a carried link from a
    /// carried copy — and the thing these tests most need to see is exactly
    /// that difference.
    static func snapshot(_ root: String) -> Tree {
        var tree = Tree()
        let manager = FileManager.default
        guard let walker = manager.enumerator(atPath: root) else { return tree }
        while let relative = walker.nextObject() as? String {
            let path = root + "/" + relative
            guard let attributes = try? manager.attributesOfItem(atPath: path) else { continue }
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink:
                tree.links[relative] =
                    (try? manager.destinationOfSymbolicLink(atPath: path)) ?? ""
            case .typeDirectory:
                tree.folders.insert(relative)
            case .typeRegular:
                tree.files[relative] = manager.contents(atPath: path)
            default:
                continue
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

    // MARK: symlinks, carried as symlinks

    /// A symlink is carried **as a link**, both ways: the target string copied
    /// verbatim and nothing followed. Until these, download skipped links
    /// outright while upload turned one into a copy of its target's bytes, a
    /// link to a folder into an **empty folder** on the far end, and a
    /// dangling one into nothing at all — three silent divergences, none
    /// reported, and a round trip that could not give back the tree it took.
    @Test("links come down as links, pointing where they pointed")
    func downloadsLinks() async throws {
        let server = try RealSFTPServer(readOnly: true) { root in
            try Self.plant(Self.linked, at: root + "/tree")
        }
        defer { server.stop() }
        let local = TestScratch.directory("link-down") + "/tree"

        let client = try await server.client()
        try await client.downloadDirectory(server.root + "/tree", to: local)

        let arrived = Self.snapshot(local)
        #expect(
            arrived.links == Self.linked.links,
            "links that did not arrive as links: \(Self.linked.links.keys.filter { arrived.links[$0] == nil }.sorted())")
        #expect(arrived.files == Self.linked.files)
        #expect(arrived.folders == Self.linked.folders)
    }

    @Test("links go up as links, pointing where they pointed")
    func uploadsLinks() async throws {
        let local = TestScratch.directory("link-up") + "/tree"
        try Self.plant(Self.linked, at: local)
        let server = try RealSFTPServer()
        defer { server.stop() }

        let client = try await server.client()
        try await client.uploadDirectory(local, to: server.root)

        let arrived = Self.snapshot(server.root + "/tree")
        #expect(
            arrived.links == Self.linked.links,
            "links that did not arrive as links: \(Self.linked.links.keys.filter { arrived.links[$0] == nil }.sorted())")
        #expect(arrived.files == Self.linked.files)
        #expect(arrived.folders == Self.linked.folders)
    }

    // MARK: there and back

    /// The test that matters most, since it is what someone does: a folder
    /// sent up and brought back down must be the folder they started with.
    /// The strongest claim in the file, and the one that catches a pair of
    /// directions that each look right alone: the whole tree, compared whole.
    @Test("a tree of links carried up and brought back is the tree it was")
    func linkRoundTrip() async throws {
        let original = TestScratch.directory("link-there") + "/tree"
        try Self.plant(Self.linked, at: original)
        let server = try RealSFTPServer()
        defer { server.stop() }
        let back = TestScratch.directory("link-back") + "/tree"

        let client = try await server.client()
        try await client.uploadDirectory(original, to: server.root)
        try await client.downloadDirectory(server.root + "/tree", to: back)

        #expect(Self.snapshot(back) == Self.linked)
    }

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

    // MARK: symlinks, on the wire

    /// The one thing only a real server can settle: which way round
    /// `SSH_FXP_SYMLINK` takes its two paths. Draft 02 writes linkpath then
    /// targetpath and OpenSSH has always read them the other way, so getting
    /// it backwards makes a link named after its own target. The link is read
    /// back off the server's **own disk** rather than through the protocol
    /// that wrote it, because a reversed pair would look consistent to
    /// `readlink` and wrong to everything else.
    @Test("a symlink made over the wire points where it was told")
    func symlinkOnTheWire() async throws {
        let server = try RealSFTPServer { root in
            FileManager.default.createFile(
                atPath: root + "/target.txt", contents: Data("bytes".utf8))
        }
        defer { server.stop() }

        let client = try await server.client()
        try await client.symlink("target.txt", at: server.root + "/link")

        let onDisk = try FileManager.default.destinationOfSymbolicLink(
            atPath: server.root + "/link")
        #expect(onDisk == "target.txt", "the link on disk points at \(onDisk)")
        let throughTheProtocol = try await client.readlink(server.root + "/link")
        #expect(throughTheProtocol == "target.txt")
    }

    // MARK: a refusal nothing else would notice

    /// A folder with files under it surfaces a refused `mkdir` through the
    /// files' own failures. An empty one has nothing to fail with, so
    /// swallowing the refusal left it vanishing while the job reported done —
    /// the same silent shape as the empty folder that downloaded as nothing.
    /// The server refuses for real here: `-R` is OpenSSH's own read-only
    /// mode, not an answer this project wrote.
    @Test("an empty folder that cannot be made fails rather than reporting success")
    func refusedAtTheRoot() async throws {
        let local = TestScratch.directory("folder-up-refused") + "/nothing"
        try FileManager.default.createDirectory(atPath: local, withIntermediateDirectories: true)
        let server = try RealSFTPServer(readOnly: true)
        defer { server.stop() }

        let client = try await server.client()
        let error = await #expect(throws: SFTPError.self) {
            try await client.uploadDirectory(local, to: server.root)
        }
        #expect(error?.message.isEmpty == false, "the refusal came back with nothing said")
        #expect(!Self.isFolder(server.root + "/nothing"), "it was made after all")
    }

    /// The other half, and the one that needs the far end **asked** rather
    /// than the status read: SFTP 3 has no "already exists", so OpenSSH
    /// answers a name already taken with the same failure it gives a
    /// read-only disk. Here the destination is a folder — already there, so
    /// carrying on is right — while the folder that has to go inside it is a
    /// **file**, which is a refusal worth reporting. With both swallowed the
    /// upload said done and the folder was simply not there.
    @Test("a folder whose name is taken by a file fails, where one already made does not")
    func refusedInside() async throws {
        let local = TestScratch.directory("folder-up-taken") + "/tree"
        try FileManager.default.createDirectory(
            atPath: local + "/empty", withIntermediateDirectories: true)
        let server = try RealSFTPServer { root in
            try FileManager.default.createDirectory(
                atPath: root + "/tree", withIntermediateDirectories: false)
            FileManager.default.createFile(
                atPath: root + "/tree/empty", contents: Data("taken".utf8))
        }
        defer { server.stop() }

        let client = try await server.client()
        await #expect(throws: SFTPError.self) {
            try await client.uploadDirectory(local, to: server.root)
        }
        #expect(
            !Self.isFolder(server.root + "/tree/empty"),
            "the file standing in the folder's place was replaced")
    }

    /// The control. Half of the `try?` those two replace was deliberate —
    /// carrying a folder onto one already there merges rather than fails — so
    /// a fix that merely stopped swallowing would satisfy both tests above
    /// and break every upload this app makes.
    @Test("a folder carried onto one already there still merges")
    func uploadsOntoItself() async throws {
        let local = TestScratch.directory("folder-up-twice") + "/tree"
        try Self.plant(Self.sample, at: local)
        let server = try RealSFTPServer()
        defer { server.stop() }

        let client = try await server.client()
        try await client.uploadDirectory(local, to: server.root)
        try await client.uploadDirectory(local, to: server.root)

        let arrived = Self.snapshot(server.root + "/tree")
        #expect(arrived.files == Self.sample.files)
        #expect(
            arrived.folders == Self.sample.folders,
            "folders lost on the second pass: \(Self.sample.folders.subtracting(arrived.folders).sorted())")
    }
}
