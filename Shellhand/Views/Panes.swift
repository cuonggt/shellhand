import Foundation

/// What picking a tab, splitting, and closing one do to the two panes.
///
/// Out here rather than inside `ContentView` for the reason `Validation` and
/// `TransferQueue` are where they are: a rule that lives in a view can only be
/// checked by driving the view, and this app's window does not answer to
/// `click at`. These earn the move more than most — every one of them has
/// been wrong in a way somebody noticed and reported, twice in the case of the
/// strip, and the trade in `picking` reads as a bug until you meet the case it
/// is for.
///
/// `ContentView` holds the state and obeys these; they hold no state of their
/// own, so the whole of the behaviour is reachable from a test with two
/// values and a list.
nonisolated enum Panes {
    /// Picking a tab: what ends up in front, and what ends up beside it.
    ///
    /// Picking the tab already shown **beside** this one trades the two
    /// places rather than drawing the same thing twice. A terminal is one
    /// view and can only be in one place, so without the trade the second
    /// pane drew nothing at all.
    static func picking(
        _ tab: PaneTab, front: PaneTab, beside: PaneTab?
    ) -> (front: PaneTab, beside: PaneTab?) {
        (front: tab, beside: beside == tab ? front : beside)
    }

    /// ⌘D: open the split on the first open tab that is not already in front,
    /// or close it if it is open. The hosts are never offered as a side — the
    /// sidebar is already the list, so they are not one of the two things you
    /// would want to watch at once.
    static func splitting(front: PaneTab, beside: PaneTab?, open: [PaneTab]) -> PaneTab? {
        beside == nil ? open.first { $0 != front } : nil
    }

    /// Whether ⌘D is worth offering: not while the hosts are in front, and
    /// not with a single session, because there would be nothing to put
    /// beside it.
    static func canSplit(front: PaneTab, open: [PaneTab]) -> Bool {
        front != .hosts && open.count > 1
    }

    /// Where the front pane lands when the current terminal moves under it,
    /// which is what closing a tab does — to another session, or to nothing
    /// when that was the last one.
    ///
    /// A pane showing the hosts stays where it is: the list is not a session
    /// and nothing about it changed. That guard is the whole reason this is
    /// safe to drive from an `onChange` when setting the old `browsing` flag
    /// was not — closing really does move the value, every time.
    /// Whether the window meets somebody with the welcome instead of a
    /// host list.
    ///
    /// **It replaces the hosts tab, not the window.** It used to replace
    /// everything whenever the list was empty, and a local shell opened on a
    /// fresh install really started — a `-zsh` with a pid — behind a welcome
    /// screen, with the tab strip hidden too, so there was no way to see it,
    /// reach it or close it. The reason the welcome exists is that "All
    /// hosts, 0 hosts" is not what to meet; that reason says nothing about a
    /// terminal somebody has just asked for.
    static func welcoming(hosts: Int, loading: Bool, front: PaneTab) -> Bool {
        guard case .hosts = front else { return false }
        return hosts == 0 && !loading
    }

    /// Whether the strip of tabs is drawn.
    ///
    /// With a list, always, so the hosts tab is there to come back to. With
    /// no list, only once something is open — a fresh install meets the
    /// window it has always met rather than one tab leading nowhere, but a
    /// session has to be reachable the moment it exists.
    static func showsTabs(hosts: Int, loading: Bool, sessions: Int) -> Bool {
        sessions > 0 || hosts > 0 || loading
    }

    static func following(selected: UUID?, front: PaneTab) -> PaneTab {
        guard case .session = front else { return front }
        return selected.map(PaneTab.session) ?? .hosts
    }
}
