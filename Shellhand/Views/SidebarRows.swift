import Foundation

/// One row of the sidebar, whether it stands for a group, a host, or the label
/// over a run of them.
nonisolated struct SidebarRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case header(String)
        case group(Group, expanded: Bool)
        case host(Host, showPath: Bool)
    }
    let id: String
    let kind: Kind
    let depth: Int
}

/// The whole sidebar as **one flat list**, and what the search field narrows
/// it to.
///
/// Flat is the point, not an implementation detail. The list holds a single
/// `ForEach` over one array, tree and search results alike, because two shapes
/// in one list left the rows of the shape it had just dropped still drawn over
/// the new ones. Keeping both shapes in one function is what makes that
/// mistake hard to make again — and testable, which it was not while the rows
/// were built inside the view.
nonisolated enum SidebarRows {
    /// The whole sidebar, in order.
    ///
    /// `matching` is `nil` when nothing is being searched for, and the tree is
    /// walked. When it is non-nil the search results replace the tree
    /// entirely — including when they are empty, which is a list of nothing
    /// rather than a tree.
    static func build(
        tree: Tree, collapsed: Set<String>, matching found: [Host]?
    ) -> [SidebarRow] {
        if let found {
            guard !found.isEmpty else { return [] }
            return [SidebarRow(id: "label:matching", kind: .header("Matching"), depth: 0)]
                + found.map {
                    SidebarRow(id: "host:\($0.id)", kind: .host($0, showPath: true), depth: 0)
                }
        }

        var out: [SidebarRow] = []
        // A title over the whole list, but only where there is a list: a
        // header above nothing is worse than no header, and the empty case
        // already has its own panel.
        if !tree.snapshot.hosts.isEmpty || !tree.snapshot.groups.isEmpty {
            out.append(SidebarRow(id: "label:hosts", kind: .header("Hosts"), depth: 0))
        }
        walk(tree: tree, under: "", depth: 0, seen: [], collapsed: collapsed, into: &out)

        let loose = tree.ungrouped
        if !loose.isEmpty {
            out.append(SidebarRow(id: "label:ungrouped", kind: .header("Ungrouped"), depth: 0))
            out += loose.map {
                SidebarRow(id: "host:\($0.id)", kind: .host($0, showPath: false), depth: 0)
            }
        }
        return out
    }

    /// Name, address, tags and the user a host ends up with, matched loosely
    /// enough that half a name finds it and strictly enough that the list
    /// stays short. Chosen tags narrow **together** — two mean both, not
    /// either.
    static func matches(in hosts: [Host], search: String, tags: Set<String>) -> [Host] {
        hosts
            .filter { host in
                guard tags.allSatisfy({ Tags.has($0, host) }) else { return false }
                guard !search.isEmpty else { return true }
                let needle = search.lowercased()
                return host.name.lowercased().contains(needle)
                    || host.addr.lowercased().contains(needle)
                    || host.tags.contains { $0.lowercased().contains(needle) }
                    || host.effective.user.lowercased().contains(needle)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Groups before hosts at every level, each level indented one further.
    ///
    /// `seen` carries down the branch rather than across the whole walk: a
    /// group that became its own ancestor stops this branch instead of the
    /// app. A folded group contributes its own row and nothing beneath it.
    private static func walk(
        tree: Tree, under parent: String, depth: Int,
        seen: Set<String>, collapsed: Set<String>, into out: inout [SidebarRow]
    ) {
        for group in tree.children(of: parent) where !seen.contains(group.id) {
            let open = !collapsed.contains(group.id)
            out.append(SidebarRow(
                id: "group:\(group.id)", kind: .group(group, expanded: open), depth: depth))
            guard open else { continue }
            walk(
                tree: tree, under: group.id, depth: depth + 1,
                seen: seen.union([group.id]), collapsed: collapsed, into: &out)
            out += tree.hosts(in: group.id).map {
                SidebarRow(id: "host:\($0.id)", kind: .host($0, showPath: false), depth: depth + 1)
            }
        }
    }
}
