import Foundation

/// The host list as a tree: what sits under what, what sits above it, and the
/// walks between them.
///
/// Filed once per snapshot rather than filtered per row. With a few hundred
/// hosts, a sidebar that filters the whole list in every row's body spends its
/// life doing it.
///
/// Out here, over a plain `Snapshot`, so the walks can be checked without a
/// database or a window. That matters more than it sounds: **every one of them
/// climbs or descends a tree that a bad edit could make circular, and every one
/// carries a guard against that.** A guard nothing has ever exercised is a
/// guard nobody should trust — and a group that became its own ancestor would
/// otherwise hang the app rather than draw a wrong row.
nonisolated struct Tree {
    let snapshot: Snapshot

    private let hostsByGroup: [String: [Host]]
    private let groupsByParent: [String: [Group]]

    init(_ snapshot: Snapshot = Snapshot()) {
        self.snapshot = snapshot
        hostsByGroup = Dictionary(grouping: snapshot.hosts, by: \.groupId)
            .mapValues { $0.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        groupsByParent = Dictionary(grouping: snapshot.groups, by: \.parentId)
            .mapValues { $0.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    }

    // MARK: looking things up

    func group(_ id: String) -> Group? { snapshot.groups.first { $0.id == id } }

    func host(_ id: String) -> Host? { snapshot.hosts.first { $0.id == id } }

    func children(of groupID: String) -> [Group] { groupsByParent[groupID] ?? [] }

    func hosts(in groupID: String) -> [Host] { hostsByGroup[groupID] ?? [] }

    /// The hosts filed nowhere, which the sidebar shows at the top level.
    var ungrouped: [Host] { hostsByGroup[""] ?? [] }

    // MARK: walking down

    /// Every host beneath a group, however deep, by name.
    func hostsBeneath(_ groupID: String) -> [Host] {
        var ids: Set<String> = [groupID]
        var frontier = [groupID]
        while let id = frontier.popLast() {
            for child in children(of: id) where !ids.contains(child.id) {
                ids.insert(child.id)
                frontier.append(child.id)
            }
        }
        return ids.flatMap { hostsByGroup[$0] ?? [] }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: walking up

    /// The name a group shows in a path, "Production / EU".
    func path(of group: Group) -> String {
        var parts = [group.name]
        var parent = group.parentId
        var seen: Set<String> = [group.id]
        while !parent.isEmpty, let next = self.group(parent), !seen.contains(next.id) {
            seen.insert(next.id)
            parts.insert(next.name, at: 0)
            parent = next.parentId
        }
        return parts.joined(separator: " / ")
    }

    /// The groups that have to be open for a host's row to be reachable: the
    /// one it is filed in, and everything above that.
    func ancestry(ofHost hostID: String) -> Set<String> {
        guard let host = host(hostID) else { return [] }
        return climb(from: host.groupId)
    }

    /// The groups that have to be open for a group's row to be reachable: its
    /// parents, and **not** itself. A group's own fold is its business — what
    /// matters is that the row can be reached.
    func ancestry(ofGroup groupID: String) -> Set<String> {
        climb(from: group(groupID)?.parentId ?? "")
    }

    // MARK: folding

    /// What starts folded on a first load: every group except the ones that
    /// have to stay open for whatever is selected to be visible.
    ///
    /// The selection restored at launch arrives *after* the groups do, so
    /// folding everything and stopping there would hide it.
    func folded(keepingVisible visible: Set<String>) -> Set<String> {
        Set(snapshot.groups.map(\.id)).subtracting(visible)
    }

    // MARK: the walk itself

    /// Up the parents from a group, gathering them, stopping if the tree
    /// turns back on itself. One set does for both the answer and the guard:
    /// everything visited is part of the answer.
    private func climb(from start: String) -> Set<String> {
        var out: Set<String> = []
        var id = start
        while !id.isEmpty, !out.contains(id) {
            out.insert(id)
            id = group(id)?.parentId ?? ""
        }
        return out
    }
}
