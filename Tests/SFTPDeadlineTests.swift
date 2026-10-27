import Foundation
import Testing

@testable import Shellhand

/// What a far end that is **there and silent** comes out as.
///
/// `SFTPFarEndTests` has the far end that has *gone* — a closed handle, a
/// broken pipe — which the reader thread notices and `finish` answers for
/// everything still waiting. This is the other one, and it is the shape of the
/// stall seen three times in this suite: pipes open, child alive, both reader
/// threads idle in `read`, and a reply that is never coming. Nothing in the
/// protocol ends that wait, so before `Deadline` these tests would not have
/// failed, they would have **hung** — which is exactly how a run once sat for
/// sixteen minutes and reported nothing at all.
///
/// The limit on the suite is the same belt as everywhere else here, and it is
/// not what is under test: a deadline that never fired would be caught by it
/// as a named failure rather than by the clock.
@Suite("SFTP deadline", .timeLimit(.minutes(1)))
nonisolated struct SFTPDeadlineTests {
    /// Pipes nobody serves, which is the whole of the real failure: the
    /// request goes out, is written perfectly, and is simply never answered.
    @Test("a request nothing answers fails, naming what went unanswered")
    func unanswered() async throws {
        let toPeer = Pipe()
        let fromPeer = Pipe()
        SFTPClient.closeOnExec(toPeer, fromPeer)
        let client = await SFTPClient.speaking(
            to: toPeer.fileHandleForWriting, from: fromPeer.fileHandleForReading,
            answeringWithin: .milliseconds(300))
        // Lets the client's reader thread end rather than blocking for ever.
        defer { try? fromPeer.fileHandleForWriting.close() }

        do {
            _ = try await client.stat("/srv/silent")
            Issue.record("a request nothing answers should not have returned")
        } catch let error as SFTPError {
            // Naming the request is the point of the sentence, not decoration:
            // 49 clean runs could not say which request stalls, and the next
            // sighting of this will say so in one line.
            #expect(error.message.contains("stat"))
            #expect(error.message.contains("did not answer"))
        }
    }

    /// The other half, and the first test does not cover it: a deadline that
    /// fired whatever happened would pass that one while breaking every
    /// transfer this app makes. A directory arriving in two batches is four
    /// requests in one conversation, and all of them must land well inside it.
    @Test("a far end that answers is not given up on")
    func answeredInTime() async throws {
        let server = ScriptedSFTP(directory: [["alpha", "beta"], ["gamma"]])
        let client = await server.client(answeringWithin: .seconds(5))
        defer { server.stop() }

        let entries = try await client.list("/srv")
        #expect(entries.map(\.name) == ["alpha", "beta", "gamma"])
    }

    /// The race the deadline introduces, pinned where it would otherwise be
    /// found in the field: a reply that arrives after its request was given up
    /// on must not be resumed into a continuation already answered, because
    /// that traps and takes the app with it.
    ///
    /// It is counted **late** rather than stray, and that difference is the
    /// only diagnostic there is for the stall: after a timeout, a late reply
    /// says the far end was answering all along and merely missed the
    /// deadline, while none at all says the answer never came.
    @Test("a reply that arrives after the deadline is counted late, not stray")
    func lateReply() async throws {
        let toPeer = Pipe()
        let fromPeer = Pipe()
        SFTPClient.closeOnExec(toPeer, fromPeer)
        let client = await SFTPClient.speaking(
            to: toPeer.fileHandleForWriting, from: fromPeer.fileHandleForReading,
            answeringWithin: .milliseconds(200))
        defer { try? fromPeer.fileHandleForWriting.close() }

        await #expect(throws: SFTPError.self) {
            _ = try await client.stat("/srv/late")
        }

        // The first request a client sends carries id 1, and this is its
        // answer, arriving long after anybody wanted it. Written through the
        // descriptor rather than the handle for the reason every write here
        // is: a `FileHandle` raises where this returns.
        var body = SFTP.Writer()
        body.uint32(1)
        body.uint32(SFTP.Status.ok.rawValue)
        try SFTPClient.writeAll(
            SFTP.Writer.packet(.status, body.bytes),
            to: fromPeer.fileHandleForWriting.fileDescriptor,
            failing: "the late reply could not be sent")

        var late = 0
        for _ in 0..<100 where late == 0 {
            late = await client.lateReplies
            if late == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(late == 1)
        #expect(await client.strayReplies == 0)
    }

    /// The other side of that distinction, and what `strayReplies` is left
    /// meaning once late ones are taken out of it: an answer to something
    /// nobody ever asked. This one really does say the conversation has lost
    /// its place, which is why it must not be diluted by the ordinary case of
    /// a server that was a moment too slow.
    @Test("a reply to a request nobody made is still a stray")
    func trueStray() async throws {
        let toPeer = Pipe()
        let fromPeer = Pipe()
        SFTPClient.closeOnExec(toPeer, fromPeer)
        let client = await SFTPClient.speaking(
            to: toPeer.fileHandleForWriting, from: fromPeer.fileHandleForReading)
        defer { try? fromPeer.fileHandleForWriting.close() }

        // Nothing has been sent at all, so there is no id this could be the
        // answer to and nothing has been given up on either.
        var body = SFTP.Writer()
        body.uint32(4242)
        body.uint32(SFTP.Status.ok.rawValue)
        try SFTPClient.writeAll(
            SFTP.Writer.packet(.status, body.bytes),
            to: fromPeer.fileHandleForWriting.fileDescriptor,
            failing: "the stray reply could not be sent")

        var strays = 0
        for _ in 0..<100 where strays == 0 {
            strays = await client.strayReplies
            if strays == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(strays == 1)
        #expect(await client.lateReplies == 0)
    }
}
