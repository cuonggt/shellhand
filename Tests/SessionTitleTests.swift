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
