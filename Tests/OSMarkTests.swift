import Foundation
import Testing

@testable import Shellhand

/// How a distribution id becomes a filename.
///
/// This is the **whole interface** between a mark somebody drops into
/// `Resources/OSMarks` and the code that looks for it — there is no list of
/// distributions anywhere, so the naming convention is the only agreement.
/// A change here stops every mark being found, silently, since a missing one
/// is a legitimate state that draws the plain server glyph.
@Suite("Distribution marks")
nonisolated struct OSMarkTests {
    @Test("an id becomes its file's name")
    func theName() {
        #expect(OSMark.resourceName(for: "ubuntu") == "os-ubuntu")
        #expect(OSMark.resourceName(for: "opensuse-leap") == "os-opensuse-leap")
    }

    /// `os-release` ids are lowercase by convention and `OSRelease` lowercases
    /// them anyway, but a file is looked up by exact name — so this settles
    /// the case rather than trusting the parser to have done it.
    @Test("case is settled here, not assumed")
    func caseIsSettled() {
        #expect(OSMark.resourceName(for: "Fedora") == "os-fedora")
        #expect(OSMark.resourceName(for: " debian\n") == "os-debian")
    }

    /// A host that has never connected, or one that could not be asked.
    @Test("nothing known means no name to look for")
    func nothingKnown() {
        #expect(OSMark.resourceName(for: "") == nil)
        #expect(OSMark.resourceName(for: "   ") == nil)
    }

    /// The id is read off a machine somebody else administers, and it ends up
    /// in a resource lookup. A separator in it would reach outside the
    /// bundle's own resources.
    @Test("an id that could walk out of the bundle is refused")
    func noWalkingOut() {
        #expect(OSMark.resourceName(for: "../../etc/passwd") == nil)
        #expect(OSMark.resourceName(for: "ubuntu/../../x") == nil)
        #expect(OSMark.resourceName(for: "..") == nil)
    }

    /// A distribution nobody has drawn a mark for. That is an ordinary state,
    /// not a failure: the host draws the plain glyph, exactly as one that has
    /// never been asked does.
    @Test("a mark that is not bundled is simply not there")
    func notBundled() {
        #expect(OSMark.image(for: "slackware") == nil)
        #expect(OSMark.image(for: "") == nil)
    }

    /// **The guard for the whole drop-in convention.**
    ///
    /// Everything else here is pure, so all of it would go on passing if
    /// `Resources/OSMarks` stopped reaching the bundle altogether — every
    /// mark would simply never be found, and the only symptom is the generic
    /// glyph, which is also what a correct miss looks like. Nothing could
    /// tell them apart.
    ///
    /// So this asks for a mark that is certainly there. XcodeGen walks that
    /// directory and adds each file individually, so they land at the **top**
    /// of `Contents/Resources` — which is where `url(forResource:)` looks,
    /// and would not be if the folder were ever added as a folder reference
    /// instead. It also covers the part no lookup can: that `NSImage` reads
    /// the SVG these are written as.
    @Test("a bundled mark is found and readable")
    func bundledMarkIsFound() {
        let ubuntu = OSMark.image(for: "ubuntu")
        #expect(ubuntu != nil)
        #expect(ubuntu?.size.width ?? 0 > 0)
        // Asked the way it comes off a machine, since that is the only way it
        // is ever asked.
        #expect(OSMark.image(for: "Ubuntu\n") != nil)
    }

    /// A derivative that names only what it is built on reaches its family's
    /// mark, which is the whole reason `ID_LIKE` is a fallback.
    @Test("the families a derivative falls back to are drawn")
    func familiesAreDrawn() {
        for family in ["debian", "rhel", "fedora", "linux"] {
            #expect(OSMark.image(for: family) != nil, "no mark for \(family)")
        }
    }
}
