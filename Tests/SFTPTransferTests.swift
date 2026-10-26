import Foundation
import Testing
@testable import Shellhand

/// Carrying a file, against a server that only exists in this process.
///
/// These are the paths no unit test could reach before, because `connect`
/// spawns `ssh` and the only way to answer it was a real server. The ones
/// worth having are where the **server misbehaves**, which a real one will
/// not do on request.
///
/// The time limit is on the suite because every test in it waits on a reply
/// carried over a pipe, and a reply that never comes is not a failure — it is
/// an unbounded wait. One run sat for sixteen minutes before it was killed by
/// hand, having reported nothing at all; a limit turns that into a named
/// failure. It is deliberately not on `SFTPWireTests`, which only encodes and
/// decodes and has nothing to wait for.
@Suite("SFTP transfers", .timeLimit(.minutes(1)))
nonisolated struct SFTPTransferTests {
    private func scratch(_ name: String) -> String {
        TestScratch.directory("sftp") + "/" + name
    }

    @Test("a whole file arrives, byte for byte")
    func whole() async throws {
        let bytes = Data((0..<40_000).map { UInt8($0 % 251) })
        let server = ScriptedSFTP(contents: bytes)
        let client = await server.client()
        defer { server.stop() }

        let local = scratch("whole.bin")
        try await client.download("/remote/whole.bin", to: local)

        let landed = try Data(contentsOf: URL(fileURLWithPath: local))
        #expect(landed == bytes)
    }

    /// The one this whole exercise is for. `SFTPTransfer` says it plainly:
    /// "A file that arrives short is a file with a piece missing, and nothing
    /// downstream would notice: the handle closes, the job says done, and what
    /// is on disk is wrong."
    @Test("a file that arrives short is an error, not a quietly truncated file")
    func short() async throws {
        let bytes = Data(repeating: 0x7F, count: 10_000)
        // The server's own stat promises twice what it will hand over.
        let server = ScriptedSFTP(contents: bytes, claimedSize: 20_000)
        let client = await server.client()
        defer { server.stop() }

        let local = scratch("short.bin")
        await #expect(throws: SFTPError.self) {
            try await client.download("/remote/short.bin", to: local)
        }
    }

    @Test("the error says how much of how much arrived")
    func shortSaysHowMuch() async throws {
        let server = ScriptedSFTP(contents: Data(repeating: 1, count: 500), claimedSize: 4_000)
        let client = await server.client()
        defer { server.stop() }

        do {
            try await client.download("/remote/short.bin", to: scratch("short2.bin"))
            Issue.record("a short file should not have been accepted")
        } catch let error as SFTPError {
            #expect(error.message.contains("500 of 4000 bytes arrived"))
        }
    }

    /// Nothing at all is the same failure as a piece missing, and is the one
    /// that was actually happening.
    @Test("a file that does not arrive at all is an error too")
    func nothing() async throws {
        let server = ScriptedSFTP(contents: Data(), claimedSize: 1_000)
        let client = await server.client()
        defer { server.stop() }

        await #expect(throws: SFTPError.self) {
            try await client.download("/remote/gone.bin", to: scratch("gone.bin"))
        }
    }

    /// An empty file is not a short one: nothing was promised and nothing
    /// came, which is the file.
    @Test("an empty file is carried, not refused")
    func empty() async throws {
        let server = ScriptedSFTP(contents: Data(), claimedSize: 0)
        let client = await server.client()
        defer { server.stop() }

        let local = scratch("empty.bin")
        try await client.download("/remote/empty.bin", to: local)
        #expect(try Data(contentsOf: URL(fileURLWithPath: local)).isEmpty)
    }

    // MARK: the other direction

    private func localFile(_ name: String, _ bytes: Data) throws -> String {
        let path = scratch(name)
        try bytes.write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test("a whole file goes up, byte for byte")
    func sendsWhole() async throws {
        let bytes = Data((0..<40_000).map { UInt8($0 % 241) })
        let server = ScriptedSFTP()
        let client = await server.client()
        defer { server.stop() }

        try await client.upload(try localFile("up.bin", bytes), to: "/remote/up.bin")
        #expect(server.received == bytes)
    }

    /// The other half of the bug the download side had. Upload never grew the
    /// `done == 0` guard, so nothing arriving has always been fine here — and
    /// an empty file is exactly nothing arriving. The create-and-truncate on
    /// the open is what makes the file at the far end.
    @Test("an empty file goes up as an empty file, not as nothing at all")
    func sendsEmpty() async throws {
        let server = ScriptedSFTP()
        let client = await server.client()
        defer { server.stop() }

        try await client.upload(try localFile("empty.bin", Data()), to: "/remote/empty.bin")
        #expect(server.received.isEmpty)
        #expect(server.openFlags != nil, "it still opened the file, which is what creates it")
    }

    /// Replacing is the whole point of the open: by the time bytes are going
    /// up, the question has been asked and answered.
    @Test("the upload asks to create and to truncate")
    func truncates() async throws {
        let server = ScriptedSFTP()
        let client = await server.client()
        defer { server.stop() }

        try await client.upload(try localFile("flags.bin", Data([1, 2, 3])), to: "/remote/f.bin")
        let flags = try #require(server.openFlags)
        #expect(flags & SFTP.OpenFlags.write.rawValue != 0)
        #expect(flags & SFTP.OpenFlags.create.rawValue != 0)
        #expect(flags & SFTP.OpenFlags.truncate.rawValue != 0)
    }

    @Test("a far end that will not take the bytes is an error, not a success")
    func refused() async throws {
        let server = ScriptedSFTP(refuseWrites: true)
        let client = await server.client()
        defer { server.stop() }

        let local = try localFile("refused.bin", Data(repeating: 9, count: 5_000))
        await #expect(throws: SFTPError.self) {
            try await client.upload(local, to: "/remote/refused.bin")
        }
    }

    @Test("a local file that is not there is an error before anything is sent")
    func missingLocal() async throws {
        let server = ScriptedSFTP()
        let client = await server.client()
        defer { server.stop() }

        await #expect(throws: SFTPError.self) {
            try await client.upload(scratch("never-written.bin"), to: "/remote/x.bin")
        }
        #expect(server.openFlags == nil, "it did not even open the far end")
    }

    /// A reply to a request nobody made is counted rather than dropped in
    /// silence, because it is the kind of thing that explains a short file.
    @Test("a reply nobody asked for is counted")
    func stray() async throws {
        let unasked = ScriptedSFTP.status(id: 9_999, .failure)
        let server = ScriptedSFTP(contents: Data(repeating: 2, count: 100), intruder: unasked)
        let client = await server.client()
        defer { server.stop() }

        try await client.download("/remote/ok.bin", to: scratch("ok.bin"))
        #expect(await client.strayReplies == 1)
    }
}
