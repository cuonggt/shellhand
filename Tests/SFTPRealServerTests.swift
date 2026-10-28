import Foundation
import Testing

@testable import Shellhand

/// The SFTP conversation held against OpenSSH's own server — the binary `sshd`
/// execs at the far end of every `ssh -s sftp` — over a pair of pipes.
///
/// Every other SFTP check here is held against `ScriptedSFTP`, which answers
/// from this project's own idea of the protocol, so a misunderstanding both
/// ends share goes unnoticed — and that harness was itself wrong for weeks
/// without anybody being able to tell. This cannot share a misunderstanding,
/// because it is the reference. It ships with macOS, so it costs no
/// prerequisite: no Go toolchain, no network, no keys, no `sshd`, and no SSH
/// server written in Swift. It is reached through the same seam the scripted
/// one is, after the same opening `connect` makes.
///
/// **What it does not reach is the `ssh` transport** — connecting, logging in,
/// jump hosts, `BatchMode`. That stays uncovered. Everything above it, the
/// conversation and the transfers and the errors, is held against the real
/// thing.
///
/// **`-d` says where the server starts; it is not a jail.** It runs as whoever
/// runs the suite, with all of their access, so every path below is absolute
/// and under `TestScratch`, and every test that only reads asks for `-R` too.
/// Keep both habits: a stray path here really does delete a file.
@Suite("SFTP against OpenSSH's sftp-server", .timeLimit(.minutes(1)))
nonisolated struct SFTPRealServerTests {
    /// The handshake is the one thing the scripted server cannot check: it
    /// answers whatever it is sent, version or not, while the real one refuses
    /// to do anything until the versions have been agreed.
    @Test("the opening the app makes is the one the real server expects")
    func opening() async throws {
        let server = try RealSFTPServer(readOnly: true)
        defer { server.stop() }

        let client = try await server.client()
        #expect(await client.home == server.root)
    }

    /// OpenSSH sends at most a hundred names per `readdir` — measured: 250
    /// files and `.` and `..` arrive as 100, 100 and 52 — so this is the
    /// end-of-directory rule against batches the client did not choose.
    @Test("a directory the server sends in several batches arrives whole")
    func severalBatches() async throws {
        let names = (1...250).map { String(format: "f%03d", $0) }
        let server = try RealSFTPServer(readOnly: true) { root in
            for name in names {
                FileManager.default.createFile(atPath: root + "/" + name, contents: Data())
            }
        }
        defer { server.stop() }

        let client = try await server.client()
        let entries = try await client.list(server.root)
        #expect(entries.map(\.name).sorted() == names)
    }

    @Test("stat says what the real server says a file is")
    func statSaysWhatTheServerSays() async throws {
        let server = try RealSFTPServer(readOnly: true) { root in
            FileManager.default.createFile(atPath: root + "/seven.txt", contents: Data("1234567".utf8))
            try FileManager.default.createDirectory(
                atPath: root + "/sub", withIntermediateDirectories: false)
        }
        defer { server.stop() }

        let client = try await server.client()
        let file = try await client.stat(server.root + "/seven.txt")
        #expect(file.size == 7)
        #expect(!file.isDirectory)
        #expect(try await client.stat(server.root + "/sub").isDirectory)
    }

    @Test("a path that is not there is the real server's no-such-file")
    func missing() async throws {
        let server = try RealSFTPServer(readOnly: true)
        defer { server.stop() }

        let client = try await server.client()
        do {
            _ = try await client.stat(server.root + "/absent")
            Issue.record("stat of a missing path should have failed")
        } catch let error as SFTPError {
            #expect(error.isNoSuchFile)
        }
    }

    /// Empty is the file that could not be carried before 0.0.4; one chunk is
    /// the boundary; the last is more than two whole pipelined windows with a
    /// ragged end, which is where a short read would leave a hole.
    @Test("a download is byte for byte what the server holds",
          arguments: [0, 1, SFTPClient.chunk, 600_001])
    func downloads(size: Int) async throws {
        let held = Self.bytes(size)
        let server = try RealSFTPServer(readOnly: true) { root in
            FileManager.default.createFile(atPath: root + "/held.bin", contents: held)
        }
        defer { server.stop() }

        let client = try await server.client()
        let local = TestScratch.directory("downloaded") + "/held.bin"
        try await client.download(server.root + "/held.bin", to: local)
        #expect(FileManager.default.contents(atPath: local) == held)
    }

    @Test("an upload lands byte for byte on the server",
          arguments: [0, 1, SFTPClient.chunk, 600_001])
    func uploads(size: Int) async throws {
        let sent = Self.bytes(size)
        let local = TestScratch.directory("to-upload") + "/sent.bin"
        FileManager.default.createFile(atPath: local, contents: sent)
        let server = try RealSFTPServer()
        defer { server.stop() }

        let client = try await server.client()
        try await client.upload(local, to: server.root + "/sent.bin")
        #expect(FileManager.default.contents(atPath: server.root + "/sent.bin") == sent)
    }

    /// `remove` asks what a path is before choosing between two requests, so a
    /// folder and a file are both worth taking away.
    @Test("a folder made, renamed and removed, and a file removed")
    func makeRenameRemove() async throws {
        let server = try RealSFTPServer { root in
            FileManager.default.createFile(atPath: root + "/doomed.txt", contents: Data("x".utf8))
        }
        defer { server.stop() }

        let client = try await server.client()
        let made = server.root + "/made", moved = server.root + "/moved"
        try await client.mkdir(made)
        #expect(FileManager.default.fileExists(atPath: made))
        try await client.rename(made, to: moved)
        #expect(!FileManager.default.fileExists(atPath: made))
        #expect(FileManager.default.fileExists(atPath: moved))
        try await client.remove(moved)
        #expect(!FileManager.default.fileExists(atPath: moved))
        try await client.remove(server.root + "/doomed.txt")
        #expect(!FileManager.default.fileExists(atPath: server.root + "/doomed.txt"))
    }

    /// The real server's own refusal, carried through as the status it sent —
    /// measured: `-R` answers a write with 3, *Permission denied*.
    @Test("a server that will not write says so, and nothing is written")
    func refusesToWrite() async throws {
        let server = try RealSFTPServer(readOnly: true)
        defer { server.stop() }

        let client = try await server.client()
        do {
            try await client.mkdir(server.root + "/nope")
            Issue.record("a read-only server should have refused")
        } catch let error as SFTPError {
            #expect(error.status == .permissionDenied)
        }
        #expect(!FileManager.default.fileExists(atPath: server.root + "/nope"))
    }

    /// Bytes that differ from their neighbours, so that a chunk landing in the
    /// wrong place cannot pass for the right one.
    static func bytes(_ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: ($0 &* 2_654_435_761) >> 13) })
    }

    // MARK: a small file read straight into memory

    /// `contents(of:)` is how the app reads the one file it reads rather than
    /// carries — a host's own `/etc/os-release`, to draw it with its
    /// distribution's mark. Held against the real server because it is a
    /// different path through the protocol from `download`: no local file, no
    /// progress, and a stop condition of its own.
    @Test("a small file reads straight into memory, byte for byte")
    func readsASmallFile() async throws {
        let said = "PRETTY_NAME=\"Ubuntu 22.04.3 LTS\"\nID=ubuntu\nID_LIKE=debian\n"
        let server = try RealSFTPServer(readOnly: true) { root in
            try said.write(toFile: root + "/os-release", atomically: true, encoding: .utf8)
        }
        defer { server.stop() }

        let client = try await server.client()
        let bytes = try await client.contents(of: server.root + "/os-release")

        #expect(String(data: bytes, encoding: .utf8) == said)
        // And the whole point of reading it: the id the mark is named after.
        #expect(OSRelease.id(from: String(data: bytes, encoding: .utf8) ?? "") == "ubuntu")
    }

    /// The path is one this app chose, but the file behind it belongs to
    /// somebody else's machine and nothing promises it is small. The read
    /// stops rather than pulling an arbitrary amount into memory.
    @Test("a file larger than the limit stops at the limit")
    func stopsAtTheLimit() async throws {
        let server = try RealSFTPServer(readOnly: true) { root in
            try Data(repeating: 0x61, count: 200_000).write(to: URL(fileURLWithPath: root + "/big"))
        }
        defer { server.stop() }

        let client = try await server.client()
        let bytes = try await client.contents(of: server.root + "/big", limit: 4096)

        #expect(bytes.count == 4096)
    }

    @Test("a file that is not there is a failure, not an empty answer")
    func missingFile() async throws {
        let server = try RealSFTPServer(readOnly: true)
        defer { server.stop() }

        let client = try await server.client()
        await #expect(throws: SFTPError.self) {
            _ = try await client.contents(of: server.root + "/nothing-here")
        }
    }
}

/// One `sftp-server`, started over pipes and stopped by letting go of them.
///
/// `nonisolated` for the reason every test type here is: the app target
/// defaults to MainActor and `Tests/` is compiled into it.
nonisolated final class RealSFTPServer: @unchecked Sendable {
    /// Where it starts, with its symlinks settled — the server answers
    /// `realpath` that way, and the temporary directory is behind one here.
    let root: String
    private let process = Process()
    /// Marked at birth, for the reason this suite once hung for a minute: a
    /// shell forked mid run — the local-shell test — took an unmarked server
    /// input with it, and the server never saw that input end. See `Forking`.
    private let toServer = Pipe.marked()
    private let fromServer = Pipe.marked()

    /// `populate` runs before the server starts, so a read-only one can still
    /// be given something to read.
    init(readOnly: Bool = false, populate: (String) throws -> Void = { _ in }) throws {
        let made = TestScratch.directory("sftp-server")
        guard let settled = Darwin.realpath(made, nil) else {
            throw SFTPError("\(made) could not be resolved")
        }
        root = String(cString: settled)
        free(settled)
        try populate(root)

        process.executableURL = URL(fileURLWithPath: "/usr/libexec/sftp-server")
        process.arguments = ["-d", root] + (readOnly ? ["-R"] : [])
        process.standardInput = toServer
        process.standardOutput = fromServer
        // It logs to syslog unless told otherwise, but a pipe nobody reads is
        // a server that blocks the moment it does write one, so: nowhere.
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// A client that has made the same opening `connect` makes.
    func client() async throws -> SFTPClient {
        let client = await SFTPClient.speaking(
            to: toServer.fileHandleForWriting, from: fromServer.fileHandleForReading)
        try await client.begin()
        return client
    }

    /// Lets go of the server's input and gives it a few seconds to end by
    /// itself, then ends it. Never `close()` the client instead: its own
    /// `Process` was never started, and terminating one that never ran raises.
    ///
    /// **Bounded, never `waitUntilExit()`.** That cannot be interrupted, so a
    /// server whose input some forked child is holding waits as long as the
    /// child lives, and the run learns nothing but *"Time limit was exceeded"*
    /// on whichever test was tearing down. `Forking` means this suite's own
    /// pipes can no longer be taken that way, so the bound is insurance now
    /// rather than the fix — kept because a teardown should never be able to
    /// hang a run, whatever opened the descriptor. A server ended here rather
    /// than by itself is not a failure of what the test checked: every
    /// assertion was made over the conversation before this runs.
    func stop() {
        try? toServer.fileHandleForWriting.close()
        let until = Date().addingTimeInterval(5)
        while process.isRunning && Date() < until { usleep(10_000) }
        if process.isRunning { process.terminate() }
    }
}
