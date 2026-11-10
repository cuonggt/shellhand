import Testing
@testable import Shellhand

// No `import Foundation`: it makes `Host` ambiguous. Where one is needed,
// spell the type `Shellhand.Host`.

/// Identities: a login written once and pointed at from many hosts and groups.
///
/// The whole of Phase 1 is checkable without a connection, which is most of
/// the reason it is a phase of its own — the resolver's precedence, what a
/// deletion says, what the file carries, and the store's own writes.
@Suite("Identities")
nonisolated struct IdentityTests {
    private let deploy = Identity(
        id: "i1", name: "deploy", user: "deploy", keyPath: "~/.ssh/id_ed25519")
    private let operatorID = Identity(id: "i2", name: "operator", user: "ops")
    private let empty = Identity(id: "i3", name: "started")

    private func resolver(
        groups: [Group] = [], hosts: [Shellhand.Host] = [], identities: [Identity] = []
    ) -> Resolver {
        Resolver(groups: groups, hosts: hosts, identities: identities)
    }

    // MARK: where an identity sits in the chain

    @Test("an identity fills in what the host leaves empty, and names itself as the source")
    func fillsIn() {
        let host = Shellhand.Host(id: "h", name: "db-01", addr: "10.0.0.1", identityId: "i1")
        let out = resolver(hosts: [host], identities: [deploy]).resolve(host)
        #expect(out.user == "deploy")
        #expect(out.keyPath == "~/.ssh/id_ed25519")
        // The identity, never the group that pointed at it: the group is
        // where the pointer is and the identity is where the value is.
        #expect(out.userFrom == "the deploy identity")
        #expect(out.keyPathFrom == "the deploy identity")
        // Pointed at by the host itself, so nothing is credited for the
        // pointer — as `userFrom` is empty when the host sets its own user.
        #expect(out.identity == "deploy")
        #expect(out.identityFrom == "")
    }

    @Test("a host's own field beats the identity it points at")
    func hostBeatsItsIdentity() {
        let host = Shellhand.Host(
            id: "h", name: "db-01", addr: "10.0.0.1", user: "root", identityId: "i1")
        let out = resolver(hosts: [host], identities: [deploy]).resolve(host)
        #expect(out.user == "root")
        #expect(out.userFrom == "")
        // The key it says nothing about still comes from the identity.
        #expect(out.keyPath == "~/.ssh/id_ed25519")
        #expect(out.keyPathFrom == "the deploy identity")
    }

    @Test("the identity a host points at beats a group above it")
    func hostIdentityBeatsGroup() {
        let group = Group(id: "g", name: "Production", user: "ubuntu", keyPath: "/keys/prod")
        let host = Shellhand.Host(
            id: "h", name: "db-01", addr: "10.0.0.1", identityId: "i1", groupId: "g")
        let out = resolver(groups: [group], hosts: [host], identities: [deploy]).resolve(host)
        #expect(out.user == "deploy")
        #expect(out.keyPath == "~/.ssh/id_ed25519")
        #expect(out.userFrom == "the deploy identity")
    }

    @Test("a group's own field beats the identity that same group points at")
    func groupBeatsItsIdentity() {
        let group = Group(
            id: "g", name: "Production", user: "ubuntu", identityId: "i1")
        let host = Shellhand.Host(id: "h", name: "db-01", addr: "10.0.0.1", groupId: "g")
        let out = resolver(groups: [group], hosts: [host], identities: [deploy]).resolve(host)
        #expect(out.user == "ubuntu")
        #expect(out.userFrom == "Production")
        // The key the group says nothing about comes from what it points at.
        #expect(out.keyPath == "~/.ssh/id_ed25519")
        #expect(out.keyPathFrom == "the deploy identity")
    }

    @Test("a group's identity reaches a host, and the group is credited for the pointer")
    func groupPointsAtOne() {
        let group = Group(id: "g", name: "Production", identityId: "i1")
        let host = Shellhand.Host(id: "h", name: "db-01", addr: "10.0.0.1", groupId: "g")
        let out = resolver(groups: [group], hosts: [host], identities: [deploy]).resolve(host)
        #expect(out.user == "deploy")
        #expect(out.userFrom == "the deploy identity")
        // Which group pointed at it, for the inspector's Identity row.
        #expect(out.identity == "deploy")
        #expect(out.identityFrom == "Production")
    }

    @Test("a nearer group's identity beats one further up")
    func nearestPointerWins() {
        let parent = Group(id: "p", name: "Production", identityId: "i1")
        let child = Group(id: "c", name: "EU", parentId: "p", identityId: "i2")
        let host = Shellhand.Host(id: "h", name: "web", addr: "10.0.0.1", groupId: "c")
        let out = resolver(
            groups: [parent, child], hosts: [host], identities: [deploy, operatorID]
        ).resolve(host)
        #expect(out.identity == "operator")
        #expect(out.identityFrom == "EU")
        #expect(out.user == "ops")
        // EU's identity says nothing about a key, so Production's is reached
        // — the fields are inherited one at a time, as everything else is.
        #expect(out.keyPath == "~/.ssh/id_ed25519")
        #expect(out.keyPathFrom == "the deploy identity")
    }

    @Test("an identity that says nothing blocks nothing")
    func saysNothing() {
        let group = Group(id: "g", name: "Production", user: "ubuntu", keyPath: "/keys/prod")
        let host = Shellhand.Host(
            id: "h", name: "db-01", addr: "10.0.0.1", identityId: "i3", groupId: "g")
        let out = resolver(groups: [group], hosts: [host], identities: [empty]).resolve(host)
        // It is still what the host points at, and it is still named.
        #expect(out.identity == "started")
        // But it fills nothing in, so the group is reached as before.
        #expect(out.user == "ubuntu")
        #expect(out.userFrom == "Production")
        #expect(out.keyPath == "/keys/prod")
    }

    @Test("an id nothing answers to falls through rather than resolving to nothing")
    func danglingPointer() {
        let group = Group(id: "g", name: "Production", user: "ubuntu")
        let host = Shellhand.Host(
            id: "h", name: "db-01", addr: "10.0.0.1", identityId: "gone", groupId: "g")
        let out = resolver(groups: [group], hosts: [host], identities: [deploy]).resolve(host)
        #expect(out.identity == "")
        #expect(out.user == "ubuntu")
        #expect(out.userFrom == "Production")
    }

    @Test("a jump host takes its own identity along")
    func hopsGetIdentities() {
        let bastion = Shellhand.Host(
            id: "b", name: "bastion", addr: "1.2.3.4", identityId: "i1")
        let host = Shellhand.Host(
            id: "h", name: "db-01", addr: "10.0.0.1", proxyJump: "bastion")
        let out = resolver(hosts: [bastion, host], identities: [deploy]).resolve(host)
        let hop = try! #require(out.jumps.first)
        #expect(hop.user == "deploy")
        #expect(hop.keyPath == "~/.ssh/id_ed25519")
    }

    @Test("the argv carries the key an identity supplies")
    func argv() {
        let host = Shellhand.Host(id: "h", name: "db-01", addr: "10.0.0.1", identityId: "i1")
        let out = resolver(hosts: [host], identities: [deploy]).resolve(host)
        #expect(SSHArgs.build(out) == ["-i", "~/.ssh/id_ed25519", "deploy@10.0.0.1"])
    }

    // MARK: what a record would inherit, for the editors' rows

    @Test("FromAbove reports a group's identity and what it fills in")
    func fromAbove() {
        let parent = Group(id: "p", name: "Production", identityId: "i1")
        let child = Group(id: "c", name: "EU", parentId: "p")
        let above = FromAbove(of: child, among: [parent, child], identities: [deploy])
        #expect(above.identity == "deploy")
        #expect(above.identityFrom == "Production")
        #expect(above.user == "deploy")
        #expect(above.userFrom == "the deploy identity")
    }

    @Test("FromAbove for a host reads its groups, not its own pointer")
    func fromAboveOfHost() {
        let group = Group(id: "g", name: "Production", identityId: "i1")
        // The host points at another one; the inherit rows must show what the
        // groups give, not what the host has already chosen.
        let host = Shellhand.Host(
            id: "h", name: "web", addr: "10.0.0.1", identityId: "i2", groupId: "g")
        let above = FromAbove(
            of: host, among: [group], identities: [deploy, operatorID])
        #expect(above.identity == "deploy")
        #expect(above.identityFrom == "Production")
    }

    // MARK: the record's own words

    @Test("an identity says where a value came from in words a caption can use")
    func source() {
        #expect(deploy.source == "the deploy identity")
        #expect(Effective.inherited("deploy", from: deploy.source)
            == "deploy from the deploy identity")
    }

    @Test("a row says what an identity fills in, and when it fills in nothing")
    func summary() {
        #expect(deploy.summary == "deploy · ~/.ssh/id_ed25519")
        #expect(operatorID.summary == "ops")
        #expect(empty.summary == "Says nothing yet")
        #expect(empty.saysNothing)
        #expect(!operatorID.saysNothing)
        // Whitespace is not a value.
        #expect(Identity(name: "x", user: "  ", keyPath: " ").saysNothing)
    }

    // MARK: what stops one being saved

    @Test("an identity needs a name, and not one another identity has")
    func problem() {
        #expect(Validation.problem(with: Identity(name: " "), among: []) != nil)
        #expect(Validation.problem(with: deploy, among: [deploy]) == nil)
        let clash = Identity(id: "other", name: "DEPLOY")
        #expect(Validation.problem(with: clash, among: [deploy])
            == "There is already an identity called DEPLOY.")
        // One that says nothing is a record somebody has started, not a
        // problem: the name has to be typeable before the rest.
        #expect(Validation.problem(with: empty, among: []) == nil)
    }

    // MARK: what deleting one says

    @Test("deleting an identity nothing points at says so")
    func deletingUnused() {
        #expect(Validation.deletionWarning(for: deploy)
            == "Nothing points at it. \(Validation.cannotBeUndone)")
    }

    @Test("deleting one says how many hosts lose what, and agrees with itself")
    func deletingUsed() {
        var one = Shellhand.Host(id: "h", name: "db-01", addr: "10.0.0.1")
        one.effective = Effective(identity: "deploy")
        let said = Validation.deletionWarning(for: deploy, hosts: [one])
        #expect(said == "1 host points at it, and loses the user and the key. "
            + "Nothing is deleted but the identity itself. \(Validation.cannotBeUndone)")

        var two = one
        two.id = "h2"
        two.name = "web"
        let many = Validation.deletionWarning(for: deploy, hosts: [one, two])
        #expect(many.hasPrefix("2 hosts point at it, and lose the user and the key."))
    }

    @Test("the groups that point at it are named, and the hosts beneath them counted")
    func deletingNamesGroups() {
        // Counted by what reaches them, so a host under a pointing group is
        // included: "the jump host for 2 groups" said nothing of the six
        // hosts in them, and this is the same mistake.
        let production = Group(id: "p", name: "Production", identityId: "i1")
        let eu = Group(id: "e", name: "EU", identityId: "i1")
        var host = Shellhand.Host(id: "h", name: "db-01", addr: "10.0.0.1", groupId: "p")
        host.effective = Effective(identity: "deploy")
        let said = Validation.deletionWarning(
            for: deploy, hosts: [host], groups: [production, eu])
        #expect(said.hasPrefix("1 host and the groups EU and Production point at it"))
    }

    @Test("an identity that fills nothing in says only who points at it")
    func deletingOneThatSaysNothing() {
        var host = Shellhand.Host(id: "h", name: "db-01", addr: "10.0.0.1")
        host.effective = Effective(identity: "started")
        let said = Validation.deletionWarning(for: empty, hosts: [host])
        #expect(said == "1 host points at it. Nothing is deleted but the identity itself. "
            + Validation.cannotBeUndone)
    }

    @Test("only the user's name is mentioned when that is all it gives")
    func deletingUserOnly() {
        var host = Shellhand.Host(id: "h", name: "db-01", addr: "10.0.0.1")
        host.effective = Effective(identity: "operator")
        let said = Validation.deletionWarning(for: operatorID, hosts: [host])
        #expect(said.hasPrefix("1 host points at it, and loses the user."))
    }

    // MARK: what kind it is

    @Test("a password identity says the password goes with it")
    func deletingAPasswordOne() {
        let switches = Identity(id: "i4", name: "switches", kind: .password, user: "root")
        var host = Shellhand.Host(id: "h", name: "sw-1", addr: "10.0.9.2")
        host.effective = Effective(identity: "switches")
        let said = Validation.deletionWarning(for: switches, hosts: [host])
        #expect(said.hasPrefix("1 host points at it, and loses the user and the password."))
    }

    @Test("a password identity is never 'says nothing', whatever is typed on it")
    func passwordIsNeverEmpty() {
        // What it carries is in the keychain, which the model cannot see and
        // must not read: a property that touched it would do so per row, per
        // redraw.
        #expect(Identity(name: "switches", kind: .password).saysNothing == false)
        #expect(Identity(name: "started", kind: .key).saysNothing)
    }

    @Test("a row says what kind it is without asking the keychain")
    func kindInTheSummary() {
        #expect(Identity(name: "x", kind: .password, user: "root").summary == "root · password")
        #expect(Identity(name: "x", kind: .password).summary == "password")
        #expect(deploy.summary == "deploy · ~/.ssh/id_ed25519")
    }

    @Test("a password identity fills in the user and leaves the key alone")
    func passwordFillsTheUser() {
        let switches = Identity(id: "i4", name: "switches", kind: .password, user: "root")
        let host = Shellhand.Host(id: "h", name: "sw-1", addr: "10.0.9.2", identityId: "i4")
        let out = resolver(hosts: [host], identities: [switches]).resolve(host)
        #expect(out.user == "root")
        #expect(out.userFrom == "the switches identity")
        #expect(out.keyPath == "")
        // And nothing of it reaches the command line yet: wiring a password
        // into a connection is the phase after this one.
        #expect(SSHArgs.build(out) == ["root@10.0.9.2"])
    }

    // MARK: the host editor's User row

    @Test("picking an identity that names a user clears a user typed beside it")
    func pickingClearsATypedUser() {
        let picked = UserField.picking(deploy, over: "root")
        #expect(picked.identityId == "i1")
        // Left typed, it would log in in the identity's place: the host's
        // own user comes before the identity it points at.
        #expect(picked.user == "")
    }

    @Test("picking one that names no user keeps the user typed, the only one there is")
    func pickingKeepsATypedUser() {
        let laptop = Identity(id: "i5", name: "laptop", keyPath: "~/.ssh/id_laptop")
        let picked = UserField.picking(laptop, over: "root")
        #expect(picked.identityId == "i5")
        #expect(picked.user == "root")
    }

    @Test("the User row says where its user is from only where the record says none itself")
    func userCaption() {
        let laptop = Identity(id: "i5", name: "laptop", keyPath: "~/.ssh/id_laptop")
        // Inherited, from a group or from a group's identity.
        #expect(UserField.caption(typed: "", picked: nil, from: "Production")
            == "Production")
        #expect(UserField.caption(typed: " ", picked: nil, from: "the deploy identity")
            == "the deploy identity")
        // Typed here, whatever is picked beside it.
        #expect(UserField.caption(typed: "root", picked: nil, from: "Production") == nil)
        #expect(UserField.caption(
            typed: "root", picked: deploy, from: "the deploy identity") == nil)
        // An identity picked here that names a user: its token says whose.
        #expect(UserField.caption(
            typed: "", picked: deploy, from: "the deploy identity") == nil)
        // One that names none leaves the user to whatever is above, which says so.
        #expect(UserField.caption(typed: "", picked: laptop, from: "Production")
            == "Production")
        // Nothing anywhere: nothing to say.
        #expect(UserField.caption(typed: "", picked: nil, from: "") == nil)
    }

    @Test("the grey user after a token is left out where it is the token's own name")
    func typingPromptAfterAToken() {
        // "deploy", logging in as deploy: the token says it once.
        #expect(UserField.typingPrompt("deploy", after: deploy) == "")
        // "operator", logging in as ops: worth saying.
        #expect(UserField.typingPrompt("ops", after: operatorID) == "ops")
        // One that names no user: the grey one is from above, whatever the
        // identity is called — even a name it happens to share.
        let laptop = Identity(id: "i5", name: "admin", keyPath: "~/.ssh/id_laptop")
        #expect(UserField.typingPrompt("admin", after: laptop) == "admin")
    }

    @Test("a group's rows read the identity it picks before the groups above it")
    func groupPassesDownItsIdentity() {
        // What the identity fills in, credited to it, as the resolver gives
        // the hosts beneath.
        let key = GroupEditorSheet.passedDown(
            picked: deploy.keyPath, pickedFrom: deploy.source,
            above: "~/.ssh/id_rsa", aboveFrom: "Production")
        #expect(key.value == "~/.ssh/id_ed25519")
        #expect(key.from == "the deploy identity")
        // Where it fills nothing in, the groups above still do.
        let user = GroupEditorSheet.passedDown(
            picked: "  ", pickedFrom: "the laptop identity",
            above: "ops", aboveFrom: "Production")
        #expect(user.value == "ops")
        #expect(user.from == "Production")
        // And with nothing picked, only the groups above.
        let none = GroupEditorSheet.passedDown(
            picked: "", pickedFrom: "", above: "", aboveFrom: "")
        #expect(none.value == "" && none.from == "")
    }

    @Test("a group's rows agree with what the resolver gives a host beneath it")
    func groupRowsAgreeWithTheResolver() {
        // Production picks deploy; a host under it that sets nothing logs
        // in with what the group's editor says it passes down.
        let production = Group(id: "g1", name: "Production", identityId: "i1")
        let host = Shellhand.Host(id: "h", name: "db-01", addr: "10.0.0.1", groupId: "g1")
        let out = resolver(groups: [production], hosts: [host], identities: [deploy]).resolve(host)
        let above = FromAbove(of: production, among: [production], identities: [deploy])
        let key = GroupEditorSheet.passedDown(
            picked: deploy.keyPath, pickedFrom: deploy.source,
            above: above.keyPath, aboveFrom: above.keyPathFrom)
        #expect(key.value == out.keyPath)
        #expect(key.from == out.keyPathFrom)
        let user = GroupEditorSheet.passedDown(
            picked: deploy.user, pickedFrom: deploy.source,
            above: above.user, aboveFrom: above.userFrom)
        #expect(user.value == out.user)
        #expect(user.from == out.userFrom)
    }
}
