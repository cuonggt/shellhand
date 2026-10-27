import Foundation
import Testing
@testable import Shellhand

/// What a write to a far end that is no longer there comes out as.
///
/// This is the path `send`'s `catch` was always written for and could never
/// reach: through `FileHandle.write(contentsOf:)` a closed or broken handle
/// raises an **ObjC** exception, which no Swift `catch` sees, so the process
/// died where it meant to report. Both halves are here because they fail
/// differently underneath — a closed handle is `EBADF`, while a far end that
/// has gone is `EPIPE` and carries a `SIGPIPE` with it, which would end the
/// process just as surely if it were not ignored.
@Suite("SFTP far end", .timeLimit(.minutes(1)))
nonisolated struct SFTPFarEndTests {
    /// The crash that killed a whole run, in one line: the handle the client
    /// writes to is closed underneath it, which is what a scripted server's
    /// `stop()` does to the close `list` leaves unawaited.
    @Test("a closed handle is an error, not a dead process")
    func closedHandle() async throws {
        let toPeer = Pipe.marked()
        let fromPeer = Pipe.marked()
        let client = await SFTPClient.speaking(
            to: toPeer.fileHandleForWriting, from: fromPeer.fileHandleForReading)
        // Lets the client's reader thread end rather than blocking for ever.
        defer { try? fromPeer.fileHandleForWriting.close() }

        try toPeer.fileHandleForWriting.close()
        await #expect(throws: SFTPError.self) {
            _ = try await client.list("/srv")
        }
    }

    /// The shipped shape: an `sftp` child that dies leaves nothing reading the
    /// pipe, so the next write is a broken one.
    @Test("a far end that has gone is an error, not a dead process")
    func brokenPipe() async throws {
        let toPeer = Pipe.marked()
        let fromPeer = Pipe.marked()
        let client = await SFTPClient.speaking(
            to: toPeer.fileHandleForWriting, from: fromPeer.fileHandleForReading)
        defer { try? fromPeer.fileHandleForWriting.close() }

        try toPeer.fileHandleForReading.close()
        await #expect(throws: SFTPError.self) {
            _ = try await client.list("/srv")
        }
    }

    /// The packets going out to `ssh` and the bytes coming down into a local
    /// file share one write loop, so this pins it once for both. A read-only
    /// descriptor is the failure used rather than a closed one deliberately:
    /// a closed descriptor's number can be handed to something else opening a
    /// file in the same instant, and in a suite this parallel that would make
    /// the write quietly succeed against a stranger's file.
    @Test("a write that cannot land is an error in the caller's own words")
    func writeThatCannotLand() throws {
        let path = TestScratch.directory("write") + "/file"
        FileManager.default.createFile(atPath: path, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let readOnly = try #require(FileHandle(forReadingAtPath: path))
        defer { try? readOnly.close() }

        do {
            try SFTPClient.writeAll(
                Data([1, 2, 3]), to: readOnly.fileDescriptor, failing: "nowhere to put it")
            Issue.record("writing to a descriptor opened for reading should have failed")
        } catch let error as SFTPError {
            #expect(error.message.hasPrefix("nowhere to put it: "))
        }
    }
}
