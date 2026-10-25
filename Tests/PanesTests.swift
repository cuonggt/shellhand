import Foundation
import Testing
@testable import Shellhand

/// The two panes: which tab is in front, what is beside it, and what the
/// strip, ⌘D and closing a tab do to that pair.
///
/// Deliberately no `Host` here, so this file can `import Foundation` for
/// `UUID` without `Host` becoming ambiguous with `Foundation.Host`.
@Suite("Panes")
nonisolated struct PanesTests {
    private let one = PaneTab.session(UUID())
    private let two = PaneTab.session(UUID())
    private let three = PaneTab.session(UUID())

    // MARK: picking a tab

    @Test("picking a tab puts it in front")
    func picks() {
        let after = Panes.picking(one, front: .hosts, beside: nil)
        #expect(after.front == one)
        #expect(after.beside == nil)
    }

    /// The bug that was reported twice. Clicking the tab you are already on
    /// has to land somewhere rather than quietly doing nothing, which is what
    /// happened while the mode was a flag set from an `onChange`: writing an
    /// unchanged value fired nothing, and with one session open — the common
    /// case — the strip did not work at all.
    @Test("picking the tab already in front is not a no-op to be skipped")
    func picksTheSame() {
        let after = Panes.picking(one, front: one, beside: nil)
        #expect(after.front == one)
        #expect(after.beside == nil)
    }

    @Test("picking the tab shown beside this one trades the two places")
    func trades() {
        let after = Panes.picking(two, front: one, beside: two)
        #expect(after.front == two)
        #expect(after.beside == one, "the old front moves to the side rather than vanishing")
    }

    @Test("picking a third tab while split replaces the front and leaves the side")
    func replacesFront() {
        let after = Panes.picking(three, front: one, beside: two)
        #expect(after.front == three)
        #expect(after.beside == two)
    }

    @Test("the hosts trade places like any other tab")
    func tradesWithHosts() {
        let after = Panes.picking(.hosts, front: one, beside: .hosts)
        #expect(after.front == .hosts)
        #expect(after.beside == one)
    }

    // MARK: the split

    @Test("splitting opens on the first open tab that is not in front")
    func splits() {
        #expect(Panes.splitting(front: one, beside: nil, open: [one, two, three]) == two)
        #expect(Panes.splitting(front: two, beside: nil, open: [one, two, three]) == one)
    }

    @Test("splitting again closes it")
    func unsplits() {
        #expect(Panes.splitting(front: one, beside: two, open: [one, two]) == nil)
    }

    @Test("there is nothing to put beside the only session")
    func nothingToSplitWith() {
        #expect(Panes.splitting(front: one, beside: nil, open: [one]) == nil)
    }

    @Test("the hosts are never offered as the other side")
    func hostsAreNotASide() {
        // The sidebar is already the list, so the hosts are not one of the two
        // things anyone wants to watch at once. `open` holds sessions only,
        // which is what keeps them out.
        #expect(Panes.splitting(front: .hosts, beside: nil, open: []) == nil)
        #expect(Panes.splitting(front: one, beside: nil, open: [one]) == nil)
    }

    @Test("⌘D is offered only with a session in front and another to show")
    func offered() {
        #expect(Panes.canSplit(front: .hosts, open: [one, two]) == false)
        #expect(Panes.canSplit(front: one, open: [one]) == false)
        #expect(Panes.canSplit(front: one, open: [one, two]) == true)
    }

    // MARK: closing a tab moves the selection under the pane

    @Test("a pane on a session follows the selection to another session")
    func followsToAnother() {
        guard case let .session(id) = two else { return }
        #expect(Panes.following(selected: id, front: one) == two)
    }

    @Test("a pane on the last session falls back to the hosts")
    func followsToHosts() {
        #expect(Panes.following(selected: nil, front: one) == .hosts)
    }

    @Test("a pane showing the hosts stays there whatever the selection does")
    func hostsStay() {
        guard case let .session(id) = one else { return }
        #expect(Panes.following(selected: id, front: .hosts) == .hosts)
        #expect(Panes.following(selected: nil, front: .hosts) == .hosts)
    }
}
