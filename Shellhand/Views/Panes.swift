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

    /// Reconnecting: the new session goes wherever the one it replaces was,
    /// in front or beside, and nothing else moves.
    static func replacing(
        _ old: UUID, with new: UUID, front: PaneTab, beside: PaneTab?
    ) -> (front: PaneTab, beside: PaneTab?) {
        let swap = { (tab: PaneTab) in tab == .session(old) ? PaneTab.session(new) : tab }
        return (front: swap(front), beside: beside.map(swap))
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

    /// ⌘⇧] and ⌘⇧[, and ⌃⇥ and ⌃⇧⇥: the tab after or before the one in
    /// front, in the order the strip draws them — the hosts, then each
    /// session as it was opened — and round from the last to the first, the
    /// way Terminal.app and Safari go. Nil when the strip holds nothing else
    /// to go to, which is what greys the menu items out.
    ///
    /// **The hosts are a stop, unlike in `splitting`.** They lead the strip
    /// and cannot be closed, so stepping that skipped them would leave a tab
    /// on screen that the keys could not reach.
    ///
    /// A front the strip no longer holds — a session closed under it — counts
    /// as the hosts, where the strip begins.
    static func stepping(by offset: Int, from front: PaneTab, sessions: [PaneTab]) -> PaneTab? {
        let strip = [PaneTab.hosts] + sessions
        guard strip.count > 1 else { return nil }
        let here = strip.firstIndex(of: front) ?? 0
        let count = strip.count
        return strip[((here + offset) % count + count) % count]
    }

    /// What a session is a session of — a host, by id, one typed into ⌘K
    /// and saved nowhere, or this Mac — which is also what ⌘T opens another
    /// of.
    nonisolated enum Opening: Equatable {
        case host(String)
        /// Carried whole, since there is no list to look it up in.
        case unsaved(Host)
        case localShell

        /// What a session on this host is a session of: a local shell for
        /// none, the machine itself for one saved nowhere — its id is empty —
        /// and the list's entry for the rest.
        static func of(_ host: Host?) -> Opening {
            guard let host else { return .localShell }
            return host.id.isEmpty ? .unsaved(host) : .host(host.id)
        }
    }

    /// Which saved host a tab's SFTP opens on: the one its session is on,
    /// while the list still has it. A local shell is this Mac, which the SFTP
    /// window's left side already is, and a machine typed into ⌘K has no
    /// list entry for a file session to be opened from — so neither offers
    /// it.
    static func sftp(for opening: Opening, isListed: (String) -> Bool) -> String? {
        guard case let .host(id) = opening, isListed(id) else { return nil }
        return id
    }

    /// ⌘T: another session like the one in front — to the same host, or
    /// another local shell for a local shell — and with the hosts in front,
    /// the host the list has selected. Nil when there is nothing to open,
    /// which greys the item out.
    ///
    /// **The session in front wins over the selection.** ⌘T used to open
    /// whatever the list had selected, whatever was in front, and the two
    /// need not be the same machine: connect to `db` through ⌘K with `web`
    /// picked in the list and ⌘T opened `web`, and with a group picked it was
    /// greyed out with a terminal right there. In every terminal app ⌘T
    /// means another of this one.
    ///
    /// A session on a host since deleted opens **nothing** rather than
    /// falling back to the selection: the argv is built from the list, and
    /// quietly opening some other machine is the surprise this is here to
    /// end.
    static func newTab(
        inFront: Opening?, selected: String?, isListed: (String) -> Bool
    ) -> Opening? {
        switch inFront {
        case let .host(id)?: isListed(id) ? .host(id) : nil
        case let .unsaved(host)?: .unsaved(host)
        case .localShell?: .localShell
        case nil: selected.flatMap { isListed($0) ? .host($0) : nil }
        }
    }

    /// Which listed host the Host menu, ⌘B and the toolbar's SFTP act on:
    /// **the one the tab in front is about**, by `newTab`'s rule. With a
    /// session in front they acted on the sidebar's selection, while the
    /// title and the inspector named the session's host — so ⌘B could open
    /// SFTP on a different machine from the one on screen. A local shell, a
    /// machine typed into ⌘K, or a host since deleted has no entry in the
    /// list, and the menu greys out rather than reaching for the selection.
    static func subject(
        inFront: Opening?, selected: String?, isListed: (String) -> Bool
    ) -> String? {
        switch inFront {
        case let .host(id)?: isListed(id) ? id : nil
        case .unsaved?, .localShell?: nil
        case nil: selected.flatMap { isListed($0) ? $0 : nil }
        }
    }

    /// What the inspector describes.
    nonisolated enum Inspected: Equatable {
        /// A listed host, by id, looked up live so an edit shows at once.
        case host(String)
        case group(String)
        /// A machine typed into ⌘K, carried whole: it is in no list.
        case unsaved(Host)
        case localShell
        case nothing
    }

    /// What the inspector describes, given the tab in front and the
    /// selection: what the tab is about, or with the hosts in front whatever
    /// is picked. It said "Nothing selected" beside a group picked in the list
    /// — with Edit Group live in the menu — beside a terminal on this Mac,
    /// and beside a machine typed into ⌘K that there was then no way to save.
    static func inspected(
        inFront: Opening?, selectedHost: String?, selectedGroup: String?,
        isListed: (String) -> Bool
    ) -> Inspected {
        switch inFront {
        case let .host(id)?: return isListed(id) ? .host(id) : .nothing
        case let .unsaved(host)?: return .unsaved(host)
        case .localShell?: return .localShell
        case nil:
            if let id = selectedHost, isListed(id) { return .host(id) }
            if let id = selectedGroup { return .group(id) }
            return .nothing
        }
    }

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

    /// Where the front pane lands when the current terminal moves under it,
    /// which is what closing a tab does — to another session, or to nothing
    /// when that was the last one.
    ///
    /// A pane showing the hosts stays where it is: the list is not a session
    /// and nothing about it changed. That guard is the whole reason this is
    /// safe to drive from an `onChange` when setting the old `browsing` flag
    /// was not — closing really does move the value, every time.
    static func following(selected: UUID?, front: PaneTab) -> PaneTab {
        guard case .session = front else { return front }
        return selected.map(PaneTab.session) ?? .hosts
    }
}
