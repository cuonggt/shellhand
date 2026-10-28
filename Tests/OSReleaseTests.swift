import Foundation
import Testing

@testable import Shellhand

/// Reading `/etc/os-release`, which is how a host says what it is.
///
/// The fixtures are the real files, as the distributions ship them — quoting
/// and all — because the quoting is the part that varies and the part a
/// hand-written sample would get tidy and wrong.
@Suite("os-release")
nonisolated struct OSReleaseTests {
    private let ubuntu = """
        PRETTY_NAME="Ubuntu 22.04.3 LTS"
        NAME="Ubuntu"
        VERSION_ID="22.04"
        VERSION="22.04.3 LTS (Jammy Jellyfish)"
        VERSION_CODENAME=jammy
        ID=ubuntu
        ID_LIKE=debian
        HOME_URL="https://www.ubuntu.com/"
        """

    private let debian = """
        PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
        NAME="Debian GNU/Linux"
        VERSION_ID="12"
        ID=debian
        HOME_URL="https://www.debian.org/"
        """

    private let alpine = """
        NAME="Alpine Linux"
        ID=alpine
        VERSION_ID=3.19.1
        PRETTY_NAME="Alpine Linux v3.19"
        """

    // MARK: which distribution

    @Test("an unquoted id is read")
    func unquoted() {
        #expect(OSRelease.id(from: ubuntu) == "ubuntu")
        #expect(OSRelease.id(from: debian) == "debian")
        #expect(OSRelease.id(from: alpine) == "alpine")
    }

    /// Both spellings are in the wild, and the quotes are not the answer.
    @Test("a quoted id is read without its quotes")
    func quoted() {
        #expect(OSRelease.id(from: #"ID="fedora""#) == "fedora")
        #expect(OSRelease.id(from: "ID='arch'") == "arch")
    }

    @Test("an id is lowercased, because a mark is looked up by it")
    func lowercased() {
        #expect(OSRelease.id(from: "ID=Fedora") == "fedora")
    }

    /// A derivative that names only what it is built on still gets the right
    /// family's mark, which beats no mark at all.
    @Test("ID_LIKE stands in when there is no ID")
    func likeStandsIn() {
        #expect(OSRelease.id(from: "ID_LIKE=debian") == "debian")
        // Most-alike first, so the first word wins.
        #expect(OSRelease.id(from: #"ID_LIKE="rhel fedora""#) == "rhel")
    }

    @Test("ID wins over ID_LIKE when both are there")
    func ownNameWins() {
        #expect(OSRelease.id(from: ubuntu) == "ubuntu")
    }

    // MARK: what it calls itself

    @Test("the pretty name is what it says in words")
    func prettyName() {
        #expect(OSRelease.name(from: ubuntu) == "Ubuntu 22.04.3 LTS")
        #expect(OSRelease.name(from: debian) == "Debian GNU/Linux 12 (bookworm)")
    }

    @Test("NAME stands in when there is no PRETTY_NAME")
    func plainName() {
        #expect(OSRelease.name(from: #"NAME="Void Linux""#) == "Void Linux")
    }

    // MARK: files that say nothing useful

    /// Somebody else's file. A line this does not understand is not a reason
    /// to report nothing about the ones it does.
    @Test("comments, blanks and junk are stepped over")
    func junkIsSkipped() {
        let messy = """
            # written by the vendor

            this line has no equals sign
            ID=opensuse-leap
            =novalue
            """
        #expect(OSRelease.id(from: messy) == "opensuse-leap")
    }

    /// A file fetched from a machine carries that machine's line endings, and
    /// Swift reads CRLF as a single Character — so a parser splitting on "\\r"
    /// alone matches neither half.
    @Test("CRLF line endings read the same as LF")
    func crlf() {
        #expect(OSRelease.id(from: "NAME=\"Ubuntu\"\r\nID=ubuntu\r\n") == "ubuntu")
    }

    @Test("a file with nothing it understands reports nothing")
    func nothingUseful() {
        #expect(OSRelease.id(from: "") == "")
        #expect(OSRelease.id(from: "NAME=\"Something\"") == "")
        #expect(OSRelease.name(from: "") == "")
    }

    /// An empty value is not an answer, and must fall through rather than
    /// being reported as a distribution with no name.
    @Test("an empty ID falls through to ID_LIKE")
    func emptyIDFallsThrough() {
        #expect(OSRelease.id(from: "ID=\nID_LIKE=debian") == "debian")
    }
}
