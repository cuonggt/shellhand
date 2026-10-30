import Testing
@testable import Shellhand

/// How a session's name is cut down for a tab and for the Window menu.
///
/// The shell sends something like `user@host:~/some/long/path`, which is too
/// long for either and mostly the same across every session on one machine.
/// What tells them apart is the machine and the tail of the path.
@Suite("Session titles")
nonisolated struct SessionTitleTests {
    @Test("the machine and the tail of the path, joined")
    func both() {
        #expect(Sessions.shortTitle(host: "prod-api", title: "root@prod:~/current/public")
            == "prod-api — ~/current/public")
    }

    @Test("a title with nothing after the colon is just the machine")
    func noPlace() {
        #expect(Sessions.shortTitle(host: "prod-api", title: "root@prod:") == "prod-api")
    }

    @Test("a title with no colon at all is just the machine")
    func noColon() {
        #expect(Sessions.shortTitle(host: "prod-api", title: "anything at all") == "prod-api")
        #expect(Sessions.shortTitle(host: "prod-api", title: "") == "prod-api")
    }

    @Test("the last colon is the one that counts")
    func lastColon() {
        // An IPv6 address, or a port, puts colons before the one that divides
        // the machine from the place.
        #expect(Sessions.shortTitle(host: "six", title: "root@fe80::1:~/srv")
            == "six — ~/srv")
    }

    /// A session's title is its host's name until the shell sends one, and a
    /// machine typed into ⌘K is named the way it was typed.
    @Test("a title that is still the host's own name is just the machine")
    func stillTheName() {
        #expect(Sessions.shortTitle(host: "root@127.0.0.1:1", title: "root@127.0.0.1:1")
            == "root@127.0.0.1:1")
        #expect(Sessions.shortTitle(host: "[2001:db8::5]:2222", title: "[2001:db8::5]:2222")
            == "[2001:db8::5]:2222")
        #expect(Sessions.shortTitle(host: "root@127.0.0.1:1", title: "root@box:~/srv")
            == "root@127.0.0.1:1 — ~/srv")
    }

    @Test("a session on no host is a local shell")
    func local() {
        #expect(Sessions.shortTitle(host: nil, title: "me@mac:~/Projects") == "Local — ~/Projects")
        #expect(Sessions.shortTitle(host: nil, title: "no colon here") == "Local")
    }

    /// The name is the host's as the list has it, not whatever the shell
    /// chose to call the machine — two hosts can point at one box under
    /// different names, and the tab has to say which one you opened.
    @Test("the name comes from the host, not from the title")
    func fromTheHost() {
        #expect(Sessions.shortTitle(host: "blue", title: "root@shared:~/x") == "blue — ~/x")
        #expect(Sessions.shortTitle(host: "green", title: "root@shared:~/x") == "green — ~/x")
    }
}
