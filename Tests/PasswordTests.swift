import Testing
@testable import Shellhand

// No `import Foundation`: it makes `Host` ambiguous. Where one is needed,
// spell the type `Shellhand.Host`.

/// A host's or a group's own password, beside its key, at the owner's word
/// (2026-11-08): where it sits in the resolver's walk, what the tab and the
/// sftp child are told, which prompt a tab types it at and how often, what
/// the editors say about it, and the store's writes — against a scratch
/// database and a keychain service of the test's own, never the user's.
@Suite("Host and group passwords")
nonisolated struct PasswordTests {
    private let deploy = Identity(
        id: "i1", name: "deploy", user: "deploy", keyPath: "~/.ssh/id_ed25519")
    private let switches = Identity(id: "i2", name: "switches", kind: .password, user: "root")

    private func resolve(
        _ host: Shellhand.Host, groups: [Group] = [], hosts: [Shellhand.Host] = [],
        identities: [Identity] = []
    ) -> Resolved {
        Resolver(groups: groups, hosts: hosts + [host], identities: identities).resolve(host)
    }

    // MARK: where a password sits in the walk

    @Test("a host's own password is filed under the host, and credited to nothing")
    func ownPassword() {
        let host = Shellhand.Host(id: "h1", name: "db-01", addr: "10.0.0.1", hasPassword: true)
        let out = resolve(host)
        #expect(out.passwordAccount == "host:h1")
        #expect(out.passwordFrom == "")
        #expect(out.effective.hasPassword)
    }

    @Test("a group's password reaches a host that keeps none, credited to the group")
    func groupPassword() {
        let production = Group(id: "g1", name: "Production", hasPassword: true)
        let host = Shellhand.Host(id: "h1", name: "db-01", addr: "10.0.0.1", groupId: "g1")
        let out = resolve(host, groups: [production])
        #expect(out.passwordAccount == "group:g1")
        #expect(out.effective.passwordFrom == "Production")
    }

    @Test("the walk is the user's: own, then the identity pointed at, then each group")
    func precedence() {
        let production = Group(id: "g1", name: "Production", hasPassword: true)
        // Its own beats everything above it.
        let own = Shellhand.Host(
            id: "h1", name: "a", addr: "10.0.0.1", identityId: "i2", hasPassword: true, groupId: "g1")
        #expect(resolve(own, groups: [production], identities: [switches]).passwordAccount == "host:h1")
        // The identity it points at beats its group's own.
        let pointed = Shellhand.Host(id: "h2", name: "b", addr: "10.0.0.2", identityId: "i2", groupId: "g1")
        let viaIdentity = resolve(pointed, groups: [production], identities: [switches])
        #expect(viaIdentity.passwordAccount == "i2")
        #expect(viaIdentity.passwordFrom == "the switches identity")
        // A key identity gives no password, and blocks nothing.
        let keyed = Shellhand.Host(id: "h3", name: "c", addr: "10.0.0.3", identityId: "i1", groupId: "g1")
        #expect(resolve(keyed, groups: [production], identities: [deploy]).passwordAccount == "group:g1")
    }

    @Test("a group's own password beats the identity that same group points at")
    func groupBeforeItsIdentity() {
        let production = Group(id: "g1", name: "Production", identityId: "i2", hasPassword: true)
        let host = Shellhand.Host(id: "h1", name: "db-01", addr: "10.0.0.1", groupId: "g1")
        #expect(resolve(host, groups: [production], identities: [switches]).passwordAccount == "group:g1")
        // Without its own, the identity's.
        let bare = Group(id: "g1", name: "Production", identityId: "i2")
        let out = resolve(host, groups: [bare], identities: [switches])
        #expect(out.passwordAccount == "i2")
        #expect(out.passwordFrom == "the switches identity")
    }

    @Test("a nearer group's password beats one further up")
    func nearerGroup() {
        let production = Group(id: "g1", name: "Production", hasPassword: true)
        let eu = Group(id: "g2", name: "EU", parentId: "g1", hasPassword: true)
        let host = Shellhand.Host(id: "h1", name: "db-01", addr: "10.0.0.1", groupId: "g2")
        let out = resolve(host, groups: [production, eu])
        #expect(out.passwordAccount == "group:g2")
        #expect(out.passwordFrom == "EU")
    }

    /// A machine typed into ⌘K has no id, so nothing was ever filed under
    /// it: a lookup under "host:" would be nobody's.
    @Test("a host with no id has no password of its own, whatever it says")
    func noID() {
        let typed = Shellhand.Host(id: "", name: "typed", addr: "10.0.9.2", hasPassword: true)
        #expect(resolve(typed).passwordAccount.isEmpty)
        #expect(!resolve(typed).effective.hasPassword)
    }

    @Test("FromAbove says whose password a group's hosts would take, its identity's credited")
    func fromAbove() {
        let production = Group(id: "g1", name: "Production", identityId: "i2")
        let eu = Group(id: "g2", name: "EU", parentId: "g1")
        let above = FromAbove(of: eu, among: [production, eu], identities: [switches])
        #expect(above.passwordAccount == "i2")
        #expect(above.passwordFrom == "the switches identity")
        let kept = Group(id: "g1", name: "Production", hasPassword: true)
        let fromKept = FromAbove(of: eu, among: [kept, eu])
        #expect(fromKept.passwordAccount == "group:g1")
        #expect(fromKept.passwordFrom == "Production")
    }

    /// What the group editor's caption and the group inspector's row both
    /// say: read off the groups above alone, a group picking a password
    /// identity named Production where its hosts take the identity's.
    @Test("a group names whose password its hosts take: the identity it picks, then the groups above")
    func groupPassesDownAPassword() {
        let production = Group(id: "g1", name: "Production", hasPassword: true)
        let eu = Group(id: "g2", name: "EU", parentId: "g1")
        let above = FromAbove(of: eu, among: [production, eu], identities: [switches])
        // A password identity picked here comes before Production's own.
        #expect(GroupEditorSheet.passedPassword(picked: switches, above: above)
            == "the switches identity")
        // A key identity gives none, and blocks nothing.
        #expect(GroupEditorSheet.passedPassword(picked: deploy, above: above) == "Production")
        #expect(GroupEditorSheet.passedPassword(picked: nil, above: above) == "Production")
        // Nothing kept anywhere: nobody's.
        let bare = FromAbove(of: eu, among: [Group(id: "g1", name: "Production"), eu])
        #expect(GroupEditorSheet.passedPassword(picked: nil, above: bare) == "")
        // And it is what the resolver gives a host beneath that keeps none.
        let picking = Group(id: "g2", name: "EU", parentId: "g1", identityId: "i2")
        let host = Shellhand.Host(id: "h1", name: "db-01", addr: "10.0.0.1", groupId: "g2")
        let out = resolve(host, groups: [production, picking], identities: [switches])
        #expect(out.passwordFrom == GroupEditorSheet.passedPassword(picked: switches, above: above))
    }

    // MARK: what a connection carries

    @Test("each stop on the way carries its own login and password, a hop's its own")
    func routeStops() {
        let bastion = Shellhand.Host(
            id: "hb", name: "bastion", addr: "192.0.2.1", user: "ops", hasPassword: true)
        let host = Shellhand.Host(
            id: "h1", name: "db-01", addr: "203.0.113.31", user: "deploy", hasPassword: true,
            proxyJump: "bastion")
        let route = resolve(host, hosts: [bastion]).route
        #expect(route.stops.map(\.user) == ["ops", "deploy"])
        #expect(route.stops.map(\.password) == ["host:hb", "host:h1"])
    }

    @Test("an unattended child answers a host's own password, under the host's account")
    func askpassForAHost() {
        let host = Shellhand.Host(id: "h1", name: "db-01", addr: "10.0.0.1", hasPassword: true)
        let out = Askpass.environment(for: resolve(host))
        #expect(Askpass.stops(from: out[Askpass.stopsVariable] ?? "").map(\.password) == ["host:h1"])
        #expect(out["SSH_ASKPASS_REQUIRE"] == "force")
        #expect(SSHArgs.unattended(resolve(host)) != SSHArgs.unattended)
    }

    /// A host with both is meant to log in with the key and fall back on the
    /// password, as a tab's ssh does — so the key leads where there is one.
    @Test("an unattended child tries the key first where one is set, then the password")
    func keyFirst() {
        let keyed = Shellhand.Host(
            id: "h1", name: "db-01", addr: "10.0.0.1", keyPath: "~/.ssh/id_ed25519", hasPassword: true)
        #expect(SSHArgs.unattended(resolve(keyed)).contains(
            "PreferredAuthentications=publickey,keyboard-interactive,password"))
        let bare = Shellhand.Host(id: "h2", name: "db-02", addr: "10.0.0.2", hasPassword: true)
        #expect(SSHArgs.unattended(resolve(bare)).contains(
            "PreferredAuthentications=keyboard-interactive,password"))
        // And with no password at all, every prompt off, as before.
        let none = Shellhand.Host(id: "h3", name: "db-03", addr: "10.0.0.3")
        #expect(SSHArgs.unattended(resolve(none)) == SSHArgs.unattended)
    }

    /// The bastion logs in with its key, the host behind it with a password:
    /// told the host's way of answering, the bastion's ssh would try only a
    /// password and turn SFTP away at the bastion.
    @Test("each ssh in an sftp child's chain is told its own way, from its own key and password")
    func eachHopItsOwnWay() throws {
        let bastion = Shellhand.Host(
            id: "hb", name: "bastion", addr: "192.0.2.1", user: "ops", keyPath: "~/.ssh/bastion")
        let db = Shellhand.Host(
            id: "h1", name: "db-01", addr: "203.0.113.31", user: "deploy", hasPassword: true,
            proxyJump: "bastion")
        let args = SFTPClient.arguments(resolve(db, hosts: [bastion]))
        let hop = try #require(args.first { $0.hasPrefix("ProxyCommand=") })
        let own = args.filter { $0 != hop }
        #expect(own.contains("PreferredAuthentications=keyboard-interactive,password"))
        #expect(!own.contains("BatchMode=yes"))
        #expect(hop.contains("BatchMode=yes"))
        #expect(!hop.contains("PreferredAuthentications"))

        // A bastion with a password of its own answers with it, key first.
        var keeping = bastion
        keeping.hasPassword = true
        let both = SFTPClient.arguments(resolve(db, hosts: [keeping]))
        let hopKeeping = try #require(both.first { $0.hasPrefix("ProxyCommand=") })
        #expect(hopKeeping.contains("PreferredAuthentications=publickey,keyboard-interactive,password"))
        #expect(!hopKeeping.contains("BatchMode=yes"))
    }

    @Test("the helper answers each machine on the way with its own password, and no other")
    func helperAnswersEachHop() {
        let stops = [
            Route.Stop(name: "bastion", dest: "bastion", addr: "192.0.2.1", port: 22,
                       user: "ops", password: "host:hb"),
            Route.Stop(name: "db-01", dest: "203.0.113.31", addr: "203.0.113.31", port: 22,
                       user: "deploy", password: "host:h1"),
        ]
        #expect(Askpass.account(for: "ops@bastion's password: ", among: stops) == "host:hb")
        #expect(Askpass.account(for: "deploy@203.0.113.31's password: ", among: stops) == "host:h1")
        // A server's own words, in its own language: the machine is what counts.
        #expect(Askpass.account(for: "(deploy@203.0.113.31) Passwort: ", among: stops) == "host:h1")
        // A jump host keeping none is never handed the host's.
        var bare = stops
        bare[0].password = ""
        #expect(Askpass.account(for: "ops@bastion's password: ", among: bare) == nil)
        // Naming none of them, two machines are not guessed between...
        #expect(Askpass.account(for: "Password: ", among: stops) == nil)
        // ...and one is: a direct connection is answered as it always was.
        #expect(Askpass.account(for: "Password: ", among: [stops[1]]) == "host:h1")
    }

    @Test("a jump host's own password reaches the helper though the host keeps none")
    func helperForAHopOnly() {
        let bastion = Shellhand.Host(
            id: "hb", name: "bastion", addr: "192.0.2.1", user: "ops", hasPassword: true)
        let db = Shellhand.Host(
            id: "h1", name: "db-01", addr: "203.0.113.31", user: "deploy", proxyJump: "bastion")
        let out = Askpass.environment(for: resolve(db, hosts: [bastion]))
        #expect(out["SSH_ASKPASS_REQUIRE"] == "force")
        let stops = Askpass.stops(from: out[Askpass.stopsVariable] ?? "")
        #expect(stops.map(\.password) == ["host:hb", ""])
        #expect(stops.map(\.user) == ["ops", "deploy"])
    }

    // MARK: which prompt a tab types at

    private let route = Route(stops: [
        Route.Stop(name: "bastion", dest: "bastion", addr: "192.0.2.1", port: 22,
                   user: "ops", password: "host:hb"),
        Route.Stop(name: "db-01", dest: "203.0.113.31", addr: "203.0.113.31", port: 2222,
                   user: "deploy", password: "host:h1"),
    ])

    @Test("ssh's own password prompt names the stop it asks for, in either shape")
    func promptShapes() {
        // Password authentication, the hop's name as ssh was handed it.
        #expect(PasswordPrompt.asked(in: "ops@bastion's password: ", route: route)?.stop == 0)
        // Or its address, which a config's HostName puts there.
        #expect(PasswordPrompt.asked(in: "ops@192.0.2.1's password: ", route: route)?.stop == 0)
        // Keyboard-interactive, the server naming it Password; no port in either.
        #expect(PasswordPrompt.asked(
            in: "Welcome\r\n(deploy@203.0.113.31) Password: ", route: route)?.stop == 1)
    }

    @Test("a prompt is typed at only while it is the last thing on screen")
    func promptMustBeLive() {
        #expect(PasswordPrompt.asked(
            in: "deploy@203.0.113.31's password: \r\nLast login: Mon\r\ndeploy@db:~$ ",
            route: route) == nil)
    }

    /// A password typed into the wrong question is a password given away.
    @Test("nothing but ssh's own prompt for a stop, logging in as its user, is typed at")
    func onlyOwnPrompts() {
        // Another user's password, on the right machine.
        #expect(PasswordPrompt.asked(in: "root@203.0.113.31's password: ", route: route) == nil)
        // A user whose name ends with the right one.
        #expect(PasswordPrompt.asked(in: "redeploy@203.0.113.31's password: ", route: route) == nil)
        // A machine not on the way.
        #expect(PasswordPrompt.asked(in: "deploy@198.51.100.9's password: ", route: route) == nil)
        // An authenticator's code, and sudo inside a session.
        #expect(PasswordPrompt.asked(
            in: "(deploy@203.0.113.31) Verification code: ", route: route) == nil)
        #expect(PasswordPrompt.asked(in: "[sudo] password for deploy: ", route: route) == nil)
    }

    @Test("a prompt the terminal wrapped across rows is still found")
    func wrappedPrompt() {
        #expect(PasswordPrompt.asked(
            in: "deploy@203.0.11\r\n3.31's passwo\r\nrd: ", route: route)?.stop == 1)
    }

    @Test("a stop with no user is asked for as this Mac's own login name")
    func localUser() {
        let bare = Route(stops: [Route.Stop(
            name: "web", dest: "web", addr: "10.0.0.5", port: 22, password: "host:hw")])
        #expect(PasswordPrompt.asked(
            in: "someone@web's password: ", route: bare, localUser: "someone")?.stop == 0)
        #expect(PasswordPrompt.asked(
            in: "other@web's password: ", route: bare, localUser: "someone") == nil)
    }

    @Test("ssh asking again stands the prompt on screen once more")
    func askedAgain() throws {
        let first = "deploy@203.0.113.31's password: "
        let asked = try #require(PasswordPrompt.asked(in: first, route: route))
        #expect(PasswordPrompt.count(asked, in: first) == 1)
        let again = first + "\r\nPermission denied, please try again.\r\n" + first
        #expect(PasswordPrompt.count(asked, in: again) == 2)
    }

    // MARK: what the watchdog makes of it

    @Test("a prompt the tab typed into, and ssh asking again, are not the far side")
    func typedIsNotThrough() throws {
        let prompt = "deploy@203.0.113.31's password: "
        let asked = try #require(PasswordPrompt.asked(in: prompt, route: route))
        // Left alone, a prompt is read as through, as it always was.
        #expect(SessionProgress.next(from: .connecting, screen: prompt) == .connected)
        // Typed into, still connecting — and still, asked again.
        #expect(SessionProgress.next(from: .connecting, screen: prompt, typed: [asked.tight]) == nil)
        let again = prompt + "\r\nPermission denied, please try again.\r\n" + prompt
        #expect(SessionProgress.next(from: .connecting, screen: again, typed: [asked.tight]) == nil)
        // Through as soon as the far side says anything.
        #expect(SessionProgress.next(
            from: .connecting, screen: prompt + "\r\nLast login: Mon\r\n$ ", typed: [asked.tight])
            == .connected)
    }

    @Test("a password turned down while connecting needs you, and says whose")
    func turnedDownStatus() {
        let status = SessionStatus.of(.connecting, stopped: false, gotThrough: false, turnedDown: true)
        #expect(status == .needsPassword)
        #expect(status.needsYou)
        #expect(status.spoken == "needs you to type the password")
        #expect(status.headline(for: "db-01") == "db-01 turned down its saved password")
        // Through, it is through, whatever was turned down on the way.
        #expect(SessionStatus.of(.connected, stopped: false, gotThrough: true, turnedDown: true)
            == .connected)
    }

    // MARK: what the editors say

    @Test("the field says one is kept, and what Save does with what was typed")
    func field() {
        #expect(PasswordField.prompt(keeps: true, forgetting: false, inherited: false)
            == "kept in this Mac's keychain")
        #expect(PasswordField.prompt(keeps: true, forgetting: true, inherited: true)
            == "forgotten on Save")
        #expect(PasswordField.prompt(keeps: false, forgetting: false, inherited: true)
            == "kept in this Mac's keychain")
        // No example of a password: nothing at all.
        #expect(PasswordField.prompt(keeps: false, forgetting: false, inherited: false) == "")

        #expect(PasswordField.change(typed: "", forgetting: false) == .keep)
        #expect(PasswordField.change(typed: "s3cret", forgetting: false) == .set("s3cret"))
        #expect(PasswordField.change(typed: "s3cret", forgetting: true) == .set("s3cret"))
        #expect(PasswordField.change(typed: "", forgetting: true) == .forget)

        // A source is named only while the record has none of its own in play.
        #expect(PasswordField.namesSource(typed: "", keeps: false))
        #expect(!PasswordField.namesSource(typed: "x", keeps: false))
        #expect(!PasswordField.namesSource(typed: "", keeps: true))
    }

    @Test("deleting a group that keeps a password says the password goes with it")
    func deletionSaysSo() {
        let production = Group(id: "g1", name: "Production", hasPassword: true)
        let host = Shellhand.Host(id: "h1", name: "db-01", addr: "10.0.0.1", groupId: "g1")
        let said = Validation.deletionWarning(for: production, groups: [production], hosts: [host])
        #expect(said.contains("The password it gives that host goes with it."))
    }

    @Test("the export carries no password, nor that there is one")
    func exportKeepsItOut() throws {
        let production = Group(id: "g1", name: "Production", hasPassword: true)
        let host = Shellhand.Host(
            id: "h1", name: "db-01", addr: "10.0.0.1", hasPassword: true, groupId: "g1")
        let text = try Portable.export(groups: [production], hosts: [host])
        // Past the header, which says none travels.
        let records = text.split(separator: "\n").filter { !$0.hasPrefix("#") }
        #expect(!records.contains { $0.lowercased().contains("password") })
    }
}

/// The tab, against a terminal fed by hand and a password handed to it
/// rather than read from any keychain: no process sits behind the view, so
/// what is typed goes nowhere, and what the session asked for is the record.
@MainActor
@Suite("A tab typing a saved password")
struct TabPasswordTests {
    private let route = Route(stops: [Route.Stop(
        name: "db-01", dest: "203.0.113.31", addr: "203.0.113.31", port: 22,
        user: "deploy", password: "host:h1")])

    private func waitUntil(_ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if done() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return done()
    }

    @Test("a tab types the stop's password once, stays connecting, and is through after")
    func typesOnce() async {
        let session = TerminalSession(title: "db-01", host: nil, route: route)
        defer { session.close() }
        var asked: [String] = []
        session.passwordFor = { account in asked.append(account); return "s3cret" }
        session.view.feed(text: "deploy@203.0.113.31's password: ")
        session.watch()

        #expect(await waitUntil { session.typedFor == "db-01" })
        #expect(asked == ["host:h1"])
        // Five looks, a whole second, and it was typed once and the tab is
        // still connecting: the prompt it typed into is ssh's, not the far side.
        let looked = session.ticks
        _ = await waitUntil { session.ticks >= looked + 5 }
        #expect(asked == ["host:h1"], "typed again: \(asked)")
        #expect(session.state == .connecting)

        session.view.feed(text: "\r\nLast login: Mon Nov 10\r\ndeploy@db-01:~$ ")
        #expect(await waitUntil { session.state == .connected })
    }

    @Test("asked again, a tab types nothing more and says the password was turned down")
    func turnedDown() async {
        let session = TerminalSession(title: "db-01", host: nil, route: route)
        defer { session.close() }
        var asked: [String] = []
        session.passwordFor = { account in asked.append(account); return "s3cret" }
        session.view.feed(text: "deploy@203.0.113.31's password: ")
        session.watch()
        #expect(await waitUntil { session.typedFor == "db-01" })

        session.view.feed(text: "\r\nPermission denied, please try again.\r\n"
            + "deploy@203.0.113.31's password: ")
        #expect(await waitUntil { session.status == .needsPassword })
        #expect(session.turnedDown == "db-01")
        #expect(asked == ["host:h1"], "typed again: \(asked)")
    }

    @Test("a stop with no password kept leaves the prompt to the person, as before")
    func nothingKept() async {
        let bare = Route(stops: [Route.Stop(
            name: "db-01", dest: "203.0.113.31", addr: "203.0.113.31", port: 22, user: "deploy")])
        let session = TerminalSession(title: "db-01", host: nil, route: bare)
        defer { session.close() }
        var asked: [String] = []
        session.passwordFor = { account in asked.append(account); return "s3cret" }
        session.view.feed(text: "deploy@203.0.113.31's password: ")
        session.watch()
        #expect(await waitUntil { session.state == .connected })
        #expect(asked.isEmpty)
        #expect(session.typedFor == nil)
    }
}

/// The store's writes, against a scratch database and a keychain service of
/// the test's own — `HostStore.keychainService` — taken away on the way out.
@MainActor
@Suite("A password kept on Save")
struct PasswordStoreTests {
    private func scratch() -> (HostStore, String) {
        let store = HostStore(dbPath: TestScratch.database())
        let service = "Shellhand test \(Store.newID())"
        store.keychainService = service
        return (store, service)
    }

    @Test("a new host's password is kept under its new id, and the host says it keeps one")
    func keptOnAdd() async throws {
        let (store, service) = scratch()
        await store.refresh()
        let saved = try #require(await store.save(
            Shellhand.Host(name: "db-01", addr: "10.0.0.1"), password: .set("s3cret")))
        let account = Keychain.account(host: saved.id)
        defer { try? Keychain.remove(account, service: service) }

        #expect(!saved.id.isEmpty)
        #expect(saved.hasPassword)
        #expect(try Keychain.password(for: account, service: service) == "s3cret")
        // Read back from the store, through the row mapping's third edit.
        #expect(store.snapshot.hosts.first { $0.id == saved.id }?.hasPassword == true)
    }

    @Test("forgotten on Save, it is gone from the keychain and the host says so")
    func forgotten() async throws {
        let (store, service) = scratch()
        await store.refresh()
        let saved = try #require(await store.save(
            Shellhand.Host(name: "db-01", addr: "10.0.0.1"), password: .set("s3cret")))
        let account = Keychain.account(host: saved.id)
        defer { try? Keychain.remove(account, service: service) }

        let after = try #require(await store.save(saved, password: .forget))
        #expect(!after.hasPassword)
        #expect(try Keychain.password(for: account, service: service) == nil)
    }

    @Test("a group's password is kept under the group, and goes when the group does")
    func groupDeleted() async throws {
        let (store, service) = scratch()
        await store.refresh()
        let group = try #require(await store.save(
            Group(name: "Production"), password: .set("s3cret")))
        let account = Keychain.account(group: group.id)
        defer { try? Keychain.remove(account, service: service) }
        #expect(try Keychain.password(for: account, service: service) == "s3cret")

        await store.delete(group)
        #expect(try Keychain.password(for: account, service: service) == nil)
    }

    @Test("saving with nothing done to the password leaves it as it was")
    func kept() async throws {
        let (store, service) = scratch()
        await store.refresh()
        let saved = try #require(await store.save(
            Shellhand.Host(name: "db-01", addr: "10.0.0.1"), password: .set("s3cret")))
        let account = Keychain.account(host: saved.id)
        defer { try? Keychain.remove(account, service: service) }

        var renamed = saved
        renamed.name = "db-02"
        let after = try #require(await store.save(renamed, password: .keep))
        #expect(after.hasPassword)
        #expect(try Keychain.password(for: account, service: service) == "s3cret")
    }
}
