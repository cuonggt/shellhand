import Foundation
import Testing

@testable import Shellhand

private typealias AppHost = Shellhand.Host

/// The names in ssh's own config reaching the resolver.
///
/// **This is a test about wiring, not about a rule**, which is why it goes
/// through the store rather than calling `Resolver.withAliases` directly.
/// Every piece of this was already built and already tested — the resolver
/// knew what to do with a name, `SSHArgs` knew how to reach a host by one,
/// and `HostDetailView` drew the warning for one that goes elsewhere — and
/// nothing handed the resolver any names, so none of it could happen. A test
/// at the seam would have passed against that. Only one that starts where the
/// app starts, a store on disk, can fail for the reason that was real.
///
/// `.serialized` because these share one config file, and the names are
/// deliberately odd: the file is at the path **every** test in this run
/// resolves against, so a name that collided with another suite's host would
/// change what that suite sees.
@MainActor
@Suite("ssh config names", .serialized)
struct ConfigAliasTests {
    /// Writes a config where this run reads one, and takes it away again.
    ///
    /// Not a path of this file's choosing: it asks the app where it reads, so
    /// that a redirect that stopped working would fail here rather than
    /// quietly sending the test at the real `~/.ssh/config`.
    private func withConfig(_ text: String, _ body: () async -> Void) async {
        let path = SSHConfigFile.pathInUse
        #expect(path != SSHConfigFile.defaultPath, "a run must never read the real ssh config")
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        await body()
    }

    private func store(_ host: AppHost) async -> (HostStore, AppHost) {
        let store = HostStore(dbPath: TestScratch.database())
        await store.refresh()
        await store.save(host)
        return (store, store.snapshot.hosts.first!)
    }

    /// The warning that could not appear. A config entry under this host's
    /// own name that goes to a different machine is reported rather than
    /// used — its settings are not this host's to take, and a `ForwardAgent`
    /// written for it would hand this machine your agent.
    @Test("a config name going elsewhere is reported")
    func elsewhereIsReported() async {
        await withConfig("Host probe-elsewhere\n  HostName 203.0.113.99\n") {
            let (_, host) = await store(AppHost(name: "probe-elsewhere", addr: "10.0.0.1"))
            #expect(host.effective.aliasElsewhere?.addr == "203.0.113.99")
        }
    }

    /// The other half of the same wiring, and it is not the same assertion:
    /// a name for the **same** machine is used rather than reported, so ssh is
    /// handed that name and the block written under it applies. `HostName`
    /// pins the address, so the alias decides which settings apply and never
    /// which machine is reached.
    @Test("a config name for the same machine is used, not reported")
    func sameMachineIsUsed() async {
        await withConfig("Host probe-same\n  HostName 10.0.0.7\n") {
            let (store, host) = await store(AppHost(name: "probe-same", addr: "10.0.0.7"))
            #expect(host.effective.aliasElsewhere == nil)
            let argv = await store.sshArgs(for: host) ?? []
            #expect(argv.contains("HostName=10.0.0.7"))
            #expect(argv.last == "probe-same")
        }
    }

    /// What a **real** launch reads, pinned without reading it.
    ///
    /// Every other test here runs with the path redirected, so all of them
    /// would go on passing if the unredirected branch were changed to point
    /// anywhere — and the feature would be inert again, which is the exact
    /// bug this whole suite exists to have fixed. The suite cannot prove the
    /// app reads the user's own config without reading it, so this pins the
    /// one thing it can: the other branch still names that file.
    @Test("a run that is not a test reads ssh's own config")
    func theRealPath() {
        #expect(SSHConfigFile.defaultPath.hasPrefix("/"))
        #expect(SSHConfigFile.defaultPath.hasSuffix("/.ssh/config"))
        #expect(TestRun.active, "this is a test run, so the redirect must be on")
        #expect(SSHConfigFile.pathInUse == TestRun.sshConfig)
    }

    /// The control, and the one that keeps the wiring from inventing things:
    /// a host the config has never heard of is reached exactly as before.
    @Test("a host the config does not name is untouched")
    func unnamedIsUntouched() async {
        await withConfig("Host somebody-else\n  HostName 203.0.113.1\n") {
            let (store, host) = await store(AppHost(name: "probe-unknown", addr: "10.0.0.9"))
            #expect(host.effective.aliasElsewhere == nil)
            let argv = await store.sshArgs(for: host) ?? []
            #expect(argv.last == "10.0.0.9")
            #expect(!argv.contains { $0.hasPrefix("HostName=") })
        }
    }
}
