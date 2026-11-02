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

    /// The hosts are never a side, as ⌘D never offers them: the trade put
    /// the host list beside the terminal.
    @Test("the tab that was beside comes in front alone from the hosts")
    func hostsAreNeverBeside() {
        let after = Panes.picking(two, front: .hosts, beside: two)
        #expect(after.front == two)
        #expect(after.beside == nil)
    }

    /// With the hosts in front nothing is beside on screen, so nothing says
    /// so; the split comes back with the next session picked. Its tab was
    /// outlined, and ⌘D read Hide Beside, over the host list alone.
    @Test("the split waits behind the hosts, unshown, and comes back")
    func splitWaitsBehindHosts() {
        let away = Panes.picking(.hosts, front: one, beside: two)
        #expect(away.front == .hosts)
        #expect(away.beside == two)
        #expect(Panes.shownBeside(front: away.front, beside: away.beside) == nil)
        let back = Panes.picking(one, front: away.front, beside: away.beside)
        #expect(back.front == one)
        #expect(back.beside == two)
        #expect(Panes.shownBeside(front: back.front, beside: back.beside) == two)
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

    /// Its inspector writes the address as a listed host's does, the port in
    /// it unless 22: it said "127.0.0.1" and gave the port a row of its own.
    @Test("a machine from ⌘K has its address written as a listed host's")
    func typedAddressLine() {
        let typed = Shellhand.Host(name: "root@127.0.0.1:1", addr: "127.0.0.1", port: 1, user: "root")
        #expect(UnsavedHostInspector.addressLine(of: typed) == "127.0.0.1:1")
        let plain = Shellhand.Host(name: "web", addr: "web.example.com", port: 22)
        #expect(UnsavedHostInspector.addressLine(of: plain) == "web.example.com")
        let six = Shellhand.Host(name: "six", addr: "2001:db8::5", port: 2222)
        #expect(UnsavedHostInspector.addressLine(of: six) == "[2001:db8::5]:2222")
    }

    /// Its Open now lists the tabs on the machine as typed: matched by the
    /// empty id every typed machine shares, it would list them all.
    @Test("a ⌘K machine's tabs are the ones typed the same way")
    func sameTypedMachine() {
        let typed = Shellhand.Host(name: "root@127.0.0.1:2", addr: "127.0.0.1", port: 2, user: "root")
        #expect(UnsavedHostInspector.sameMachine(typed, as: typed))
        var other = typed
        other.port = 1
        #expect(!UnsavedHostInspector.sameMachine(other, as: typed))
        other = typed
        other.user = "deploy"
        #expect(!UnsavedHostInspector.sameMachine(other, as: typed))
        // A listed host at the very address is a host of the list, not this.
        var listed = typed
        listed.id = "h1"
        #expect(!UnsavedHostInspector.sameMachine(listed, as: typed))
        // A local shell has no host.
        #expect(!UnsavedHostInspector.sameMachine(nil, as: typed))
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

    // MARK: the Window menu

    /// Two sessions on one host came out of the Window menu as one item
    /// twice, both on ⌘2 and nothing on ⌘4, SwiftUI matching items by title.
    @Test("sessions of one name are told apart in the Window menu")
    func menuTitlesDiffer() {
        #expect(Panes.menuTitles(["waiter", "refuser", "This Mac — ~", "refuser"])
            == ["waiter", "refuser", "This Mac — ~", "refuser (2)"])
        #expect(Panes.menuTitles(["web", "web", "web"]) == ["web", "web (2)", "web (3)"])
        // One already called what a second would be is still kept apart.
        #expect(Set(Panes.menuTitles(["web (2)", "web", "web"])).count == 3)
        #expect(Panes.menuTitles([]).isEmpty)
    }

    /// A tab cut its whole title in the middle, and "root@127.0.0.1:2 (2)"
    /// read "root…(2)": the port went, and the space before the number.
    /// A typed machine's tab cut in the middle read "root@….0.1:2", four
    /// dots in a row; it gives up its user first.
    @Test("a typed machine's tab drops its user before its address")
    func tabTitleWithoutUser() {
        #expect(Panes.tabTitleWithoutUser("root@127.0.0.1:2") == "127.0.0.1:2")
        #expect(Panes.tabTitleWithoutUser("deploy@[::1]:2222") == "[::1]:2222")
        #expect(Panes.tabTitleWithoutUser("web.example.com") == nil)
        #expect(Panes.tabTitleWithoutUser("root@") == nil)
    }

    /// Without its user, cut in its middle anywhere, a typed machine's
    /// address still read "127….1:2", the cut beside a dot, four in a row.
    /// An address gives up whole parts from between its dots, and no cut
    /// stands beside one.
    @Test("a tab's name is cut at its dots, never beside one")
    func tabTitleCuts() {
        #expect(Array(Panes.tabTitleCuts("root@127.0.0.1:2", typed: true).prefix(5))
            == ["root@127.0.0.1:2", "127.0.0.1:2", "127…0.1:2", "127…1:2", "…1:2"])
        // Where the shell is on it stays after the address.
        #expect(Array(Panes.tabTitleCuts("root@10.0.1.23 — ~", typed: true).prefix(5))
            == ["root@10.0.1.23 — ~", "10.0.1.23 — ~", "10…1.23 — ~", "10…23 — ~", "…23 — ~"])
        // A host's name keeps what it is called, and its first part to the last.
        #expect(Array(Panes.tabTitleCuts("db-01.us.example.com", typed: false).prefix(4))
            == ["db-01.us.example.com", "db-01.us…com", "db-01…com", "db-01…"])
        #expect(Panes.tabTitlePartCuts("example.com") == ["example…"])
        #expect(Panes.tabTitlePartCuts("192.168.100.200:2222")
            == ["192.168…200:2222", "192…200:2222", "…200:2222"])
        // No part to spare, or a space in it: nothing is dropped whole.
        #expect(Panes.tabTitlePartCuts("localhost").isEmpty)
        #expect(Panes.tabTitlePartCuts("v1.2 build box").isEmpty)
        #expect(Panes.tabTitlePartCuts("a..b").isEmpty)
        // A name with no dot is cut in its middle, as SwiftUI cut it, with
        // no space beside "…".
        #expect(Array(Panes.tabTitleCuts("This Mac — ~", typed: false).prefix(3))
            == ["This Mac — ~", "This…c — ~", "This…— ~"])
        #expect(Array(Panes.tabTitleCuts("refuser", typed: false).prefix(2)) == ["refuser", "ref…er"])
        // However far it goes, each cut is new and none stands beside a dot.
        for name in ["root@127.0.0.1:2", "deploy@192.168.100.200:2222 — ~/site.github.io",
                     "example.com", "a..b", ".hidden", "v1.2 build box — ~", "This Mac — ~"] {
            let cuts = Panes.tabTitleCuts(name, typed: true)
            #expect(cuts.first == name)
            #expect(Set(cuts).count == cuts.count)
            for cut in cuts.dropFirst() {
                #expect(!cut.contains(".…") && !cut.contains("…."), "\(cut)")
                #expect(!cut.contains(" …") && !cut.contains("… "), "\(cut)")
            }
        }
    }

    /// A tab draws the first of its spellings that fits, so one no narrower
    /// than a spelling before it would never be drawn, and the room the strip
    /// gave it for its width would stand empty.
    @Test("a tab's spellings each draw narrower than the one before")
    func tabTitleSteps() {
        let steps = Panes.tabTitleSteps(["127.0.0.1:2", "127…0.1:2", "12…:2", "127…1:2"],
                                        number: " (2)") { CGFloat($0.count) }
        #expect(steps.cuts == ["127.0.0.1:2", "127…0.1:2", "12…:2"])
        #expect(steps.widths == [15, 13, 9])
        // The spelling and its number are measured apart, as they are drawn,
        // each to what it takes on its own: measured as one, "…1:2 (2)" was
        // given half a point less than its two parts drew.
        #expect(Panes.tabTitleSteps(["…1:2"], number: " (2)") { CGFloat($0.count) + 0.5 }.widths
            == [9])
    }

    @Test("a tab's number stands apart from the name it cuts")
    func tabTitleParts() {
        #expect(Panes.tabTitleParts("root@127.0.0.1:2 (2)") == ("root@127.0.0.1:2", " (2)"))
        #expect(Panes.tabTitleParts("This Mac — ~ (12)") == ("This Mac — ~", " (12)"))
        #expect(Panes.tabTitleParts("refuser") == ("refuser", ""))
        // Brackets that hold no number are the name's own.
        #expect(Panes.tabTitleParts("web (eu)") == ("web (eu)", ""))
        #expect(Panes.tabTitleParts("web ()") == ("web ()", ""))
        #expect(Panes.tabTitleParts("(2)") == ("(2)", ""))
        // Whatever the parts, they make the title again.
        for title in Panes.menuTitles(["db (2)", "db", "db", "x"]) {
            let parts = Panes.tabTitleParts(title)
            #expect(parts.name + parts.number == title)
        }
    }

    // MARK: the strip

    /// Held at 180 each, a full strip scrolled and pushed the Hosts tab half
    /// off its edge; shared evenly, a long name was cut beside short ones
    /// with room to spare. The tabs share by need, and scroll only past 60.
    @Test("a full strip's tabs share its room by what each needs")
    func tabTitleWidths() {
        // Room for every name whole: each its own.
        #expect(Panes.tabTitleWidths(room: 1000, needs: [40, 300]) == [40, 180])
        // waiter, refuser, This Mac — ~ and refuser (2) in a strip where an
        // even share was 76 each: the short ones give the long one its 85.
        let tight: CGFloat = 4 * (76 + Panes.tabChrome) + 3 * Panes.tabSpacing
        #expect(Panes.tabTitleWidths(room: tight, needs: [40, 48, 85, 70]) == [40, 48, 85, 70])
        // Where even so they do not fit, the long ones share what is left.
        let short: CGFloat = 4 * (40 + Panes.tabChrome) + 3 * Panes.tabSpacing
        #expect(Panes.tabTitleWidths(room: short, needs: [30, 90, 90, 90])
            == [30, 60, 60, 60])
        let some: CGFloat = 3 * (100 + Panes.tabChrome) + 2 * Panes.tabSpacing
        #expect(Panes.tabTitleWidths(room: some, needs: [50, 200, 200]) == [50, 125, 125])
        // A tab waiting on an answer draws its badge too, which comes out of
        // the room before it is shared: left out, the strip scrolled.
        #expect(Panes.tabTitleWidths(room: tight + 70, needs: [40, 48, 85, 70], extras: [0, 0, 70, 0])
            == [40, 48, 85, 70])
        #expect(Panes.tabTitleWidths(room: tight, needs: [90, 90, 90, 90], extras: [0, 0, 0, 40])
            == [66, 66, 66, 66])
        // Before the strip has been measured, as they always were.
        #expect(Panes.tabTitleWidths(room: 0, needs: [10, 20]) == [180, 180])
        #expect(Panes.tabTitleWidths(room: 500, needs: []).isEmpty)
    }

    /// Given its share whole, a name cut at its dots or without its user
    /// stood with the rest of it empty before its ×: 19.5pt after
    /// "127.0.0.1:2", while "db-01…com" beside it was cut short of
    /// "db-01.us…com".
    @Test("a tab cut short takes what it draws, and the rest goes where it shows more")
    func tabTitleWidthsByCuts() {
        // Given 80 each, the typed machine draws "127.0.0.1:2" in 62 and
        // db-01 "db-01…com" in 72; what they leave takes db-01 to 93.
        let two: CGFloat = 2 * (80 + Panes.tabChrome) + Panes.tabSpacing
        #expect(Panes.tabTitleWidths(room: two, needs: [106, 125],
                                     cuts: [[106, 62, 57, 45], [125, 93, 72, 48]]) == [62, 93])
        // Past 180 a name takes the widest spelling within it.
        #expect(Panes.tabTitleWidths(room: 1000, needs: [250], cuts: [[250, 170, 120]]) == [170])
        // With no spelling within its share it keeps the share, for SwiftUI
        // to cut; and a name whole is left alone.
        #expect(Panes.tabTitleWidths(room: 100 + Panes.tabChrome, needs: [200], cuts: [[200, 150]])
            == [100])
        #expect(Panes.tabTitleWidths(room: 1000, needs: [40, 50], cuts: [[40, 20], [50]]) == [40, 50])
    }

    /// The tooltip was the shell's own title alone: "refuser" for the tab
    /// named "refuser (2)", and nothing of the name the strip had cut.
    @Test("a tab's tooltip is its whole name, and the shell's where it says more")
    func tabHelp() {
        #expect(Panes.tabHelp(title: "refuser (2)", sent: "refuser") == "refuser (2)")
        #expect(Panes.tabHelp(title: "This Mac — ~", sent: "me@mac:~")
            == "This Mac — ~\nme@mac:~")
        #expect(Panes.tabHelp(title: "web", sent: "") == "web")
    }

    /// At the window's default size four tabs fill the strip, and the first
    /// was shown sheared with nothing to say the strip scrolled.
    @Test("the strip fades the edges it has tabs past")
    func hiddenEdges() {
        // Everything in sight: no fade.
        #expect(Panes.hiddenEdges(offset: 0, shown: 403, content: 380) == .init())
        // Scrolled along to the tab in front, the last: tabs before it.
        #expect(Panes.hiddenEdges(offset: 49, shown: 403, content: 452)
            == .init(leading: true, trailing: false))
        // At the start of a full strip: tabs after it.
        #expect(Panes.hiddenEdges(offset: 0, shown: 403, content: 452)
            == .init(leading: false, trailing: true))
        // In the middle: both.
        #expect(Panes.hiddenEdges(offset: 20, shown: 403, content: 452)
            == .init(leading: true, trailing: true))
    }

    /// ⌘D closes the split while one is open, and its item said Show
    /// Beside all the same.
    @Test("⌘D's item says what it would do")
    func splitTitle() {
        #expect(Panes.splitTitle(besideOpen: false) == "Show Beside")
        #expect(Panes.splitTitle(besideOpen: true) == "Hide Beside")
    }

    /// It said Toggle Host Details, over a group as over a host.
    @Test("⌥⌘I's item names the inspector, and says what it would do")
    func inspectorTitle() {
        #expect(Panes.inspectorTitle(showing: true) == "Hide Inspector")
        #expect(Panes.inspectorTitle(showing: false) == "Show Inspector")
    }

    /// The system's own item drew this, and was read as Show Sidebar
    /// either way.
    @Test("⌃⌘S's item says what it would do")
    func sidebarTitle() {
        #expect(Panes.sidebarTitle(shown: true) == "Hide Sidebar")
        #expect(Panes.sidebarTitle(shown: false) == "Show Sidebar")
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
