import Foundation
import Testing

@testable import Shellhand

private typealias AppHost = Shellhand.Host

/// What ssh's own config adds to a host: the name it gives a machine, and
/// what it would send a connection through.
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
@Suite("what ssh's own config adds", .serialized)
struct SSHConfigReachTests {
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
    // MARK: what it sends a host through

    /// **The row that said the opposite of the truth.** With nothing set on
    /// the host, a config entry matching where it is going really does route
    /// the connection — ssh applies it itself — and the inspector showed
    /// "Jump host: —". Matched here by **address**, which is the case that
    /// cannot be answered by name: `Host 198.51.100.*` catches a host reached
    /// by its address as surely as a block catches one reached by its name.
    @Test("a jump the config gives an address is reported")
    func proxiedByAddress() async {
        await withConfig("Host 198.51.100.*\n  ProxyJump bastion.example\n") {
            let (_, host) = await store(AppHost(name: "probe-addr", addr: "198.51.100.7"))
            #expect(host.effective.configProxy == "bastion.example")
        }
    }

    /// The other way a block is matched, and the subtlety this test got
    /// wrong first time round.
    ///
    /// A block is only reached by name when **ssh is handed that name**, and
    /// ssh is handed the address unless the alias was adopted — which happens
    /// only when the config's entry points at this same machine. So the
    /// `HostName` here is not decoration: without it the entry names a
    /// different machine, the alias is refused as `aliasElsewhere`, ssh gets
    /// `10.0.0.30`, and `Host probe-named` never applies. The first version
    /// of this test left it out and failed, correctly.
    @Test("a jump the config gives a name it also reaches is reported")
    func proxiedByName() async {
        let config = """
            Host probe-named
              HostName 10.0.0.30
              ProxyJump gateway.example

            """
        await withConfig(config) {
            let (_, host) = await store(AppHost(name: "probe-named", addr: "10.0.0.30"))
            #expect(host.effective.configProxy == "gateway.example")
        }
    }

    /// **The control that matters.** A jump of the host's own goes on the
    /// command line, which ssh reads first and keeps — so the config's is not
    /// what happens and must not be reported. A wiring that reported the
    /// config's unconditionally would pass both tests above and tell every
    /// host with a jump of its own the wrong thing.
    @Test("a host with its own jump is not told the config's")
    func ownJumpWins() async {
        await withConfig("Host 198.51.100.*\n  ProxyJump bastion.example\n") {
            var own = AppHost(name: "probe-own", addr: "198.51.100.8")
            own.proxyJump = "chosen.example"
            let (_, host) = await store(own)
            #expect(host.effective.configProxy == "")
            #expect(host.effective.proxyJump == "chosen.example")
        }
    }

    /// `ProxyJump none` is how a config says "and this one goes straight
    /// there", usually under a glob that would otherwise catch it. Reporting
    /// the literal word as a jump host would be worse than reporting nothing.
    @Test("ProxyJump none is no jump")
    func noneIsNothing() async {
        await withConfig("Host probe-none\n  ProxyJump none\n") {
            let (_, host) = await store(AppHost(name: "probe-none", addr: "10.0.0.31"))
            #expect(host.effective.configProxy == "")
        }
    }

    @Test("a host the config does not match goes straight there")
    func notMatched() async {
        await withConfig("Host 203.0.113.*\n  ProxyJump bastion.example\n") {
            let (_, host) = await store(AppHost(name: "probe-direct", addr: "10.0.0.32"))
            #expect(host.effective.configProxy == "")
        }
    }
    // MARK: which one the inspector shows

    /// The row itself, as a rule rather than through a window.
    ///
    /// This is the half that would otherwise go unchecked — the resolver
    /// tests above prove `configProxy` is worked out, and nothing but this
    /// proves the inspector shows it, or that it still prefers the host's own
    /// when there is one. A decision left inside the view could only be
    /// checked by driving the view, which in this app cannot be done.
    @Test("the jump host row prefers the host's own and falls back to the config's")
    func whichJumpIsShown() {
        var e = Effective()
        #expect(e.jumpHost.value == "")
        #expect(e.jumpHost.from == "")

        e.configProxy = "bastion.example"
        #expect(e.jumpHost.value == "bastion.example")
        #expect(e.jumpHost.from == "your ssh config")

        e.proxyJump = "chosen.example"
        e.proxyJumpFrom = "Production"
        #expect(e.jumpHost.value == "chosen.example")
        #expect(e.jumpHost.from == "Production")
    }
}
