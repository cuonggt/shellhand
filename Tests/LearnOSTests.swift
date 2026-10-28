import Foundation
import Testing

@testable import Shellhand

private typealias AppHost = Shellhand.Host

/// Asking a real host what it is, over a real `ssh`.
///
/// **This is the wiring, and it was the one piece with nothing on it.** The
/// read has its own tests against OpenSSH's own server, the parsing has
/// eleven, the field round-trips through the store and the schedule is
/// checked to the hour — and `Core.osOf`, which connects, reads and parses in
/// one breath, had none, because testing it means connecting to something.
/// Every part proven and the join unproven is the shape this project keeps
/// finding; here it is one layer up from the usual.
///
/// It connects to macOS's own `sshd`, started for this test on a loopback
/// port with keys made in `TestScratch`, and **off the user's `~/.ssh`** the
/// way every connection in this suite is: `osOf` takes the same `fixed`
/// settings `connect` does, and they lead.
@Suite("asking a host over ssh", .timeLimit(.minutes(1)))
nonisolated struct LearnOSTests {
    private let ubuntu = """
        PRETTY_NAME="Ubuntu 22.04.3 LTS"
        NAME="Ubuntu"
        ID=ubuntu
        ID_LIKE=debian

        """

    /// A store holding one host pointing at `server`, and that host's id.
    @MainActor
    private func store(for server: LocalSSHD) async -> (String, String) {
        let store = HostStore(dbPath: TestScratch.database("learn-os.sqlite"))
        await store.refresh()
        var host = AppHost(name: "local-sshd", addr: "127.0.0.1", port: server.port)
        host.user = server.user
        host.identity = server.clientKey
        let saved = await store.save(host)
        return (store.dbPath, saved?.id ?? "")
    }

    @Test("a host says what it is, and it is read back whole")
    func readsOverSSH() async throws {
        let server = try LocalSSHD()
        defer { server.stop() }
        let file = try LocalSSHD.settled(TestScratch.directory("os-release")) + "/os-release"
        try ubuntu.write(toFile: file, atomically: true, encoding: .utf8)

        let (db, id) = await store(for: server)
        let said = await Core.shared.osOf(
            db: db, hostID: id, path: file, fixed: server.isolation())

        #expect(said?.id == "ubuntu")
        #expect(said?.name == "Ubuntu 22.04.3 LTS")
    }

    /// Every way of not finding out is the same answer, and the icon that
    /// follows from it is the one most hosts show anyway — so none of these
    /// is worth a word to anybody.
    @Test("a file that is not there is simply not an answer")
    func noSuchFile() async throws {
        let server = try LocalSSHD()
        defer { server.stop() }
        let (db, id) = await store(for: server)
        let said = await Core.shared.osOf(
            db: db, hostID: id,
            path: TestScratch.directory("nothing") + "/os-release",
            fixed: server.isolation())
        #expect(said == nil)
    }

    /// A file that is there and says nothing this understands. The id is what
    /// a mark is found by, so a file without one is not an answer either —
    /// a host labelled and undrawn would be worse than one left alone.
    @Test("a file with no ID is not an answer either")
    func noID() async throws {
        let server = try LocalSSHD()
        defer { server.stop() }
        let file = try LocalSSHD.settled(TestScratch.directory("os-nameless")) + "/os-release"
        try "PRETTY_NAME=\"Something\"\n".write(toFile: file, atomically: true, encoding: .utf8)

        let (db, id) = await store(for: server)
        let said = await Core.shared.osOf(
            db: db, hostID: id, path: file, fixed: server.isolation())
        #expect(said == nil)
    }

    /// **The failure that matters most**, because it is the common one: a
    /// host that refuses. It has to come back nil rather than throwing or
    /// waiting, since this runs behind a session somebody is already using.
    @Test("a host that will not have us is not an answer")
    func refused() async throws {
        // **A server is started only for its isolation.** ssh reads
        // `~/.ssh/config` before it connects to anything, so a connection
        // made without `fixed` would take whatever is written there — a
        // `Host *` with a `ProxyCommand` would run somebody's program on the
        // way to a port that was never going to answer. Nothing in this
        // suite connects without it, refusals included.
        let server = try LocalSSHD()
        defer { server.stop() }
        let store = await MainActor.run {
            HostStore(dbPath: TestScratch.database("refused.sqlite"))
        }
        await store.refresh()
        // Port 1 refuses at once and reaches nothing, which is the rule this
        // suite already uses for driving Quick Connect.
        let saved = await store.save(AppHost(name: "nowhere", addr: "127.0.0.1", port: 1))
        let said = await Core.shared.osOf(
            db: store.dbPath, hostID: saved?.id ?? "",
            path: "/etc/os-release", fixed: server.isolation())
        #expect(said == nil)
    }
}
