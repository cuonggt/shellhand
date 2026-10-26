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
}
