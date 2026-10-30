import Testing
@testable import Shellhand

/// What a file pane calls itself, what it shows, and how it names a child.
///
/// No `import Foundation`: it would make `Host` ambiguous with
/// `Foundation.Host`. Nothing here needs it.
@Suite("Places")
nonisolated struct PlacesTests {
    private static func entry(_ name: String) -> RemoteEntry {
        RemoteEntry(name: name)
    }

    private let listing = [
        entry(".bashrc"),
        entry(".ssh"),
        entry("Documents"),
        entry("notes.txt"),
    ]

    // MARK: what the pane calls itself

    /// The distinction the whole `chosen` flag exists for. Without it an
    /// unpointed pane reads as "This Mac" over an empty listing — which looks
    /// exactly like an empty home directory.
    @Test("a pane pointed nowhere asks, rather than claiming to be this Mac")
    func unpointed() {
        #expect(Places.title(chosen: false, host: nil) == "Choose a host")
        #expect(Places.title(chosen: false, host: "web") == "Choose a host",
                "not chosen yet beats whatever host it is about to be given")
    }

    @Test("a pane pointed at this Mac, and at a host, say so")
    func pointed() {
        #expect(Places.title(chosen: true, host: nil) == "This Mac")
        #expect(Places.title(chosen: true, host: "web") == "web")
    }

    // MARK: whether it is this Mac

    /// This matters beyond the label: `isLocal` decides whether a name clash
    /// is judged case-insensitively, because this disk is and a server's
    /// usually is not.
    @Test("only a pane pointed at this Mac is local")
    func local() {
        #expect(Places.isLocal(chosen: true, onAHost: false) == true)
        #expect(Places.isLocal(chosen: true, onAHost: true) == false)
    }

    @Test("a pane pointed nowhere is not local either")
    func unpointedIsNotLocal() {
        #expect(Places.isLocal(chosen: false, onAHost: false) == false)
        #expect(Places.isLocal(chosen: false, onAHost: true) == false)
    }

    // MARK: what it shows

    @Test("dotfiles are held back by default")
    func hidesDotfiles() {
        #expect(Places.shown(listing, hidden: false).map(\.name) == ["Documents", "notes.txt"])
        #expect(Places.hiddenCount(listing, hidden: false) == 2)
    }

    @Test("asked for, they come back in the order they were in")
    func showsDotfiles() {
        #expect(Places.shown(listing, hidden: true).map(\.name)
            == [".bashrc", ".ssh", "Documents", "notes.txt"])
        #expect(Places.hiddenCount(listing, hidden: true) == 0)
    }

    @Test("a listing with nothing in it hides nothing")
    func emptyListing() {
        #expect(Places.shown([], hidden: false).isEmpty)
        #expect(Places.hiddenCount([], hidden: false) == 0)
    }

    @Test("a name that is only a dot is still a dotfile")
    func justADot() {
        #expect(Places.shown([Self.entry(".")], hidden: false).isEmpty)
    }

    // MARK: naming a child

    @Test("a child of an ordinary directory")
    func childPath() {
        #expect(Places.path("/home/deploy", "notes.txt") == "/home/deploy/notes.txt")
        #expect(Places.path("/var/log", "syslog") == "/var/log/syslog")
    }

    /// The root is the case worth having: it already ends in a slash, so
    /// joining blindly would ask the server for `//etc`.
    @Test("a child of the root does not get two slashes")
    func rootPath() {
        #expect(Places.path("/", "etc") == "/etc")
    }

    @Test("a directory written with a trailing slash behaves the same")
    func trailingSlash() {
        #expect(Places.path("/home/deploy/", "notes.txt") == "/home/deploy/notes.txt")
    }

    // MARK: what the replace question offers

    @Test("one file is skipped or replaced, several are them")
    func wording() {
        #expect(Places.skipping(1) == "Skip it")
        #expect(Places.replacing(1) == "Replace")
        #expect(Places.skipping(2) == "Skip them")
        #expect(Places.replacing(40) == "Replace them")
    }

    // MARK: where its operations go

    /// The empty session is this Mac to the engine, so the one pane that must
    /// never hand it over is one pointed at a host with no session yet — the
    /// state a pane is in while it connects and after a host refuses.
    @Test("a pane on a host with no session open reaches nothing")
    func noSessionReachesNothing() {
        #expect(Places.session(chosen: true, onAHost: true, open: "") == nil)
        #expect(Places.session(chosen: true, onAHost: true, open: "s1") == "s1")
        #expect(Places.session(chosen: true, onAHost: false, open: "") == "",
                "this Mac is reached through the empty session")
        #expect(Places.session(chosen: false, onAHost: false, open: "") == nil,
                "a pane pointed nowhere is not this Mac")
    }

    // MARK: where it says what went wrong

    @Test("a failure shows over a listing, and in place of none")
    func failureIsShown() {
        #expect(Places.notice(listed: true, failure: "refused") == .banner)
        #expect(Places.notice(listed: false, failure: "refused") == .instead)
        #expect(Places.notice(listed: true, failure: nil) == Places.Notice.none)
    }

    @Test("a message from elsewhere ends as one sentence")
    func sentences() {
        #expect(Places.sentence("Failure") == "Failure.")
        #expect(Places.sentence("It is gone.") == "It is gone.")
    }

    // MARK: what deleting asks

    @Test("deleting on this Mac offers the Trash")
    func deletingHere() {
        let one = Places.deleteQuestion(["a.txt"], local: true, on: "This Mac")
        #expect(one.title == "Move “a.txt” to the Trash?")
        #expect(one.message == "You can put it back from the Trash.")
        #expect(one.confirm == "Move to Trash")
        let two = Places.deleteQuestion(["a.txt", "b.txt"], local: true, on: "This Mac")
        #expect(two.title == "Move 2 items to the Trash?")
        #expect(two.message == "You can put them back from the Trash.")
    }

    @Test("deleting on a host says it is final, in the right number")
    func deletingThere() {
        let one = Places.deleteQuestion(["logs"], local: false, on: "web")
        #expect(one.title == "Delete “logs”?")
        #expect(one.message == "It is deleted on web. This cannot be undone.")
        #expect(one.confirm == "Delete")
        let two = Places.deleteQuestion(["a", "b"], local: false, on: "web")
        #expect(two.message == "They are deleted on web. This cannot be undone.")
    }

    // MARK: a host it cannot reach

    /// SFTP's ssh runs with `BatchMode=yes`, so a host whose key it has never
    /// seen fails with this and nothing else — and a terminal tab is the one
    /// place the question can be answered.
    @Test("a host never connected to says so, and offers a terminal tab")
    func neverConnected() {
        let trouble = Places.trouble("Host key verification failed.", on: "staging-web")
        #expect(trouble.title == "staging-web hasn't been connected to yet")
        #expect(trouble.advice.contains("Open staging-web once in a terminal tab"))
        #expect(trouble.offersTerminal)
    }

    /// The same last line, for the opposite reason: a terminal tab would be
    /// turned away too, so it is not offered.
    @Test("a key that changed is not taken for a host never met")
    func changedKey() {
        let said = """
            @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
            Host key verification failed.
            """
        let trouble = Places.trouble(said, on: "web")
        #expect(trouble.title == "web's key has changed")
        #expect(!trouble.offersTerminal)
    }

    @Test("a host that takes only a password says SFTP needs a key")
    func passwordOnly() {
        let trouble = Places.trouble("deploy@192.0.2.21: Permission denied (password).", on: "db-01")
        #expect(trouble.title == "SFTP needs a key for db-01")
        #expect(trouble.offersTerminal)
        let interactive = Places.trouble(
            "deploy@192.0.2.21: Permission denied (keyboard-interactive).", on: "db-01")
        #expect(interactive.title == "SFTP needs a key for db-01")
    }

    /// Takes keys, and turned down every one: a terminal tab helps only where
    /// the host would take a password instead.
    @Test("a host that turned down the key offers a terminal only if it takes a password")
    func keyTurnedDown() {
        let both = Places.trouble("deploy@web: Permission denied (publickey,password).", on: "web")
        #expect(both.title == "web turned down the key")
        #expect(both.offersTerminal)
        let keysOnly = Places.trouble("deploy@web: Permission denied (publickey).", on: "web")
        #expect(keysOnly.title == "web turned down the key")
        #expect(!keysOnly.offersTerminal)
    }

    @Test("anything else is a connection that failed, said plainly where ssh's line is known")
    func otherwise() {
        let refused = Places.trouble("ssh: connect to host 127.0.0.1 port 1: Connection refused", on: "web")
        #expect(refused.title == "Couldn't connect to web")
        #expect(refused.advice == "The machine answered, but nothing is listening on port 1.")
        #expect(!refused.offersTerminal)
        #expect(Places.trouble("something new", on: "web").advice.isEmpty)
    }

    @Test("a folder on this Mac is written from ~, and nothing else is")
    func abbreviated() {
        #expect(Places.abbreviated("/Users/me/Projects/site", home: "/Users/me") == "~/Projects/site")
        #expect(Places.abbreviated("/Users/me", home: "/Users/me") == "~")
        #expect(Places.abbreviated("/Users/meadow/x", home: "/Users/me") == "/Users/meadow/x")
        #expect(Places.abbreviated("/var/www", home: "/Users/me") == "/var/www")
    }
}
