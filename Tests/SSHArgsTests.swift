import Testing
@testable import Shellhand

/// The command line, which is the one thing in the port that has to come out
/// byte for byte as it did: everything connects through it.
@Suite("Argv", .serialized)
nonisolated struct SSHArgsTests {
    private func clean() { SSHArgs.setGlobalOptions([]) }

    private func host(
        _ addr: String, port: Int = 0, user: String = "", identity: String = "",
        alias: String = "", name: String = "web"
    ) -> Resolved {
        Resolved(
            host: Host(name: name, addr: addr, port: port), user: user, identity: identity,
            alias: alias)
    }

    @Test("the plainest connection is the address and nothing else")
    func plain() {
        clean()
        #expect(SSHArgs.build(host("10.0.0.1")) == ["10.0.0.1"])
    }

    @Test("a user becomes user@addr rather than -l")
    func user() {
        clean()
        #expect(SSHArgs.build(host("10.0.0.1", user: "deploy")) == ["deploy@10.0.0.1"])
    }

    @Test("a port is passed only when it is not ssh's own")
    func port() {
        clean()
        #expect(SSHArgs.build(host("10.0.0.1", port: 0)) == ["10.0.0.1"])
        #expect(SSHArgs.build(host("10.0.0.1", port: 22)) == ["10.0.0.1"])
        #expect(SSHArgs.build(host("10.0.0.1", port: 2222)) == ["-p", "2222", "10.0.0.1"])
    }

    @Test("a key becomes -i")
    func identity() {
        clean()
        #expect(SSHArgs.build(host("10.0.0.1", identity: "/keys/id"))
            == ["-i", "/keys/id", "10.0.0.1"])
    }

    @Test("the options given to the app lead, because ssh keeps the first it sees")
    func globalOptionsLead() {
        SSHArgs.setGlobalOptions(["IdentitiesOnly=yes", "ServerAliveInterval=30"])
        defer { clean() }
        #expect(SSHArgs.build(host("10.0.0.1", port: 2222, identity: "/keys/id")) == [
            "-o", "IdentitiesOnly=yes", "-o", "ServerAliveInterval=30",
            "-p", "2222", "-i", "/keys/id", "10.0.0.1",
        ])
    }

    @Test("what the caller cannot let be overridden comes before even those")
    func fixedLeads() {
        SSHArgs.setGlobalOptions(["BatchMode=no"])
        defer { clean() }
        let args = SSHArgs.build(host("10.0.0.1"), fixed: ["-o", "BatchMode=yes"])
        #expect(args == ["-o", "BatchMode=yes", "-o", "BatchMode=no", "10.0.0.1"])
    }

    @Test("the line the window shows is the line that was shipped")
    func golden() {
        SSHArgs.setGlobalOptions([
            "UserKnownHostsFile=/tmp/shellhand-check/known_hosts.uicheck",
            "IdentitiesOnly=yes",
        ])
        defer { clean() }
        let resolved = host(
            "127.0.0.1", port: 42222, user: "spike", identity: "/tmp/shellhand-check/id_spike",
            name: "demoserver")
        #expect((["ssh"] + SSHArgs.build(resolved)).joined(separator: " ")
            == "ssh -o UserKnownHostsFile=/tmp/shellhand-check/known_hosts.uicheck"
            + " -o IdentitiesOnly=yes -p 42222 -i /tmp/shellhand-check/id_spike spike@127.0.0.1")
    }

    // MARK: jump hosts

    @Test("a hop is spelled out, with its own port and key, reaching this host's address")
    func oneHop() {
        clean()
        var resolved = host("10.0.1.5", port: 2200, user: "app")
        resolved.jumps = [Hop(
            name: "bastion", addr: "10.0.0.9", port: 2222, user: "jump",
            identity: "/keys/jump")]
        let args = SSHArgs.build(resolved)
        #expect(args == [
            "-p", "2200",
            "-o", "ProxyCommand=ssh -p 2222 -i /keys/jump -W '[10.0.1.5]:2200' jump@10.0.0.9",
            "app@10.0.1.5",
        ])
    }

    @Test("each hop reaches the next, not the far end")
    func twoHops() {
        clean()
        var resolved = host("10.0.2.5")
        resolved.jumps = [
            Hop(name: "inner", addr: "10.0.1.9"),
            Hop(name: "outer", addr: "10.0.0.9"),
        ]
        let args = SSHArgs.build(resolved)
        let proxy = args.first { $0.hasPrefix("ProxyCommand=") }
        // The first hop is reached through the second, and dials only the
        // address of the host that named it.
        #expect(proxy == "ProxyCommand=ssh -o 'ProxyCommand=ssh -W '\"'\"'[10.0.1.9]:22'\"'\"' "
            + "10.0.0.9' -W '[10.0.2.5]:22' 10.0.1.9")
    }

    @Test("a jump host that is not one of yours is handed to ssh as it was written")
    func rawJump() {
        clean()
        var resolved = host("10.0.1.5")
        resolved.proxyJump = "someone@elsewhere.net"
        #expect(SSHArgs.build(resolved) == ["-J", "someone@elsewhere.net", "10.0.1.5"])
    }

    @Test("settings that must hold are carried down to every hop")
    func fixedReachesHops() {
        clean()
        var resolved = host("10.0.1.5")
        resolved.jumps = [Hop(name: "bastion", addr: "10.0.0.9")]
        let args = SSHArgs.build(resolved, fixed: ["-o", "BatchMode=yes"])
        #expect(args.first == "-o")
        #expect(args.contains { $0.contains("ProxyCommand=ssh -o BatchMode=yes -W") })
    }

    // MARK: the name ssh's own config knows

    @Test("a config name is used for the destination, with HostName pinning the machine")
    func alias() {
        clean()
        let args = SSHArgs.build(host("10.0.0.1", user: "deploy", alias: "web"))
        #expect(args == ["-o", "HostName=10.0.0.1", "deploy@web"])
    }

    @Test("a name that is the address adds nothing")
    func aliasIsAddress() {
        clean()
        #expect(SSHArgs.build(host("10.0.0.1", alias: "10.0.0.1")) == ["10.0.0.1"])
    }

    @Test("a percent in an address is doubled, because ssh expands tokens in HostName")
    func aliasPercent() {
        clean()
        let args = SSHArgs.build(host("fe80::1%en0", alias: "linklocal"))
        #expect(args == ["-o", "HostName=fe80::1%%en0", "linklocal"])
    }

    // MARK: subsystems, quoting, and what ssh will take

    @Test("a subsystem goes where a remote command would")
    func subsystem() {
        clean()
        let args = SSHArgs.subsystem(host("10.0.0.1"), "sftp", fixed: ["-o", "BatchMode=yes"])
        #expect(args == ["-o", "BatchMode=yes", "-s", "10.0.0.1", "sftp"])
    }

    @Test("quoting leaves plain arguments alone and wraps anything a shell would act on")
    func quoting() {
        #expect(SSHArgs.shellQuote("10.0.0.1") == "10.0.0.1")
        #expect(SSHArgs.shellQuote("/keys/id_rsa") == "/keys/id_rsa")
        #expect(SSHArgs.shellQuote("[%h]:%p") == "'[%h]:%p'")
        #expect(SSHArgs.shellQuote("/keys/my key") == "'/keys/my key'")
        #expect(SSHArgs.shellQuote("it's") == "'it'\"'\"'s'")
        #expect(SSHArgs.shellQuote("") == "''")
    }

    @Test("an option with no value is refused, and a real one is not")
    func optionProblems() {
        #expect(SSHArgs.optionProblem("BatchMode=yes") == nil)
        #expect(SSHArgs.optionProblem("BatchMode yes") == nil)
        #expect(SSHArgs.optionProblem("SetEnv FOO=bar") == nil)
        #expect(SSHArgs.optionProblem("BatchMode") == "has no value")
        #expect(SSHArgs.optionProblem("BatchMode=") == "has no value")
        #expect(SSHArgs.optionProblem("") == "is empty")
        #expect(SSHArgs.optionProblem("=yes")?.isEmpty == false)
    }

    @Test("a connection nobody is watching never waits at a prompt")
    func unattended() {
        #expect(SSHArgs.unattended == ["-o", "BatchMode=yes"])
    }
}

@Suite("Config")
nonisolated struct ConfigTests {
    @Test("a file that is not there is a config that sets nothing")
    func missing() throws {
        #expect(try Config.load(path: "/nowhere/shellhand/config.yaml").sshOptions.isEmpty)
    }

    @Test("empty, or only comments, is also a config that sets nothing")
    func empty() throws {
        #expect(try Config.parse("").sshOptions.isEmpty)
        #expect(try Config.parse("# nothing here\n").sshOptions.isEmpty)
    }

    @Test("ssh options are read in the order they are written")
    func options() throws {
        let config = try Config.parse("""
            ssh_options:
              - ServerAliveInterval=30
              - IdentitiesOnly=yes
            """)
        #expect(config.sshOptions == ["ServerAliveInterval=30", "IdentitiesOnly=yes"])
    }

    @Test("a key that is not a setting is an error, not something to skip past")
    func unknownKey() {
        #expect(throws: ConfigError.self) { try Config.parse("ssh_option:\n  - BatchMode=yes\n") }
    }

    @Test("an option ssh would refuse is refused here, where it can be read")
    func badOption() {
        #expect(throws: ConfigError.self) { try Config.parse("ssh_options:\n  - BatchMode\n") }
    }

    @Test("a second document would be skipped silently, so it is an error")
    func twoDocuments() {
        #expect(throws: ConfigError.self) {
            try Config.parse("ssh_options: []\n---\nssh_options:\n  - BatchMode=yes\n")
        }
    }

    /// An unclosed quote used to read as no documents at all, so a config
    /// with one sets nothing and says nothing — see `YAMLDocuments`.
    @Test("a file that is not YAML is an error, not a config that sets nothing")
    func notYAML() {
        let error = #expect(throws: ConfigError.self) {
            try Config.parse("ssh_options:\n  - \"ServerAliveInterval=30\n")
        }
        #expect(error?.message.contains("line 2") == true, "the error does not say where")
    }

    @Test("a second document that is not YAML is an error too, not one dropped")
    func secondDocumentNotYAML() {
        #expect(throws: ConfigError.self) {
            try Config.parse("ssh_options: []\n---\nssh_options:\n  - \"BatchMode=yes\n")
        }
    }
}

@Suite("Per-host options", .serialized)
nonisolated struct HostOptionsTests {
    private func clean() { SSHArgs.setGlobalOptions([]) }

    @Test("a host's own options beat the ones every connection gets")
    func ownBeforeGlobal() {
        SSHArgs.setGlobalOptions(["ServerAliveInterval=30"])
        defer { clean() }
        var resolved = Resolved(host: Host(name: "web", addr: "10.0.0.1"))
        resolved.sshOptions = ["ServerAliveInterval=5"]
        let args = SSHArgs.build(resolved)
        // ssh keeps the first value it sees, so the host's has to come first.
        let first = args.firstIndex(of: "ServerAliveInterval=5")
        let second = args.firstIndex(of: "ServerAliveInterval=30")
        #expect(first != nil && second != nil && first! < second!)
    }

    @Test("agent forwarding is said plainly, either way")
    func agentForwarding() {
        clean()
        var resolved = Resolved(host: Host(name: "web", addr: "10.0.0.1"))
        #expect(!SSHArgs.build(resolved).contains { $0.hasPrefix("ForwardAgent") })

        resolved.forwardAgent = true
        #expect(SSHArgs.build(resolved).contains("ForwardAgent=yes"))
        resolved.forwardAgent = false
        #expect(SSHArgs.build(resolved).contains("ForwardAgent=no"))
    }

    @Test("a hop carries its own settings, to the ssh that reaches it")
    func hopsCarryTheirOwn() {
        clean()
        var resolved = Resolved(host: Host(name: "web", addr: "10.0.1.5"))
        resolved.jumps = [Hop(
            name: "bastion", addr: "10.0.0.9", options: ["Compression=yes"],
            forwardAgent: true)]
        let proxy = SSHArgs.build(resolved).first { $0.hasPrefix("ProxyCommand=") } ?? ""
        #expect(proxy.contains("ForwardAgent=yes"))
        #expect(proxy.contains("Compression=yes"))
    }
}

@Suite("Options through the groups")
nonisolated struct OptionInheritanceTests {
    private var groups: [Group] {
        [
            Group(id: "p", name: "Production", sshOptions: ["ServerAliveInterval=30"],
                  forwardAgent: true),
            Group(id: "e", name: "EU", parentId: "p", sshOptions: ["Compression=yes"]),
        ]
    }

    private func resolve(_ host: Host) -> Resolved {
        Resolver(groups: groups, hosts: [host]).resolve(host)
    }

    @Test("a host's own come first, then each group going up")
    func nearestFirst() {
        let host = Host(id: "h", name: "web", addr: "10.0.0.1", groupId: "e",
                        sshOptions: ["LogLevel=DEBUG"])
        #expect(resolve(host).sshOptions
            == ["LogLevel=DEBUG", "Compression=yes", "ServerAliveInterval=30"])
    }

    @Test("a host with none of its own still takes what the groups give")
    func fromGroupsAlone() {
        let host = Host(id: "h", name: "web", addr: "10.0.0.1", groupId: "e")
        #expect(resolve(host).sshOptions == ["Compression=yes", "ServerAliveInterval=30"])
    }

    @Test("the nearest thing that mentions the agent decides, and says so")
    func agentFromNearest() {
        let host = Host(id: "h", name: "web", addr: "10.0.0.1", groupId: "e")
        let resolved = resolve(host)
        #expect(resolved.forwardAgent == true)
        #expect(resolved.forwardAgentFrom == "Production")
    }

    @Test("a host can turn off what its group turned on")
    func hostOverridesGroup() {
        let host = Host(id: "h", name: "web", addr: "10.0.0.1", groupId: "e",
                        forwardAgent: false)
        let resolved = resolve(host)
        #expect(resolved.forwardAgent == false)
        // Its own, so nothing is credited to a group.
        #expect(resolved.forwardAgentFrom == "")
    }

    @Test("nothing anywhere leaves it unsaid, rather than guessed")
    func unsaid() {
        let lone = Host(id: "h", name: "web", addr: "10.0.0.1")
        #expect(Resolver(groups: [], hosts: [lone]).resolve(lone).forwardAgent == nil)
    }
}
