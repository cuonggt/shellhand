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

    // MARK: stepping through the strip

    @Test("the next tab after the hosts is the first session, and so on along the strip")
    func stepsForward() {
        let open = [one, two, three]
        #expect(Panes.stepping(by: 1, from: .hosts, sessions: open) == one)
        #expect(Panes.stepping(by: 1, from: one, sessions: open) == two)
        #expect(Panes.stepping(by: 1, from: two, sessions: open) == three)
    }

    @Test("the previous tab walks the strip the other way")
    func stepsBack() {
        let open = [one, two, three]
        #expect(Panes.stepping(by: -1, from: three, sessions: open) == two)
        #expect(Panes.stepping(by: -1, from: one, sessions: open) == .hosts)
    }

    /// Round from the last to the first and back, the way Terminal.app and
    /// Safari go — stopping at an end would make the key do nothing exactly
    /// where somebody pressing it twice expects to come back round.
    @Test("stepping goes round at both ends")
    func wraps() {
        let open = [one, two, three]
        #expect(Panes.stepping(by: 1, from: three, sessions: open) == .hosts)
        #expect(Panes.stepping(by: -1, from: .hosts, sessions: open) == three)
    }

    /// Hosts and one session is the common case, and the two keys are then
    /// both a toggle between them.
    @Test("with one session, either key moves between it and the hosts")
    func togglesWithOne() {
        #expect(Panes.stepping(by: 1, from: .hosts, sessions: [one]) == one)
        #expect(Panes.stepping(by: 1, from: one, sessions: [one]) == .hosts)
        #expect(Panes.stepping(by: -1, from: .hosts, sessions: [one]) == one)
        #expect(Panes.stepping(by: -1, from: one, sessions: [one]) == .hosts)
    }

    @Test("with only the hosts there is nowhere to go, which greys the items out")
    func nowhereToGo() {
        #expect(Panes.stepping(by: 1, from: .hosts, sessions: []) == nil)
        #expect(Panes.stepping(by: -1, from: .hosts, sessions: []) == nil)
    }

    /// A front the strip no longer holds is where a closed session leaves
    /// the pane for an instant; it counts as the hosts, where the strip
    /// begins, rather than as nowhere.
    @Test("a front no longer in the strip steps from the hosts")
    func strayFront() {
        let gone = PaneTab.session(UUID())
        #expect(Panes.stepping(by: 1, from: gone, sessions: [one, two]) == one)
        #expect(Panes.stepping(by: -1, from: gone, sessions: [one, two]) == two)
    }

    // MARK: what ⌘T opens

    private let listed: (String) -> Bool = { ["web", "db"].contains($0) }

    /// **The bug this is for**: connected to `db` with `web` picked in the
    /// list, ⌘T opened `web`.
    @Test("with a session on a host in front, ⌘T opens that host, not the one selected")
    func newTabFollowsTheSession() {
        #expect(Panes.newTab(inFront: .host("db"), selected: "web", isListed: listed) == .host("db"))
    }

    @Test("with a local shell in front, ⌘T opens another local shell")
    func newTabOnALocalShell() {
        #expect(Panes.newTab(inFront: .localShell, selected: "web", isListed: listed) == .localShell)
    }

    /// A group picked in the list, or nothing, greyed ⌘T out with a terminal
    /// right there.
    @Test("a terminal in front opens another of itself whatever the list has picked")
    func newTabIgnoresTheSelection() {
        #expect(Panes.newTab(inFront: .host("db"), selected: nil, isListed: listed) == .host("db"))
        #expect(Panes.newTab(inFront: .localShell, selected: nil, isListed: listed) == .localShell)
    }

    @Test("with the hosts in front, ⌘T opens the host selected, and nothing without one")
    func newTabFromTheList() {
        #expect(Panes.newTab(inFront: nil, selected: "web", isListed: listed) == .host("web"))
        #expect(Panes.newTab(inFront: nil, selected: nil, isListed: listed) == nil)
    }

    /// Falling back to the selection here would open some other machine,
    /// which is the very surprise the rule exists to end.
    @Test("a session on a host since deleted opens nothing, not the selection")
    func newTabOnADeletedHost() {
        #expect(Panes.newTab(inFront: .host("gone"), selected: "web", isListed: listed) == nil)
    }

    @Test("a selection the list no longer holds opens nothing")
    func newTabOnAStaleSelection() {
        #expect(Panes.newTab(inFront: nil, selected: "gone", isListed: listed) == nil)
    }

    // MARK: what the Host menu acts on

    /// With a session in front, ⌘B, ⌘E, ⇧⌘C and ⌘↩ acted on the sidebar's
    /// selection while the title and the inspector named the session's host:
    /// ⌘B on a terminal on `db` opened SFTP on `web`.
    @Test("with a session in front, the Host menu acts on its host, not the selection")
    func subjectFollowsTheSession() {
        #expect(Panes.subject(inFront: .host("db"), selected: "web", isListed: listed) == "db")
        #expect(Panes.subject(inFront: .host("db"), selected: nil, isListed: listed) == "db")
    }

    @Test("with the hosts in front, the Host menu acts on the host selected")
    func subjectFromTheList() {
        #expect(Panes.subject(inFront: nil, selected: "web", isListed: listed) == "web")
        #expect(Panes.subject(inFront: nil, selected: nil, isListed: listed) == nil)
        #expect(Panes.subject(inFront: nil, selected: "gone", isListed: listed) == nil)
    }

    /// Nothing listed to act on, and reaching for the selection instead would
    /// act on a machine that is not the one on screen.
    // MARK: what the inspector describes

    /// "Nothing selected" stood beside a picked group, a terminal on this Mac
    /// and a machine typed into ⌘K, each of which has plenty to say.
    @Test("the inspector describes what the tab in front is about")
    func inspectsTheTabInFront() {
        let typed = Shellhand.Host(name: "root@10.0.1.5", addr: "10.0.1.5", user: "root")
        #expect(Panes.inspected(inFront: .host("db"), selectedHost: "web", selectedGroup: nil,
                                isListed: listed) == .host("db"))
        #expect(Panes.inspected(inFront: .unsaved(typed), selectedHost: "web", selectedGroup: nil,
                                isListed: listed) == .unsaved(typed))
        #expect(Panes.inspected(inFront: .localShell, selectedHost: "web", selectedGroup: nil,
                                isListed: listed) == .localShell)
        #expect(Panes.inspected(inFront: .host("gone"), selectedHost: "web", selectedGroup: nil,
                                isListed: listed) == .nothing)
    }

    @Test("with the hosts in front, the inspector describes the host or group picked")
    func inspectsThePick() {
        #expect(Panes.inspected(inFront: nil, selectedHost: "web", selectedGroup: nil,
                                isListed: listed) == .host("web"))
        #expect(Panes.inspected(inFront: nil, selectedHost: nil, selectedGroup: "prod",
                                isListed: listed) == .group("prod"))
        #expect(Panes.inspected(inFront: nil, selectedHost: nil, selectedGroup: nil,
                                isListed: listed) == .nothing)
        #expect(Panes.inspected(inFront: nil, selectedHost: "gone", selectedGroup: nil,
                                isListed: listed) == .nothing)
    }

    /// Save as Host… opens New Host on the machine as typed, named by its
    /// address rather than by the whole of `user@host:port`.
    @Test("a machine from ⌘K is saved as typed, named by its address")
    func savingATypedMachine() {
        let typed = Shellhand.Host(name: "root@10.0.1.5:2222", addr: "10.0.1.5", port: 2222, user: "root")
        let saved = UnsavedHostInspector.savable(typed)
        #expect(saved.id.isEmpty)
        #expect(saved.name == "10.0.1.5")
        #expect(saved.addr == "10.0.1.5")
        #expect(saved.user == "root")
        #expect(saved.port == 2222)
    }

    @Test("a local shell, a ⌘K machine or a deleted host leaves the Host menu nothing")
    func subjectWithNothingListed() {
        let typed = Shellhand.Host(name: "root@10.0.1.5", addr: "10.0.1.5", user: "root")
        #expect(Panes.subject(inFront: .localShell, selected: "web", isListed: listed) == nil)
        #expect(Panes.subject(inFront: .unsaved(typed), selected: "web", isListed: listed) == nil)
        #expect(Panes.subject(inFront: .host("gone"), selected: "web", isListed: listed) == nil)
    }

    /// Typed into ⌘K, it is in no list to be looked up in, so it is carried
    /// whole — and is never "deleted since", having never been saved.
    @Test("a session to a machine typed into ⌘K opens another of itself")
    func newTabOnAnUnsavedHost() {
        let typed = Shellhand.Host(name: "root@10.0.1.5", addr: "10.0.1.5", user: "root")
        #expect(Panes.newTab(inFront: .unsaved(typed), selected: "web", isListed: listed)
            == .unsaved(typed))
    }

    // MARK: what a session is a session of, and what its tab can open

    @Test("a session is of a saved host by id, of a typed one whole, or of this Mac")
    func openingOfASession() {
        let saved = Shellhand.Host(id: "db", name: "db", addr: "10.0.1.5")
        let typed = Shellhand.Host(name: "root@10.0.1.5", addr: "10.0.1.5", user: "root")
        #expect(Panes.Opening.of(saved) == .host("db"))
        #expect(Panes.Opening.of(typed) == .unsaved(typed))
        #expect(Panes.Opening.of(nil) == .localShell)
    }

    /// SFTP opens from a list entry, so only a saved host still listed
    /// offers it — a local shell is this Mac, which the window's left side
    /// already is, and a typed machine has no entry.
    @Test("a tab offers SFTP only for a saved host the list still holds")
    func sftpFromATab() {
        let typed = Shellhand.Host(name: "root@10.0.1.5", addr: "10.0.1.5", user: "root")
        #expect(Panes.sftp(for: .host("db"), isListed: listed) == "db")
        #expect(Panes.sftp(for: .host("gone"), isListed: listed) == nil)
        #expect(Panes.sftp(for: .localShell, isListed: listed) == nil)
        #expect(Panes.sftp(for: .unsaved(typed), isListed: listed) == nil)
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
    // MARK: the welcome, and what it stands in for

    /// **The bug this is for**: the welcome replaced the whole window while
    /// the list was empty, so a local shell opened on a fresh install really
    /// started — a shell with a pid — behind it, with the tab strip hidden
    /// too. Nothing could see it, reach it or close it.
    @Test("a session is shown even with no hosts yet")
    func sessionBeatsTheWelcome() {
        let id = UUID()
        #expect(!Panes.welcoming(hosts: 0, loading: false, front: .session(id)))
        #expect(Panes.showsTabs(sessions: 1))
    }

    /// And the reason the welcome exists is untouched: with nothing open and
    /// nothing in the list, "All hosts, 0 hosts" is not what to meet.
    @Test("a fresh install still meets the welcome")
    func freshInstallIsWelcomed() {
        #expect(Panes.welcoming(hosts: 0, loading: false, front: .hosts))
        #expect(!Panes.showsTabs(sessions: 0))
    }

    /// A list that has not been read yet is not an empty list — otherwise
    /// the welcome flashes up on every launch before the store answers.
    @Test("a list still loading is not an empty one")
    func loadingIsNotEmpty() {
        #expect(!Panes.welcoming(hosts: 0, loading: true, front: .hosts))
    }

    /// The strip used to be drawn whenever there was a list, so with nothing
    /// open it held one tab, the one you were on — clutter, as CLAUDE.md had
    /// said it might read. It comes with the first session now.
    @Test("with hosts and nothing open, there is no strip of one tab")
    func withHosts() {
        #expect(!Panes.welcoming(hosts: 3, loading: false, front: .hosts))
        #expect(!Panes.showsTabs(sessions: 0))
        #expect(Panes.showsTabs(sessions: 2))
    }

    // MARK: reconnecting

    /// Reconnecting closed the tab and opened another at the end of the
    /// strip, put in front wherever the old one had been.
    @Test("a reconnected session goes where the one it replaces was")
    func replacing() {
        let old = UUID()
        let new = UUID()
        let inFront = Panes.replacing(old, with: new, front: .session(old), beside: one)
        #expect(inFront.front == .session(new))
        #expect(inFront.beside == one)
        let beside = Panes.replacing(old, with: new, front: one, beside: .session(old))
        #expect(beside.front == one)
        #expect(beside.beside == .session(new))
        // Reconnected from its own menu with another tab in front, nothing
        // moves.
        let elsewhere = Panes.replacing(old, with: new, front: .hosts, beside: two)
        #expect(elsewhere.front == .hosts)
        #expect(elsewhere.beside == two)
    }

    // MARK: side by side

    /// Out of the width there is, never more: Show Beside widened the window
    /// past the screen while the split decided its own widths.
    @Test("the split shares out the width it is given")
    func sharesTheWidth() {
        #expect(Panes.frontWidth(share: 0.5, of: 1000) == 500)
        #expect(Panes.frontWidth(share: 0.625, of: 1000) == 625)
        // The side beside keeps its minimum too, so the front stops short.
        #expect(Panes.frontWidth(share: 0.75, of: 1000) == 1000 - Panes.besideMinimum)
        // Dragged as far as it goes either way, each side keeps its minimum.
        #expect(Panes.frontWidth(share: 0.05, of: 1000) == Panes.besideMinimum)
        #expect(Panes.frontWidth(share: 1.4, of: 1000) == 1000 - Panes.besideMinimum)
    }

    @Test("too narrow for two minimums, the sides halve it")
    func halvesWhatThereIs() {
        #expect(Panes.frontWidth(share: 0.9, of: 500) == 250)
        #expect(Panes.frontWidth(share: 0.1, of: 500) == 250)
        #expect(Panes.frontWidth(share: 0.5, of: 0) == 0)
        #expect(Panes.frontWidth(share: 0.5, of: -10) == 0)
    }
}
