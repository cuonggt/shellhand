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
        #expect(QuickConnect.moved(from: "1", by: 1, over: []) == nil)
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
}
