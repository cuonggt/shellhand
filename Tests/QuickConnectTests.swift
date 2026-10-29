import Testing
@testable import Shellhand

/// What ⌘K offers for what has been typed, and where an arrow moves the
/// highlight.
///
/// No `import Foundation` here: it would make `Host` ambiguous with
/// `Foundation.Host`, which is why ids are written as plain strings.
@Suite("Quick Connect")
nonisolated struct QuickConnectTests {
    private static func host(
        _ id: String, _ name: String, addr: String = "10.0.0.1", tags: [String] = []
    ) -> Host {
        Host(id: id, name: name, addr: addr, tags: tags)
    }

    private let hosts = [
        host("1", "web-staging", addr: "10.0.0.11"),
        host("2", "api", addr: "10.0.0.12", tags: ["web", "eu"]),
        host("3", "database", addr: "10.0.0.13"),
        host("4", "WEB-PROD", addr: "192.168.0.1"),
        host("5", "cache", addr: "10.0.0.15", tags: ["eu"]),
    ]

    private func names(_ typed: String) -> [String] {
        QuickConnect.matches(among: hosts, for: typed).map(\.name)
    }

    // MARK: what matches, and in what order

    @Test("typing nothing offers the whole list, alphabetically")
    func everything() {
        let out = names("")
        #expect(out.count == 5)
        #expect(Array(out.prefix(3)) == ["api", "cache", "database"])
        // Which of the two web hosts leads is the locale's business, not this
        // app's, so only their position is asserted.
        #expect(Set(out.suffix(2)) == ["web-staging", "WEB-PROD"])
    }

    @Test("a name that starts with what was typed comes before one that merely holds it")
    func prefixWins() {
        // "web-staging" and "WEB-PROD" both start with it; "api" only carries
        // it as a tag, so it comes last.
        let out = names("web")
        #expect(out.count == 3)
        #expect(Set(out.prefix(2)) == ["web-staging", "WEB-PROD"])
        #expect(out.last == "api")
    }

    @Test("a name match beats an address match")
    func nameBeatsAddress() {
        // "cache" matches by name; the others only by address digits.
        #expect(names("ca").first == "cache")
    }

    @Test("an address match beats a tag match")
    func addressBeatsTag() {
        // 192.168 is only in WEB-PROD's address; nothing is tagged with it.
        #expect(names("192") == ["WEB-PROD"])
    }

    @Test("a tag finds a host whose name and address say nothing")
    func byTag() {
        #expect(Set(names("eu")) == ["api", "cache"])
    }

    @Test("matching ignores case on both sides")
    func caseBlind() {
        #expect(names("WEB-PROD") == ["WEB-PROD"])
        #expect(names("web-prod") == ["WEB-PROD"])
        #expect(names("DATA") == ["database"])
    }

    @Test("nothing matching is an empty list, not the whole one")
    func nothing() {
        #expect(names("zzzz").isEmpty)
    }

    @Test("the list is capped, so one letter does not rank everything")
    func capped() {
        let many = (1...120).map { Self.host("\($0)", "host-\($0)") }
        #expect(QuickConnect.matches(among: many, for: "host").count == QuickConnect.limit)
        #expect(QuickConnect.matches(among: many, for: "").count == QuickConnect.limit)
        #expect(QuickConnect.matches(among: many, for: "host", limit: 3).count == 3)
    }

    // MARK: moving the highlight

    @Test("down and up move one, and stop at the ends rather than wrapping")
    func moves() {
        let list = QuickConnect.matches(among: hosts, for: "")
        let first = list[0].id
        let second = list[1].id
        let last = list[list.count - 1].id

        #expect(QuickConnect.moved(from: first, by: 1, over: list) == second)
        #expect(QuickConnect.moved(from: second, by: -1, over: list) == first)
        #expect(QuickConnect.moved(from: first, by: -1, over: list) == first,
                "running off the top stays at the top")
        #expect(QuickConnect.moved(from: last, by: 1, over: list) == last,
                "running off the bottom stays at the bottom")
    }

    @Test("a highlight on a host the list no longer holds starts again from the top")
    func stale() {
        let list = QuickConnect.matches(among: hosts, for: "")
        #expect(QuickConnect.moved(from: "gone", by: -1, over: list) == list[0].id)
    }

    @Test("an empty list has nothing to highlight")
    func empty() {
        #expect(QuickConnect.moved(from: "1", by: 1, over: [Host]()) == nil)
    }

    /// Documented rather than endorsed. With nothing highlighted, Down lands
    /// on the *second* row while Up lands on the first, because "not found"
    /// and "the first row" are the same answer to `firstIndex`. The sheet
    /// never reaches this — it sets the highlight to the top match on appear
    /// and on every keystroke — so it is a latent oddity, not a visible bug.
    /// If the sheet ever stops doing that, this is what it would meet.
    @Test("with nothing highlighted the arrows are not symmetric")
    func fromNothing() {
        let list = QuickConnect.matches(among: hosts, for: "")
        #expect(QuickConnect.moved(from: nil, by: 1, over: list) == list[1].id)
        #expect(QuickConnect.moved(from: nil, by: -1, over: list) == list[0].id)
    }

    // MARK: reading what was typed as somewhere to connect

    private typealias Destination = QuickConnect.Destination

    private func read(_ typed: String) -> Destination? {
        QuickConnect.destination(from: typed)
    }

    @Test("a host, with or without a user and a port")
    func readsTheParts() {
        #expect(read("db.example.com") == Destination(host: "db.example.com"))
        #expect(read("deploy@db.example.com") == Destination(user: "deploy", host: "db.example.com"))
        #expect(read("db.example.com:2222") == Destination(host: "db.example.com", port: 2222))
        #expect(read("deploy@10.0.1.5:2222") == Destination(user: "deploy", host: "10.0.1.5", port: 2222))
        #expect(read("  web  ") == Destination(host: "web"), "the spaces either side are typing, not the name")
    }

    /// Several colons are an IPv6 address with no port; a port after one has
    /// to come after brackets, the way ssh's own users write it.
    @Test("an IPv6 address, bare or bracketed with a port")
    func readsIPv6() {
        #expect(read("fe80::1") == Destination(host: "fe80::1"))
        #expect(read("[2001:db8::7]:2222") == Destination(host: "2001:db8::7", port: 2222))
        #expect(read("root@[fe80::1%en0]:22") == Destination(user: "root", host: "fe80::1%en0", port: 22))
        #expect(read("[::1]") == Destination(host: "::1"))
    }

    @Test("an ssh:// link reads as what follows it")
    func readsALink() {
        #expect(read("ssh://deploy@db.example.com:2222") == Destination(user: "deploy", host: "db.example.com", port: 2222))
        #expect(read("SSH://db.example.com/") == Destination(host: "db.example.com"))
    }

    @Test("a port has to be one: plain digits, 1 to 65535")
    func refusesABadPort() {
        for typed in ["web:", "web:0", "web:65536", "web:22x", "web:+22", "[::1]:", "[::1]x"] {
            #expect(read(typed) == nil, "\(typed) read as a destination")
        }
    }

    /// **The case the refusal is for.** The destination ends ssh's command
    /// line, and ssh reads anything starting with `-` as an option.
    @Test("nothing that ssh would read as an option")
    func refusesAnOption() {
        for typed in ["-oProxyCommand=sh", "-p", "deploy@-oProxyCommand=sh", "-l@web", "-x@web:22"] {
            #expect(read(typed) == nil, "\(typed) read as a destination")
        }
    }

    @Test("nothing with spaces, an empty part, or marks no name uses")
    func refusesTheRest() {
        for typed in ["", "   ", "web prod", "@web", "deploy@", "a@b@c", "web/etc", "we;b", "wéb", "[::1"] {
            #expect(read(typed) == nil, "\(typed) read as a destination")
        }
    }

    @Test("it is written back the way ssh is typed")
    func spelling() {
        #expect(QuickConnect.Destination(host: "web").spelled == "web")
        #expect(QuickConnect.Destination(user: "deploy", host: "web", port: 2222).spelled == "deploy@web:2222")
        #expect(QuickConnect.Destination(host: "fe80::1").spelled == "fe80::1")
        #expect(QuickConnect.Destination(user: "root", host: "::1", port: 22).spelled == "root@[::1]:22")
    }

    @Test("a typed destination is connected as a host saved nowhere, named as typed")
    func unsaved() {
        let host = QuickConnect.unsaved(.init(user: "deploy", host: "10.0.1.5", port: 2222))
        #expect(host.id.isEmpty, "an id would put it in the list, the inspector and the OS question")
        #expect(host.name == "deploy@10.0.1.5:2222")
        #expect(host.addr == "10.0.1.5")
        #expect(host.user == "deploy")
        #expect(host.port == 2222)
        #expect(host.groupId.isEmpty)
    }

    // MARK: where the typed row goes

    private func ids(_ typed: String, among list: [Host]) -> [String] {
        QuickConnect.rows(among: list, for: typed).map(\.id)
    }

    @Test("nothing typed, or nothing that reads as a destination, adds no row")
    func noTypedRow() {
        #expect(QuickConnect.rows(among: hosts, for: "").count == hosts.count)
        #expect(!ids("web prod", among: hosts).contains { $0.hasPrefix("typed:") })
    }

    /// A bare word is a search first, as ⌘K always was: `web` is
    /// `web-staging` before it is a machine called `web`.
    @Test("a bare word lists the saved hosts first and itself last")
    func bareWordLast() {
        let out = ids("web", among: hosts)
        #expect(out.count == 4)
        #expect(out.last == "typed:web")
    }

    @Test("something no saved host matches is the only row")
    func onlyTheTypedRow() {
        #expect(ids("nas", among: hosts) == ["typed:nas"])
        #expect(ids("deploy@db.example.com:2222", among: hosts) == ["typed:deploy@db.example.com:2222"])
    }

    /// `10.0.1.5` must not lose to a host at `10.0.1.50`, which merely
    /// contains it — but the host saved at exactly that address keeps its key
    /// and its jump host by coming first.
    @Test("an address leads its own row unless a saved host is at exactly that address")
    func addressRanking() {
        let list = [Self.host("near", "near", addr: "10.0.1.50"), Self.host("here", "here", addr: "10.0.1.5")]
        #expect(ids("10.0.1.5", among: list) == ["here", "typed:10.0.1.5", "near"])
        #expect(ids("10.0.1.5", among: [Self.host("near", "near", addr: "10.0.1.50")])
            == ["typed:10.0.1.5", "near"])
    }

    /// A user or a port typed is a request: a saved host at that address
    /// logging in as somebody else, or on another port, is not what was asked
    /// for, so it does not get to go first.
    @Test("a user or port that says otherwise keeps a saved host from going first")
    func userAndPortDecide() {
        var saved = Self.host("db", "db", addr: "10.0.1.5")
        saved.effective.user = "deploy"
        #expect(ids("deploy@10.0.1.5", among: [saved]) == ["db", "typed:deploy@10.0.1.5"])
        #expect(ids("root@10.0.1.5", among: [saved]) == ["typed:root@10.0.1.5"])
        #expect(ids("10.0.1.5:2222", among: [saved]) == ["typed:10.0.1.5:2222"])
        #expect(ids("10.0.1.5:22", among: [saved]) == ["db", "typed:10.0.1.5:22"])
    }

    @Test("a saved host named exactly what was typed comes first")
    func exactNameFirst() {
        let list = [Self.host("1", "db.prod"), Self.host("2", "db.prod-old")]
        #expect(ids("db.prod", among: list) == ["1", "typed:db.prod", "2"])
    }

    @Test("the arrows move over the typed row like any other")
    func movesOverTheTypedRow() {
        let rows = QuickConnect.rows(among: hosts, for: "web")
        #expect(QuickConnect.moved(from: rows[2].id, by: 1, over: rows) == "typed:web")
        #expect(QuickConnect.moved(from: "typed:web", by: 1, over: rows) == "typed:web")
    }
}
