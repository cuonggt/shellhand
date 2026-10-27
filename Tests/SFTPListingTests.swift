import Foundation
import Testing
@testable import Shellhand

/// Reading a directory, and what the far end's refusals come out as.
///
/// Both are multi-step and neither could be reached before: `list` keeps
/// asking until the server says EOF, and an error has to survive two layers —
/// the status code, and whatever sentence the server chose to send with it.
///
/// The time limit is on the suite because every test in it waits on a reply
/// carried over a pipe, and a reply that never comes is not a failure — it is
/// an unbounded wait. One run sat for sixteen minutes before it was killed by
/// hand, having reported nothing at all; a limit turns that into a named
/// failure. It is deliberately not on `SFTPWireTests`, which only encodes and
/// decodes and has nothing to wait for.
@Suite("SFTP listings", .timeLimit(.minutes(1)))
nonisolated struct SFTPListingTests {
    /// The minimal conversation — one opendir, one readdir, EOF — and the test
    /// the stall turned up in most, naming `readdir` here twice before it was
    /// traced to `ScriptedSFTP` itself and fixed; `SFTPChurnTests` guards that.
    ///
    /// The catch stays as insurance rather than a hunt. Should anything like it
    /// come back, the deadline's error already says which request went
    /// unanswered, and `lateReplies` is the only thing that can say whether the
    /// answer came late or never came at all — read *after* the failure, which
    /// a bare `try` throws away. A second's grace is for a reply still in
    /// flight.
    @Test("a directory that arrives in one go")
    func oneBatch() async throws {
        let server = ScriptedSFTP(directory: [["alpha", "beta"]])
        let client = await server.client()
        defer { server.stop() }

        do {
            let entries = try await client.list("/srv")
            #expect(entries.map(\.name) == ["alpha", "beta"])
        } catch let error as SFTPError {
            try? await Task.sleep(for: .seconds(1))
            let late = await client.lateReplies
            let strays = await client.strayReplies
            Issue.record(
                "\(error.message) — after a second: lateReplies=\(late) strayReplies=\(strays)")
        }
    }

    /// The normal case for a large directory, and the reason `list` is a loop
    /// rather than one request.
    @Test("a directory that arrives in pieces is joined, in order")
    func manyBatches() async throws {
        let server = ScriptedSFTP(directory: [["alpha", "beta"], ["gamma"], ["delta", "epsilon"]])
        let client = await server.client()
        defer { server.stop() }

        let entries = try await client.list("/srv")
        #expect(entries.map(\.name) == ["alpha", "beta", "gamma", "delta", "epsilon"])
    }

    /// Not entries anyone wants in a browser, and the parent has its own
    /// button.
    @Test("dot and dot-dot are left out, wherever they turn up")
    func dots() async throws {
        let server = ScriptedSFTP(directory: [[".", "..", "alpha"], ["..", "beta"]])
        let client = await server.client()
        defer { server.stop() }

        #expect(try await client.list("/srv").map(\.name) == ["alpha", "beta"])
    }

    @Test("a directory holding nothing is empty, not an error")
    func empty() async throws {
        let server = ScriptedSFTP(directory: [])
        let client = await server.client()
        defer { server.stop() }

        #expect(try await client.list("/srv").isEmpty)
    }

    /// A directory of nothing but dot entries is still empty — the filtering
    /// happens after the batch, so this is the case where the loop would stop
    /// early if EOF were inferred from an empty result.
    @Test("a directory of only dot entries is empty, and still ends")
    func onlyDots() async throws {
        let server = ScriptedSFTP(directory: [[".", ".."]])
        let client = await server.client()
        defer { server.stop() }

        #expect(try await client.list("/srv").isEmpty)
    }

    // MARK: what a refusal reads as

    /// The server's own sentence is the useful one — "Permission denied" from
    /// the far end beats anything this app would compose.
    @Test("the far end's own words are kept when it sends any")
    func ownWords() async throws {
        let server = ScriptedSFTP(refusal: (.permissionDenied, "Permission denied by policy"))
        let client = await server.client()
        defer { server.stop() }

        do {
            try await client.mkdir("/srv/nope")
            Issue.record("mkdir should have been refused")
        } catch let error as SFTPError {
            #expect(error.message == "Permission denied by policy")
            #expect(error.status == .permissionDenied)
        }
    }

    @Test("a refusal with nothing said still reads as a sentence")
    func composedWords() async throws {
        let server = ScriptedSFTP(refusal: (.noSuchFile, ""))
        let client = await server.client()
        defer { server.stop() }

        do {
            try await client.remove("/srv/gone")
            Issue.record("remove should have been refused")
        } catch let error as SFTPError {
            #expect(error.message == "there is no such file")
        }
    }

    @Test("a status nobody has a sentence for still says which it was")
    func unknownStatus() async throws {
        let server = ScriptedSFTP(refusal: (.badMessage, ""))
        let client = await server.client()
        defer { server.stop() }

        do {
            try await client.rename("/a", to: "/b")
            Issue.record("rename should have been refused")
        } catch let error as SFTPError {
            #expect(error.message.contains("status 5"))
        }
    }
}
