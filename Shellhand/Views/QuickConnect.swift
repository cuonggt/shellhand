import Foundation

/// Which hosts ⌘K offers for what has been typed, and where the highlight
/// goes when you press an arrow.
///
/// Out of the sheet for the same reason as `Panes`: a ranking rule is exactly
/// the kind of thing that is easy to get subtly wrong and impossible to check
/// by looking at it. Driving the real palette is worse than useless here —
/// `CLAUDE.md` records that synthetic keystrokes against a real host list
/// opened a session to a live machine, which is a high price for testing a
/// sort.
nonisolated enum QuickConnect {
    /// As many as the sheet will show. Fifty do not fit on screen; the cap is
    /// there so that typing one letter does not rank the whole list.
    static let limit = 50

    /// Everything whose name, address or tags hold what was typed, nearest
    /// first: a name that **starts** with it beats one that merely contains
    /// it, which beats a match on the address, which beats one on a tag.
    /// Hosts of equal standing come back in the order a person would file
    /// them, so the list does not reshuffle for reasons nobody can see.
    ///
    /// Typing nothing offers the list itself, alphabetically.
    static func matches(among hosts: [Host], for typed: String, limit: Int = limit) -> [Host] {
        let needle = typed.lowercased()
        guard !needle.isEmpty else {
            return Array(hosts.sorted(by: byName).prefix(limit))
        }
        return hosts
            .compactMap { host -> (Host, Int)? in
                let name = host.name.lowercased()
                if name.hasPrefix(needle) { return (host, 0) }
                if name.contains(needle) { return (host, 1) }
                if host.addr.lowercased().contains(needle) { return (host, 2) }
                if host.tags.contains(where: { $0.lowercased().contains(needle) }) { return (host, 3) }
                return nil
            }
            .sorted { $0.1 == $1.1 ? byName($0.0, $1.0) : $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Where the highlight goes for an arrow key.
    ///
    /// It stops at the ends rather than wrapping — the shape Spotlight has,
    /// where running off the bottom and reappearing at the top loses your
    /// place. A highlight on nothing, or on a host the list no longer holds
    /// because the typing moved on, starts again from the top.
    static func moved(from highlighted: String?, by delta: Int, over list: [Host]) -> String? {
        guard !list.isEmpty else { return nil }
        let at = list.firstIndex { $0.id == highlighted } ?? 0
        return list[min(max(at + delta, 0), list.count - 1)].id
    }

    private static func byName(_ a: Host, _ b: Host) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
