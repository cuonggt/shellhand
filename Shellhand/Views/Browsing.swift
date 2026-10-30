import Foundation

/// Where the host pane is looking, which is **not** the same as what is
/// selected.
///
/// Out here rather than inside `ContentView` for the reason `Panes` and
/// `SidebarRows` are: a rule that lives in a view can only be checked by
/// driving the view, and this app's window does not answer to `click at`.
///
/// **These were one value, and that could not survive a selectable pane.**
/// The pane took `selectedGroup`, which is nil whenever a host is selected,
/// because `Selection` is an either/or. That was invisible while picking a
/// host *replaced* the pane with its details — but with the list staying up,
/// clicking a host inside Production would have widened the list to every
/// host and moved the row out from under the pointer. Selecting a thing and
/// going to a place are different acts, and only the second moves the pane.
nonisolated enum Browsing {
    /// Where the pane looks once `selection` is picked, given where it was.
    ///
    /// A group is a **place**, so picking one goes there. A host is a
    /// **thing**, so picking one leaves the place alone — which is what keeps
    /// the list still while you click down it, and what lets the inspector
    /// describe a host without the list beside it rearranging.
    ///
    /// Nothing selected also leaves it alone: clearing a selection is not a
    /// request to go anywhere, and sending the pane back to the whole list
    /// would lose the place somebody had navigated to.
    ///
    /// `hostsGroup` is the group the selected host is filed under, when the
    /// selection is a host and that host is known — nil otherwise.
    static func scope(
        after selection: Selection?, from scope: String, hostsGroup: String? = nil
    ) -> String {
        switch selection {
        case let .group(id):
            return id
        case .host:
            // One exception to "a host leaves the place alone", and the
            // sidebar is what forces it: the tree holds hosts as well as
            // groups, so it can select a host the pane is not showing. That
            // host would be selected **invisibly** — no row of its own in the
            // list, nothing highlighted, while the inspector describes it —
            // which reads as the selection having failed. So the pane follows
            // to where that host actually is. Nothing moves when the host is
            // already on screen, which is every click inside the pane itself.
            guard let hostsGroup else { return scope }
            return scope.isEmpty || hostsGroup == scope ? scope : hostsGroup
        case nil:
            return scope
        }
    }

    /// The same scope with a group that has gone since forgotten.
    ///
    /// A deleted group would otherwise leave the pane looking at a place that
    /// no longer exists — an empty list with a name above it and no way back
    /// but picking something else. The whole list is the honest answer.
    static func settled(_ scope: String, within groups: [Group]) -> String {
        groups.contains { $0.id == scope } ? scope : ""
    }

    /// A count of hosts, in words.
    static func counted(_ n: Int) -> String { n == 1 ? "1 host" : "\(n) hosts" }

    /// What a group holds, counted as **everything beneath it**. Production
    /// read "1 host" with seven in it, counting only the one filed directly
    /// there. `here` is the hosts filed directly in it, `groups` the groups
    /// directly inside.
    static func summary(inAll: Int, here: Int, groups: Int) -> String {
        guard groups > 0 else { return counted(inAll) }
        let inside = groups == 1 ? "1 group" : "\(groups) groups"
        guard here > 0 else { return "\(counted(inAll)) in \(inside)" }
        return "\(counted(inAll)): \(here) here, \(inAll - here) in \(inside)"
    }

    /// What a list narrowed by the search field or the tag bar says it shows.
    /// They narrowed the sidebar alone, so the pane beside it went on listing
    /// all twelve hosts next to the sidebar's three.
    static func narrowed(shown: Int, of total: Int, search: String, tags: Set<String>) -> String {
        var why: [String] = []
        let typed = search.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { why.append("matching “\(typed)”") }
        if !tags.isEmpty { why.append("tagged " + tags.sorted().joined(separator: " and ")) }
        return "\(shown) of \(total)" + (why.isEmpty ? "" : " · " + why.joined(separator: ", "))
    }

    /// Whether the search field or the tag bar is narrowing anything.
    static func narrowing(search: String, tags: Set<String>) -> Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty || !tags.isEmpty
    }
}
