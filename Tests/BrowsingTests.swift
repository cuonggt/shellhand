import Foundation
import Testing

@testable import Shellhand

/// Where the host pane looks, against what is selected.
///
/// The two were one value until the pane became selectable, and this suite is
/// the whole of the rule that separates them. It needs no window: the pane
/// obeys these and holds the state, so a couple of values and a list reach
/// every case.
///
/// Deliberately no `Host` here, so this file can `import Foundation` without
/// `Host` becoming ambiguous with `Foundation.Host` — the same reason
/// `PanesTests` and `ValidationTests` are careful about it.
@Suite("Browsing")
nonisolated struct BrowsingTests {
    private let production = Group(id: "g-prod", name: "Production")
    private let eu = Group(id: "g-eu", name: "EU", parentId: "g-prod")

    // MARK: a group is a place

    @Test("picking a group goes there")
    func groupMoves() {
        #expect(Browsing.scope(after: .group("g-prod"), from: "") == "g-prod")
    }

    @Test("picking another group goes there instead")
    func groupReplaces() {
        #expect(Browsing.scope(after: .group("g-eu"), from: "g-prod") == "g-eu")
    }

    // MARK: a host is a thing

    /// The whole point of the split. Without it the pane took `selectedGroup`,
    /// which is nil for a host — so clicking a host inside a group widened
    /// the list to every host and the row moved out from under the pointer.
    @Test("picking a host leaves the pane where it was")
    func hostStays() {
        #expect(Browsing.scope(after: .host("h-web"), from: "g-prod") == "g-prod")
    }

    @Test("picking a host while looking at the whole list stays there")
    func hostStaysAtTheTop() {
        #expect(Browsing.scope(after: .host("h-web"), from: "") == "")
    }

    /// Clearing a selection is not a request to go anywhere. Sending the pane
    /// back to the whole list would throw away the place somebody walked to.
    @Test("selecting nothing leaves the pane where it was")
    func nothingStays() {
        #expect(Browsing.scope(after: nil, from: "g-eu") == "g-eu")
    }

    // MARK: a host the pane is not showing

    /// The sidebar's tree holds hosts as well as groups, so it can select one
    /// the pane is not showing. Without this the host would be selected with
    /// nothing drawn as selected anywhere, while the inspector described it.
    @Test("a host outside the place being browsed brings the pane to it")
    func followsAHostElsewhere() {
        #expect(
            Browsing.scope(after: .host("h-edge"), from: "g-prod", hostsGroup: "g-eu") == "g-eu")
    }

    @Test("a host already on screen moves nothing")
    func staysForAHostInView() {
        #expect(
            Browsing.scope(after: .host("h-web"), from: "g-prod", hostsGroup: "g-prod") == "g-prod")
    }

    /// The whole list shows every host, so nothing is ever invisible there.
    @Test("browsing the whole list never follows anywhere")
    func theWholeListShowsEverything() {
        #expect(Browsing.scope(after: .host("h-edge"), from: "", hostsGroup: "g-eu") == "")
    }

    /// An unfiled host belongs to no group, and the whole list is the only
    /// place that shows it.
    @Test("an unfiled host brings the pane back to the whole list")
    func followsAnUnfiledHost() {
        #expect(Browsing.scope(after: .host("h-loose"), from: "g-prod", hostsGroup: "") == "")
    }

    @Test("a host nothing knows about moves nothing")
    func unknownHostStays() {
        #expect(Browsing.scope(after: .host("h-gone"), from: "g-prod") == "g-prod")
    }

    // MARK: a place that has gone

    @Test("a group still there is kept")
    func keepsWhatExists() {
        #expect(Browsing.settled("g-prod", within: [production, eu]) == "g-prod")
    }

    /// A deleted group would otherwise leave the pane naming a place that is
    /// not there, with an empty list under it.
    @Test("a group that has been deleted falls back to the whole list")
    func forgetsWhatIsGone() {
        #expect(Browsing.settled("g-prod", within: [eu]) == "")
    }

    @Test("the whole list is always a place it can be")
    func topIsAlwaysValid() {
        #expect(Browsing.settled("", within: [production, eu]) == "")
        #expect(Browsing.settled("", within: []) == "")
    }

    // MARK: what the pane says it holds

    /// The README picture's "Production — 1 host", for a group holding seven:
    /// one filed directly in it, six in its two groups.
    @Test("a group counts everything beneath it")
    func countsBeneath() {
        #expect(Browsing.summary(inAll: 7, here: 1, groups: 2) == "7 hosts: 1 here, 6 in 2 groups")
        #expect(Browsing.summary(inAll: 6, here: 0, groups: 2) == "6 hosts in 2 groups")
        #expect(Browsing.summary(inAll: 3, here: 3, groups: 0) == "3 hosts")
        #expect(Browsing.summary(inAll: 1, here: 0, groups: 1) == "1 host in 1 group")
        #expect(Browsing.counted(1) == "1 host")
        #expect(Browsing.counted(0) == "0 hosts")
    }

    /// The search field and the tag bar narrowed the sidebar alone, so the
    /// pane listed all twelve beside the sidebar's three.
    @Test("a narrowed list says what narrowed it")
    func narrowed() {
        #expect(Browsing.narrowed(shown: 3, of: 12, search: "", tags: ["db"])
            == "3 of 12 · tagged db")
        #expect(Browsing.narrowed(shown: 2, of: 12, search: " eu ", tags: [])
            == "2 of 12 · matching “eu”")
        #expect(Browsing.narrowed(shown: 1, of: 12, search: "api", tags: ["web", "eu"])
            == "1 of 12 · matching “api”, tagged eu and web")
    }

    @Test("blank search with no tags narrows nothing")
    func notNarrowing() {
        #expect(!Browsing.narrowing(search: "", tags: []))
        #expect(!Browsing.narrowing(search: "   ", tags: []))
        #expect(Browsing.narrowing(search: "db", tags: []))
        #expect(Browsing.narrowing(search: "", tags: ["db"]))
    }
}
