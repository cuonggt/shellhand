import Testing
@testable import Shellhand

@Suite("Validation")
nonisolated struct ValidationTests {
    private let existing = [
        Host(id: "a", name: "web", addr: "10.0.0.1"),
        Host(id: "b", name: "DB", addr: "10.0.0.2"),
    ]

    @Test("a host needs a name and an address")
    func needs() {
        #expect(Validation.problem(with: Host(addr: "10.0.0.9"), among: []) != nil)
        #expect(Validation.problem(with: Host(name: "new"), among: []) != nil)
        #expect(Validation.problem(with: Host(name: "  ", addr: "10.0.0.9"), among: []) != nil)
        #expect(Validation.problem(with: Host(name: "new", addr: "10.0.0.9"), among: []) == nil)
    }

    @Test("nought is not a port but a way of saying ssh's own")
    func ports() {
        func host(_ port: Int) -> Host { Host(name: "new", addr: "10.0.0.9", port: port) }
        #expect(Validation.problem(with: host(0), among: []) == nil)
        #expect(Validation.problem(with: host(22), among: []) == nil)
        #expect(Validation.problem(with: host(65535), among: []) == nil)
        #expect(Validation.problem(with: host(65536), among: []) != nil)
        #expect(Validation.problem(with: host(-1), among: []) != nil)
    }

    @Test("two hosts cannot share a name, however it is cased")
    func duplicates() {
        #expect(Validation.problem(
            with: Host(id: "c", name: "WEB", addr: "10.0.0.9"), among: existing) != nil)
        #expect(Validation.problem(
            with: Host(id: "c", name: " db ", addr: "10.0.0.9"), among: existing) != nil)
        #expect(Validation.problem(
            with: Host(id: "c", name: "cache", addr: "10.0.0.9"), among: existing) == nil)
    }

    @Test("a host saved under the name it already has is not a clash with itself")
    func itself() {
        #expect(Validation.problem(
            with: Host(id: "a", name: "web", addr: "10.0.0.5"), among: existing) == nil)
    }

    @Test("a host cannot be its own jump host")
    func ownJumpHost() {
        #expect(Validation.problem(
            with: Host(id: "c", name: "edge", addr: "10.0.0.9", proxyJump: "EDGE"),
            among: existing) != nil)
        #expect(Validation.problem(
            with: Host(id: "c", name: "edge", addr: "10.0.0.9", proxyJump: "web"),
            among: existing) == nil)
    }

    /// The editor's example for an empty jump field is never the host's own
    /// name, or bastion's own editor suggests the loop the rule above refuses.
    @Test("the jump field's example is never the host itself")
    func jumpExample() {
        #expect(HostEditorSheet.jumpExample(for: "web") == "bastion")
        #expect(HostEditorSheet.jumpExample(for: " Bastion ") == "gateway")
        #expect(Validation.problem(
            with: Host(id: "c", name: "bastion", addr: "10.0.0.9",
                       proxyJump: HostEditorSheet.jumpExample(for: "bastion")),
            among: existing) == nil)
    }

    @Test("a group needs a name of its own, and cannot be inside itself")
    func groups() {
        let groups = [Group(id: "g", name: "Production")]
        #expect(Validation.problem(with: Group(name: ""), among: groups) != nil)
        #expect(Validation.problem(with: Group(id: "h", name: "production"), among: groups) != nil)
        #expect(Validation.problem(with: Group(id: "h", name: "Staging"), among: groups) == nil)
        #expect(Validation.problem(
            with: Group(id: "h", name: "Staging", parentId: "h"), among: groups) != nil)
    }
}

@Suite("Where a group can go")
nonisolated struct GroupParentTests {
    /// Production › EU › Frankfurt, and a Staging of its own.
    private let groups = [
        Group(id: "p", name: "Production"),
        Group(id: "e", name: "EU", parentId: "p"),
        Group(id: "f", name: "Frankfurt", parentId: "e"),
        Group(id: "s", name: "Staging"),
    ]

    @Test("a group is never offered itself")
    func notItself() {
        let offered = Validation.possibleParents(for: groups[0], among: groups).map(\.id)
        #expect(!offered.contains("p"))
    }

    @Test("nor anything already beneath it, however deep")
    func notItsOwnChildren() {
        let offered = Validation.possibleParents(for: groups[0], among: groups).map(\.id)
        #expect(offered == ["s"])
    }

    @Test("a group deeper in can still move anywhere above it")
    func deeperOne() {
        let offered = Validation.possibleParents(for: groups[2], among: groups).map(\.id).sorted()
        #expect(offered == ["e", "p", "s"])
    }

    @Test("a group that does not exist yet can go anywhere")
    func newOne() {
        let offered = Validation.possibleParents(for: Group(name: "New"), among: groups)
        #expect(offered.count == groups.count)
    }

    @Test("a tree that somehow loops does not hang the walk")
    func looping() {
        let looped = [
            Group(id: "a", name: "A", parentId: "b"),
            Group(id: "b", name: "B", parentId: "a"),
            Group(id: "c", name: "C"),
        ]
        let offered = Validation.possibleParents(for: looped[0], among: looped).map(\.id)
        #expect(offered == ["c"])
    }
}

@Suite("What deleting takes with it")
nonisolated struct DeletionWarningTests {
    private let host = Host(id: "h", name: "web", addr: "10.0.0.1")

    @Test("a host with no rules says only that it cannot be undone")
    func noRules() {
        #expect(Validation.deletionWarning(for: host) == "This cannot be undone.")
    }

    /// Their jump field names it, and once it is gone ssh is left to find a
    /// machine by that name on its own — which deleting never said.
    @Test("a host others jump through says how many, and that ssh is left the name")
    func jumpedThrough() {
        let bastion = Host(id: "b", name: "bastion", addr: "192.0.2.10")
        let hosts = [
            bastion,
            Host(id: "1", name: "db-01", addr: "10.0.0.1", proxyJump: "bastion"),
            Host(id: "2", name: "db-02", addr: "10.0.0.2", proxyJump: "BASTION"),
            Host(id: "3", name: "web", addr: "10.0.0.3", proxyJump: "edge"),
        ]
        let groups = [Group(id: "p", name: "Production", proxyJump: "bastion"), Group(id: "s", name: "Staging")]
        let said = Validation.deletionWarning(for: bastion, hosts: hosts, groups: groups)
        #expect(said.hasPrefix("bastion is the jump host for 2 hosts and the group Production."))
        #expect(said.contains("find a machine called bastion by itself"))
        #expect(said.hasSuffix("This cannot be undone."))
        // One that nothing goes through is as before.
        #expect(Validation.deletionWarning(for: hosts[3], hosts: hosts, groups: groups)
            == "This cannot be undone.")
    }

    /// A group's jump host is every host's beneath it that names none of its
    /// own, which `effective` says: "the jump host for 2 groups" said
    /// nothing of the six hosts in them.
    @Test("hosts that have it from a group are counted, and the groups named")
    func jumpedThroughFromAbove() {
        let bastion = Host(id: "b", name: "bastion", addr: "192.0.2.10")
        var inherits = Host(id: "1", name: "api-eu-1", addr: "198.51.100.21", groupId: "e")
        inherits.effective.proxyJump = "bastion"
        var ownWay = Host(id: "2", name: "db-01", addr: "192.0.2.21", proxyJump: "edge", groupId: "u")
        ownWay.effective.proxyJump = "edge"
        let groups = [
            Group(id: "u", name: "US", proxyJump: "bastion"),
            Group(id: "e", name: "EU", proxyJump: "bastion"),
        ]
        #expect(Validation.deletionWarning(for: bastion, hosts: [bastion, inherits, ownWay], groups: groups)
            .hasPrefix("bastion is the jump host for 1 host and the groups EU and US."))
        let more = groups + [
            Group(id: "a", name: "Asia", proxyJump: "bastion"),
            Group(id: "o", name: "Oceania", proxyJump: "Bastion"),
        ]
        #expect(Validation.deletionWarning(for: bastion, groups: Array(more.prefix(3)))
            .hasPrefix("bastion is the jump host for the groups Asia, EU and US."))
        #expect(Validation.deletionWarning(for: bastion, groups: more)
            .hasPrefix("bastion is the jump host for 4 groups."))
    }

    // Production › EU, with two hosts in EU and one in Production.
    private var groups: [Group] {
        [Group(id: "p", name: "Production"), Group(id: "e", name: "EU", parentId: "p")]
    }

    private var hosts: [Host] {
        [
            Host(id: "a", name: "a", addr: "10.0.0.1", groupId: "p"),
            Host(id: "b", name: "b", addr: "10.0.0.2", groupId: "e"),
            Host(id: "c", name: "c", addr: "10.0.0.3", groupId: "e"),
        ]
    }

    @Test("an empty group says nothing is filed under it")
    func emptyGroup() {
        let said = Validation.deletionWarning(
            for: Group(id: "x", name: "Empty"), groups: [Group(id: "x", name: "Empty")],
            hosts: [])
        #expect(said == "Nothing is filed under it. This cannot be undone.")
    }

    /// What moves is what the store moves: the host filed in it, and the
    /// group inside it with its own two, which stay in it. It said all three
    /// moved to the top of the list.
    @Test("a group says what moves: its own hosts, and the groups inside with theirs")
    func saysWhatMoves() {
        let said = Validation.deletionWarning(
            for: groups[0], groups: groups, hosts: hosts)
        #expect(said == "Its one host moves to the top of the list, and so does the group "
            + "inside it, with its 2 hosts. Nothing is deleted but the group itself.")
        // Nothing filed in it directly, only a group inside.
        let onlyInside = Validation.deletionWarning(
            for: groups[0], groups: groups, hosts: Array(hosts.dropFirst()))
        #expect(onlyInside.hasPrefix("The group inside it moves to the top of the list, with its 2 hosts."))
    }

    /// Deleting Production took the user, the key and the palette from
    /// every host beneath it, and the question never said so.
    @Test("a group says that what it gives the hosts beneath it goes with it")
    func saysWhatItGives() {
        var production = Group(id: "p", name: "Production", user: "deploy", identity: "~/.ssh/id_ed25519")
        production.theme = "Nord"
        let said = Validation.deletionWarning(
            for: production, groups: [production, groups[1]], hosts: hosts)
        #expect(said.contains("The user, the key and the palette it gives those 3 hosts go with it."))
        var nordOnly = Group(id: "p", name: "Production")
        nordOnly.theme = "Nord"
        let one = Validation.deletionWarning(
            for: nordOnly, groups: [nordOnly], hosts: [hosts[0]])
        #expect(one.contains("The palette it gives that host goes with it."))
        // A group that sets nothing has nothing to say about it.
        #expect(!Validation.deletionWarning(for: groups[0], groups: groups, hosts: hosts)
            .contains("it gives"))
    }

    @Test("a group inside another says which one its hosts move to")
    func namesTheParent() {
        let said = Validation.deletionWarning(for: groups[1], groups: groups, hosts: hosts)
        #expect(said.contains("Its 2 hosts move to Production"))
        #expect(!said.contains("groups inside it"))
    }

    @Test("one host reads as one")
    func singleHost() {
        let said = Validation.deletionWarning(
            for: groups[1], groups: groups,
            hosts: [Host(id: "b", name: "b", addr: "10.0.0.2", groupId: "e")])
        #expect(said.contains("Its one host moves to Production"))
    }
}

@Suite("Options a host can carry")
nonisolated struct OptionValidationTests {
    @Test("an option ssh would refuse is refused here")
    func badOption() {
        let host = Host(id: "h", name: "web", addr: "10.0.0.1", sshOptions: ["BatchMode"])
        #expect(Validation.problem(with: host, among: []) != nil)
        let group = Group(id: "g", name: "Production", sshOptions: ["=yes"])
        #expect(Validation.problem(with: group, among: []) != nil)
    }

    @Test("real ones pass, on either")
    func goodOptions() {
        let host = Host(id: "h", name: "web", addr: "10.0.0.1",
                        sshOptions: ["ServerAliveInterval=30", "SetEnv FOO=bar"])
        #expect(Validation.problem(with: host, among: []) == nil)
        let group = Group(id: "g", name: "Production", sshOptions: ["Compression=yes"])
        #expect(Validation.problem(with: group, among: []) == nil)
    }
}

/// The fields a rename takes along, and what the editor says beforehand.
@Suite("What renaming a host takes with it")
nonisolated struct RenamingTests {
    // bastion, renamed gateway: db-01 names it itself, cased and padded
    // differently, api-eu-1 has it from EU, and web goes through edge.
    private let renamed = Host(id: "b", name: "gateway", addr: "192.0.2.10")
    private var hosts: [Host] {
        var inherits = Host(id: "1", name: "api-eu-1", addr: "198.51.100.21", groupId: "e")
        inherits.effective.proxyJump = "bastion"
        var own = Host(id: "2", name: "db-01", addr: "192.0.2.21", proxyJump: " BASTION ")
        own.effective.proxyJump = " BASTION "
        return [
            Host(id: "b", name: "bastion", addr: "192.0.2.10"),
            inherits, own,
            Host(id: "3", name: "web", addr: "10.0.0.3", proxyJump: "edge"),
        ]
    }
    private let groups = [
        Group(id: "e", name: "EU", proxyJump: "bastion"),
        Group(id: "u", name: "US", proxyJump: "edge"),
    ]

    /// Every field that named it, a host's own or a group's, names the new
    /// name, and nothing else is touched: api-eu-1 follows through EU.
    @Test("a rename takes the jump fields that named the host along")
    func follows() {
        let following = Validation.renaming(renamed, from: "bastion", hosts: hosts, groups: groups)
        #expect(following.hosts.map(\.id) == ["2"])
        #expect(following.hosts.map(\.proxyJump) == ["gateway"])
        #expect(following.groups.map(\.id) == ["e"])
        #expect(following.groups.map(\.proxyJump) == ["gateway"])
    }

    @Test("an unchanged name takes nothing, and a change of case settles the spelling")
    func unchangedOrRecased() {
        let same = Host(id: "b", name: "bastion", addr: "192.0.2.10")
        let none = Validation.renaming(same, from: "bastion", hosts: hosts, groups: groups)
        #expect(none.hosts.isEmpty && none.groups.isEmpty)
        let recased = Host(id: "b", name: "Bastion", addr: "192.0.2.10")
        let settled = Validation.renaming(recased, from: "bastion", hosts: hosts, groups: groups)
        #expect(settled.hosts.map(\.proxyJump) == ["Bastion"])
        #expect(settled.groups.map(\.proxyJump) == ["Bastion"])
    }

    /// A list from before names had to differ can hold two hosts by one
    /// name. The fields naming it still reach the other, so none of them is
    /// rewritten onto this one.
    @Test("nothing follows while another host still answers to the old name")
    func anotherAnswers() {
        let twice = hosts + [Host(id: "4", name: "Bastion", addr: "192.0.2.99")]
        let following = Validation.renaming(renamed, from: "bastion", hosts: twice, groups: groups)
        #expect(following.hosts.isEmpty && following.groups.isEmpty)
        #expect(Validation.renameNote(for: renamed, from: "bastion", hosts: twice, groups: groups) == nil)
    }

    @Test("the editor says what will follow, before Save")
    func note() {
        #expect(Validation.renameNote(for: renamed, from: "bastion", hosts: hosts, groups: groups)
            == "2 hosts and the group EU go through bastion, and will follow the new name.")
        let alone = [Group(id: "e", name: "EU", proxyJump: "bastion")]
        #expect(Validation.renameNote(for: renamed, from: "bastion", hosts: [hosts[0]], groups: alone)
            == "The group EU goes through bastion, and will follow the new name.")
        // Nothing goes through web, so renaming it says nothing.
        let www = Host(id: "3", name: "www", addr: "10.0.0.3", proxyJump: "edge")
        #expect(Validation.renameNote(for: www, from: "web", hosts: hosts, groups: groups) == nil)
    }
}
