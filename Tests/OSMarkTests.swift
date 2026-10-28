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

    /// None are bundled yet — they are trademarks and shipping them is a
    /// decision of its own — so every host draws the fallback today. This
    /// pins that the absence is handled rather than crashing or drawing a
    /// broken-image placeholder.
    @Test("a mark that is not bundled is simply not there")
    func notBundled() {
        #expect(OSMark.image(for: "ubuntu") == nil)
        #expect(OSMark.image(for: "") == nil)
    }

    /// **The guard for the whole drop-in convention**, and the reason the
    /// folder's `README.md` is left in the resources phase rather than
    /// excluded from it.
    ///
    /// Everything else here is pure, so all of it would go on passing if
    /// `Resources/OSMarks` stopped reaching the bundle altogether — a file
    /// dropped in would simply never be found, and the only symptom is the
    /// generic glyph, which is also what a correct miss looks like. Nothing
    /// could tell them apart.
    ///
    /// So this asserts on the one file in that folder that is certain to be
    /// there. It is an odd thing to ship inside an app and it buys a real
    /// check: XcodeGen walks the directory and adds each file individually,
    /// so they land at the **top** of `Contents/Resources` — which is where
    /// `url(forResource:withExtension:)` looks, and would not be if the
    /// folder were ever added as a folder reference instead.
    @Test("files in the marks folder reach the bundle where a lookup finds them")
    func theFolderIsBundled() {
        #expect(Bundle.main.url(forResource: "README", withExtension: "md") != nil)
    }
}
