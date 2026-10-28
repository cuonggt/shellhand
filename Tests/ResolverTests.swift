import Testing
@testable import Shellhand

/// The inheritance rules, which are the part of the port with the most ways to
/// be subtly wrong: a host's own value beats the nearest group that sets it.
@Suite("Inheritance")
nonisolated struct ResolverTests {
    private func resolver(groups: [Group] = [], hosts: [Host] = []) -> Resolver {
        Resolver(groups: groups, hosts: hosts)
    }

    @Test("a host's own user wins over everything above it")
    func hostWins() {
        let group = Group(id: "g", name: "Production", user: "deploy")
        let host = Host(id: "h", name: "web", addr: "10.0.0.1", user: "root", groupId: "g")
        let out = resolver(groups: [group], hosts: [host]).resolve(host)
        #expect(out.user == "root")
        // Nothing was inherited, so nothing is credited.
        #expect(out.userFrom == "")
    }

    @Test("an empty field comes from the nearest group that sets it, and says so")
    func nearestGroupWins() {
        let parent = Group(id: "p", name: "Production", user: "deploy", identity: "/keys/prod")
        let child = Group(id: "c", name: "EU", parentId: "p", user: "eu-deploy")
        let host = Host(id: "h", name: "web", addr: "10.0.0.1", groupId: "c")
        let out = resolver(groups: [parent, child], hosts: [host]).resolve(host)
        #expect(out.user == "eu-deploy")
        #expect(out.userFrom == "EU")
        // Nothing nearer sets the key, so the grandparent's is used.
        #expect(out.identity == "/keys/prod")
        #expect(out.identityFrom == "Production")
    }

    @Test("a group chain that loops stops rather than spinning")
    func groupLoop() {
        let a = Group(id: "a", name: "A", parentId: "b")
        let b = Group(id: "b", name: "B", parentId: "a", user: "deploy")
        let host = Host(id: "h", name: "web", addr: "10.0.0.1", groupId: "a")
        let out = resolver(groups: [a, b], hosts: [host]).resolve(host)
        #expect(out.user == "deploy")
    }

    // MARK: jump hosts

    @Test("a jump host named by name becomes that host, with its port and key")
    func jumpResolves() {
        let bastion = Host(
            id: "b", name: "bastion", addr: "10.0.0.9", port: 2222, user: "jump",
            identity: "/keys/jump")
        let host = Host(
            id: "h", name: "web", addr: "10.0.1.5", proxyJump: "bastion")
        let out = resolver(hosts: [bastion, host]).resolve(host)
        #expect(out.jumps.count == 1)
        #expect(out.jumps.first?.addr == "10.0.0.9")
        #expect(out.jumps.first?.port == 2222)
        #expect(out.jumps.first?.user == "jump")
        #expect(out.jumps.first?.identity == "/keys/jump")
    }

    @Test("a jump host that is not one of yours is left for ssh")
    func jumpUnknown() {
        let host = Host(id: "h", name: "web", addr: "10.0.1.5", proxyJump: "someone@elsewhere.net")
        let out = resolver(hosts: [host]).resolve(host)
        #expect(out.jumps.isEmpty)
        #expect(out.proxyJump == "someone@elsewhere.net")
    }

    @Test("a jump host reached through itself stops the chain")
    func jumpLoop() {
        let a = Host(id: "a", name: "a", addr: "10.0.0.1", proxyJump: "b")
        let b = Host(id: "b", name: "b", addr: "10.0.0.2", proxyJump: "a")
        let out = resolver(hosts: [a, b]).resolve(a)
        #expect(out.jumps.map(\.name) == ["b", "a"])
    }

    @Test("a chain is bounded")
    func jumpBounded() {
        // Twelve hosts, each pointing at the next: longer than the bound.
        var hosts: [Host] = []
        for i in 0..<12 {
            hosts.append(Host(
                id: "h\(i)", name: "h\(i)", addr: "10.0.0.\(i)", proxyJump: "h\(i + 1)"))
        }
        let out = resolver(hosts: hosts).resolve(hosts[0])
        #expect(out.jumps.count == Resolver.maxJumpHops)
    }

    @Test("a hop inherits from its own groups")
    func jumpInherits() {
        let group = Group(id: "g", name: "Production", user: "deploy")
        let bastion = Host(id: "b", name: "bastion", addr: "10.0.0.9", groupId: "g")
        let host = Host(id: "h", name: "web", addr: "10.0.1.5", proxyJump: "bastion")
        let out = resolver(groups: [group], hosts: [bastion, host]).resolve(host)
        #expect(out.jumps.first?.user == "deploy")
    }

    // MARK: what ssh's own config says

    @Test("a config entry under the host's name is used when it goes to the same machine")
    func aliasMatches() {
        let host = Host(id: "h", name: "web", addr: "10.0.0.1")
        let out = resolver(hosts: [host])
            .withAliases([Alias(name: "web", addr: "10.0.0.1", port: 22)])
            .resolve(host)
        #expect(out.alias == "web")
        #expect(out.aliasElsewhere == nil)
        #expect(out.dest == "web")
    }

    @Test("a config entry that goes elsewhere is reported, not used")
    func aliasElsewhere() {
        let host = Host(id: "h", name: "web", addr: "10.0.0.1")
        let out = resolver(hosts: [host])
            .withAliases([Alias(name: "web", addr: "192.168.0.5", port: 22)])
            .resolve(host)
        #expect(out.alias == "")
        #expect(out.aliasElsewhere?.addr == "192.168.0.5")
        // Reached by address, as it always was.
        #expect(out.dest == "10.0.0.1")
    }

    @Test("a port of nothing is a port of 22 on both sides of the comparison")
    func aliasPortDefaults() {
        let host = Host(id: "h", name: "web", addr: "10.0.0.1", port: 0)
        let out = resolver(hosts: [host])
            .withAliases([Alias(name: "web", addr: "10.0.0.1", port: 22)])
            .resolve(host)
        #expect(out.alias == "web")
    }

    @Test("the config's own proxy is ignored once the host names a jump host")
    func configProxyYields() {
        let bastion = Host(id: "b", name: "bastion", addr: "10.0.0.9")
        let host = Host(id: "h", name: "web", addr: "10.0.1.5", proxyJump: "bastion")
        let out = resolver(hosts: [bastion, host])
            .withProxies { _ in .init(jump: "bastion.example") }
            .resolve(host)
        // ssh reads the command line before the file and keeps the first route
        // it is given, so what the file says would never be used.
        #expect(out.configProxy == "")
    }

    @Test("the config's own proxy is asked by the name ssh is handed")
    func configProxyAsked() {
        let host = Host(id: "h", name: "web", addr: "10.0.1.5")
        let out = resolver(hosts: [host])
            .withProxies { dest in
                dest == "10.0.1.5" ? .init(jump: "gateway.example") : .init()
            }
            .resolve(host)
        #expect(out.configProxy == "gateway.example")
    }
}

/// What a group's own editor shows beside each field: the value it would take
/// from above, and whose it is. The sheet used to work this out four times
/// over, once per field, which is how three of the four came to carry slightly
/// different wording for the same answer.
@Suite("What a group takes from above")
nonisolated struct FromAboveTests {
    /// Production › EU › Frankfurt. Production logs in as ubuntu and paints
    /// its hosts Solarized; EU sets a jump host and nothing else.
    private let groups = [
        Group(id: "p", name: "Production", user: "ubuntu", theme: "Solarized"),
        Group(id: "e", name: "EU", parentId: "p", proxyJump: "bastion-eu"),
        Group(id: "f", name: "Frankfurt", parentId: "e"),
    ]

    @Test("the nearest group that sets a value wins, and is named")
    func nearest() {
        let above = FromAbove(of: groups[2], among: groups)
        #expect(above.proxyJump == "bastion-eu")
        #expect(above.proxyJumpFrom == "EU")
        #expect(above.user == "ubuntu")
        #expect(above.userFrom == "Production")
    }

    @Test("a group never reads its own fields, because those are what it sets")
    func notItsOwn() {
        // EU sets the jump host, so what EU takes from above has none.
        let above = FromAbove(of: groups[1], among: groups)
        #expect(above.proxyJump.isEmpty)
        #expect(above.proxyJumpFrom.isEmpty)
        #expect(above.user == "ubuntu")
    }

    @Test("a group at the top takes nothing")
    func atTheTop() {
        let above = FromAbove(of: groups[0], among: groups)
        #expect(above == FromAbove())
    }

    @Test("a palette comes down the chain like everything else")
    func palette() {
        let above = FromAbove(of: groups[2], among: groups)
        #expect(above.theme == "Solarized")
        #expect(above.themeFrom == "Production")
    }

    /// Nothing anywhere above is a third answer, not a no: a host under a
    /// group that carries the agent and a host under one that refuses it are
    /// different, and so is one nobody asked about.
    @Test("the agent has three answers, and nothing said is one of them")
    func agent() {
        var carried = groups
        carried[0].forwardAgent = true
        #expect(FromAbove(of: carried[2], among: carried).forwardAgent == true)
        #expect(FromAbove(of: carried[2], among: carried).forwardAgentFrom == "Production")

        carried[1].forwardAgent = false
        #expect(FromAbove(of: carried[2], among: carried).forwardAgent == false)
        #expect(FromAbove(of: carried[2], among: carried).forwardAgentFrom == "EU")

        #expect(FromAbove(of: groups[2], among: groups).forwardAgent == nil)
    }

    @Test("a group that does not exist yet still takes what its parent gives")
    func newOne() {
        let fresh = Group(name: "Berlin", parentId: "e")
        let above = FromAbove(of: fresh, among: groups)
        #expect(above.proxyJump == "bastion-eu")
        #expect(above.user == "ubuntu")
    }

    @Test("a tree that somehow loops stops rather than hanging")
    func looping() {
        let looped = [
            Group(id: "a", name: "A", parentId: "b", user: "one"),
            Group(id: "b", name: "B", parentId: "a"),
        ]
        #expect(FromAbove(of: looped[1], among: looped).user == "one")
        // Its own value is not taken from above, and the walk ends.
        #expect(FromAbove(of: looped[0], among: looped).user.isEmpty)
    }

    @Test("a parent that is not in the list ends the walk rather than failing")
    func missingParent() {
        let orphan = Group(id: "x", name: "Orphan", parentId: "nowhere")
        #expect(FromAbove(of: orphan, among: groups) == FromAbove())
    }
}
