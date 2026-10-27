import Foundation
import Testing

@testable import Shellhand

/// A reproducer for the stall, kept and **disabled**. It is not a check.
///
/// The stall had been seen five times in ordinary suite runs, never explained,
/// at perhaps one run in several — which is an expensive way to buy one data
/// point. This buys about six in seven seconds, by running the minimal
/// conversation over and over with a short deadline on each so that a stall is
/// a caught error rather than a hung run.
///
/// It is disabled because it fails by design: roughly one conversation in
/// 2,500 stalls, so with 20,000 of them it will essentially always record
/// something. Enable it when there is a theory to test. What it has already
/// established is in `CLAUDE.md`; the short version is that the reply never
/// arrives at all, that it happens to `opendir` as readily as to `readdir`,
/// and that bytes go missing in **both** directions.
///
/// Note what it cannot say: this is `ScriptedSFTP` on a pair of pipes, churned
/// far harder than the app ever churns a session. Whether the shipped path
/// through `ssh` has the same fault is open.
@Suite("SFTP stall hunt", .timeLimit(.minutes(5)))
nonisolated struct SFTPStallHunt {
    @Test(
        "the minimal conversation, many at once",
        .disabled("a reproducer, not a check: about 1 conversation in 2,500 stalls"))
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
        print("STALLHUNT \(rounds) conversations, \(width) at a time, in \(String(format: "%.1f", took))s, \(trouble.count) trouble")
        if !trouble.isEmpty { Issue.record("\(trouble.count): \(trouble.joined(separator: " | "))") }
    }
}
