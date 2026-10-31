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

    /// The import sheet and the welcome read the same file the resolver
    /// does. They read the real one, so a drive that put the import sheet up
    /// on a scratch copy listed its user's own hosts.
    @Test("the import and the welcome start on the run's own config")
    func importStartsHere() async {
        #expect(Core.shared.defaultSSHConfigPath() == SSHConfigFile.pathInUse)
        await withConfig("Host probe-counted\n  HostName 10.0.0.40\n") {
            #expect(Core.shared.sshConfigHosts() == 1)
            let result = try? await Core.shared.importSSHConfig(
                db: TestScratch.database(), dryRun: true)
            #expect(result?.added == 1)
        }
    }

    // MARK: what the run's own ssh reads

    /// ssh reads `~/.ssh/config` by itself, whatever the app reads, so every
    /// ssh a run starts is handed the run's own: the file the resolver reads,
    /// or none where there is no file, since ssh refuses a `-F` it cannot
    /// open.
    @Test("a run's ssh is handed the run's own config, never the user's")
    func sshIsHandedTheRunsConfig() async {
        try? FileManager.default.removeItem(atPath: SSHConfigFile.pathInUse)
        #expect(TestRun.sshFixed == ["-F", "/dev/null"])
        await withConfig("Host probe-fixed\n  HostName 10.0.0.41\n") {
            #expect(TestRun.sshFixed == ["-F", SSHConfigFile.pathInUse])
        }
    }

    /// Into every hop, since a jump is an `ssh` of its own that reads a
    /// config too — and only into what connects: the line the window shows
    /// and Copy gives stays the user's.
    @Test("a session leads with it and carries it into every hop")
    func sessionCarriesIt() async throws {
        try? FileManager.default.removeItem(atPath: SSHConfigFile.pathInUse)
        let db = TestScratch.database()
        let store = HostStore(dbPath: db)
        await store.refresh()
        await store.save(AppHost(name: "probe-hop", addr: "192.0.2.10"))
        let behind = await store.save(
            AppHost(name: "probe-behind", addr: "10.0.0.42", proxyJump: "probe-hop"))!
        let argv = try await Core.shared.connection(db: db, hostID: behind.id).argv
        #expect(Array(argv.prefix(2)) == ["-F", "/dev/null"])
        let hop = argv.first { $0.hasPrefix("ProxyCommand=") } ?? ""
        #expect(hop.hasPrefix("ProxyCommand=ssh -F /dev/null "))
        let shown = await store.sshArgs(for: behind) ?? []
        #expect(!shown.isEmpty && !shown.contains("-F"))
        #expect(!shown.contains { $0.contains(" -F ") })
    }

    /// File sessions too, the run's own leading, so that a caller's own `-F`
    /// — the suite's `-F /dev/null` — comes later and is the one ssh keeps.
    @Test("a file session leads with it, and a caller's own -F comes later")
    func fileSessionCarriesIt() {
        let resolved = Resolved(host: AppHost(name: "probe-files", addr: "10.0.0.43"))
        let args = SFTPClient.arguments(resolved, fixed: ["-F", "callers-own"])
        #expect(Array(args.prefix(2)) == TestRun.sshFixed)
        let last = args.lastIndex(of: "-F").map { args[$0 + 1] }
        #expect(last == "callers-own")
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
    // MARK: a command rather than a jump host

    /// **A `ProxyCommand` is not a jump host**, so it gets a row of its own
    /// rather than being squeezed into one labelled "Jump host" — which
    /// would be a different wrong answer rather than a right one. Before
    /// this it was reported nowhere at all, and a host reached through one
    /// read as going straight there.
    @Test("a proxy command is reported as a command, not as a jump host")
    func proxyCommand() async {
        await withConfig("Host 198.51.100.*\n  ProxyCommand ssh -W %h:%p gateway\n") {
            let (_, host) = await store(AppHost(name: "probe-cmd", addr: "198.51.100.20"))
            #expect(host.effective.configProxyCommand == "ssh -W %h:%p gateway")
            #expect(host.effective.configProxy == "", "a command is not a jump host")
        }
    }

    /// ssh's own rule: *"this option takes precedence over the ProxyCommand
    /// directive if both are specified"*. So a host never shows both, and
    /// nothing above the config has to know the precedence.
    @Test("a jump host wins over a command, as ssh has it")
    func jumpBeatsCommand() async {
        let config = """
            Host 198.51.100.*
              ProxyJump bastion.example
              ProxyCommand ssh -W %h:%p gateway

            """
        await withConfig(config) {
            let (_, host) = await store(AppHost(name: "probe-both", addr: "198.51.100.21"))
            #expect(host.effective.configProxy == "bastion.example")
            #expect(host.effective.configProxyCommand == "")
        }
    }

    @Test("ProxyCommand none is no command")
    func commandNone() async {
        await withConfig("Host probe-nocmd\n  ProxyCommand none\n") {
            let (_, host) = await store(AppHost(name: "probe-nocmd", addr: "10.0.0.40"))
            #expect(host.effective.configProxyCommand == "")
        }
    }
}
