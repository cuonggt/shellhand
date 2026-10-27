import Foundation
import Testing

@testable import Shellhand

/// Twenty thousand conversations in a row, and nothing left behind.
///
/// This began as a hunt for the stall that had haunted the suite for weeks —
/// sixteen minutes once, five sightings, no explanation — and it is a check
/// now because the hunt finished. It runs the minimal conversation over and
/// over with a deadline of its own on each, so that a stall is a caught error
/// rather than a hung run.
///
/// **The bug it guards against was in this harness, not in the engine.**
/// `ScriptedSFTP`'s reader thread borrowed the pipe's read descriptor by
/// number, and a thread can hold nothing else; churn thousands of
/// conversations and the `FileHandle` owning that number is deallocated while
/// the thread is still parked in `read`, so the number is reissued and an
/// orphan reads somebody else's pipe. That is why bytes went missing in
/// **both** directions, which no fault in one side's logic could do.
///
/// Measured both ways round, which is the only reason to believe it: with the
/// harness borrowing, 11 stalls in 80,000 conversations; with it holding a
/// `dup` of its own, 0 in 100,000. The engine's own `dup` made no difference
/// to this at all — see `CLAUDE.md` for the table.
@Suite("SFTP churn", .timeLimit(.minutes(5)))
nonisolated struct SFTPChurnTests {
    @Test("twenty thousand conversations leave nothing behind")
    func manyAtOnce() async throws {
        let rounds = 20_000
        let width = 16
        let started = Date()

        let trouble = await withTaskGroup(of: String?.self) { group -> [String] in
            var sent = 0
            var found: [String] = []
            func launch(_ i: Int) {
                group.addTask {
                    let server = ScriptedSFTP(directory: [["alpha", "beta"]])
                    let client = await server.client(answeringWithin: .seconds(5))
                    defer { server.stop() }
                    do {
                        let entries = try await client.list("/srv")
                        return entries.map(\.name) == ["alpha", "beta"]
                            ? nil : "#\(i) wrong entries: \(entries.map(\.name))"
                    } catch let error as SFTPError {
                        // The grace is for a reply still in flight; the
                        // counters are the whole point of catching this.
                        try? await Task.sleep(for: .milliseconds(500))
                        return """
                            #\(i) \(error.message) \
                            late=\(await client.lateReplies) \
                            strays=\(await client.strayReplies) \
                            serverReader=\(server.readerStopped ?? "still reading") \
                            saw=\(server.packetsSeen) sent=\(server.repliesSent) \
                            writeTrouble=\(server.writeTrouble ?? "none")
                            """
                    } catch {
                        return "#\(i) \(error)"
                    }
                }
            }
            while sent < width && sent < rounds { sent += 1; launch(sent) }
            while let result = await group.next() {
                if let result { found.append(result) }
                if sent < rounds { sent += 1; launch(sent) }
            }
            return found
        }

        let took = Date().timeIntervalSince(started)
        print("CHURN \(rounds) conversations, \(width) at a time, in \(String(format: "%.1f", took))s, \(trouble.count) trouble")
        if !trouble.isEmpty { Issue.record("\(trouble.count): \(trouble.joined(separator: " | "))") }
    }
}
