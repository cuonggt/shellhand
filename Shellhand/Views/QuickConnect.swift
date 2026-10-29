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

    /// One line of the palette: a saved host, or what was typed, connected
    /// to as typed.
    nonisolated enum Row: Identifiable, Equatable {
        case saved(Host)
        case typed(Destination)

        var id: String {
            switch self {
            case let .saved(host): host.id
            case let .typed(destination): "typed:" + destination.spelled
            }
        }
    }

    /// What the palette lists: the saved hosts that match, and — when what
    /// was typed reads as somewhere to connect — a row that connects to it as
    /// typed, for a machine that is not in the list.
    ///
    /// **Where that row goes is the rule.** A saved host that what was typed
    /// names exactly comes first, so its key and its jump host still apply:
    /// `10.0.1.5` is the host saved at that address, and `deploy@10.0.1.5` is
    /// too when that host logs in as `deploy`. Then the typed row, when it
    /// could only be a destination — it names a user or a port, or is a dotted
    /// or an IPv6 address — so that `10.0.1.5` is not beaten by a host at
    /// `10.0.1.50`, which merely contains it. A bare word is a search first,
    /// as it always was, so its row comes last: `web` is `web-1` before it is
    /// a machine called `web`.
    static func rows(among hosts: [Host], for typed: String, limit: Int = limit) -> [Row] {
        let found = matches(among: hosts, for: typed, limit: limit)
        guard let destination = destination(from: typed) else { return found.map(Row.saved) }
        guard destination.isUnmistakable else { return found.map(Row.saved) + [.typed(destination)] }
        let exact = hosts.filter { names($0, destination, typed) }.sorted(by: byName)
        let rest = found.filter { host in !exact.contains { $0.id == host.id } }
        return exact.map(Row.saved) + [.typed(destination)] + rest.map(Row.saved)
    }

    /// Whether what was typed is this saved host exactly: its name, or its
    /// address with no user and no port typed that say otherwise.
    private static func names(_ host: Host, _ destination: Destination, _ typed: String) -> Bool {
        let typed = typed.trimmingCharacters(in: .whitespaces)
        if host.name.caseInsensitiveCompare(typed) == .orderedSame { return true }
        guard host.addr.caseInsensitiveCompare(destination.host) == .orderedSame else { return false }
        if !destination.user.isEmpty && destination.user != host.effective.user { return false }
        if destination.port != 0 && destination.port != host.effective.port { return false }
        return true
    }

    /// A machine typed into ⌘K rather than picked from the list:
    /// `user@host:port`, with anything but the host left out.
    nonisolated struct Destination: Equatable {
        var user = ""
        var host: String
        /// 0 for ssh's default, which is what leaving it out means.
        var port = 0

        /// Written back the way ssh is typed: brackets round an IPv6
        /// address only where a port follows it, since that is the only place
        /// its colons are ambiguous.
        var spelled: String {
            let bracketed = port != 0 && host.contains(":") ? "[\(host)]" : host
            let at = user.isEmpty ? bracketed : "\(user)@\(bracketed)"
            return port == 0 ? at : "\(at):\(port)"
        }

        /// Whether this could only be somewhere to connect rather than part
        /// of a name: it has a user or a port, or is a dotted or an IPv6
        /// address.
        var isUnmistakable: Bool {
            !user.isEmpty || port != 0 || host.contains(".") || host.contains(":")
        }
    }

    /// What was typed, read as somewhere to connect: `host`, `user@host`,
    /// `host:port`, `user@host:port`, `[v6]:port`, or any of them after
    /// `ssh://`. Nil for anything else.
    ///
    /// **Nothing may start with `-`.** The destination is the last thing on
    /// ssh's command line, and ssh reads an argument that starts with one as
    /// an option — so `-oProxyCommand=…` typed here would be run rather than
    /// connected to. Everything else outside the letters, digits and the
    /// handful of marks a name or an address uses is refused for the same
    /// reason: this is handed to ssh as it stands.
    static func destination(from typed: String) -> Destination? {
        var text = Substring(typed.trimmingCharacters(in: .whitespaces))
        if text.lowercased().hasPrefix("ssh://") { text = text.dropFirst(6) }
        if text.hasSuffix("/") { text = text.dropLast() }
        guard !text.isEmpty else { return nil }

        var user: Substring = ""
        var rest = text
        if let at = text.lastIndex(of: "@") {
            user = text[..<at]
            rest = text[text.index(after: at)...]
            guard !user.isEmpty else { return nil }
        }

        var host = rest
        var port = 0
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            host = rest[rest.index(after: rest.startIndex)..<close]
            let after = rest[rest.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":"), let given = Self.port(after.dropFirst()) else { return nil }
                port = given
            }
        } else if rest.filter({ $0 == ":" }).count == 1, let colon = rest.firstIndex(of: ":") {
            // One colon is a port; more is an IPv6 address with none.
            host = rest[..<colon]
            guard let given = Self.port(rest[rest.index(after: colon)...]) else { return nil }
            port = given
        }

        guard !host.isEmpty, Self.made(of: host, marks: ".-_:%"),
              user.isEmpty || Self.made(of: user, marks: ".-_")
        else { return nil }
        return Destination(user: String(user), host: String(host), port: port)
    }

    /// The host a typed destination is connected as: in no group and saved
    /// nowhere, so its id is empty — which is what keeps it out of the list,
    /// out of the inspector and out of the once-a-day question about what it
    /// runs — and named as it was typed, which is what its tab says.
    static func unsaved(_ destination: Destination) -> Host {
        Host(name: destination.spelled, addr: destination.host,
             port: destination.port, user: destination.user)
    }

    /// 1 to 65535 in plain digits — not `+22`, which `Int` would take.
    private static func port(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.count <= 5, text.allSatisfy({ ("0"..."9").contains($0) }),
              let port = Int(text), (1...65535).contains(port)
        else { return nil }
        return port
    }

    /// ASCII letters and digits and the marks given, not starting with `-`.
    private static func made(of text: Substring, marks: String) -> Bool {
        guard text.first != "-" else { return false }
        return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || marks.contains($0)) }
    }

    /// Where the highlight goes for an arrow key.
    ///
    /// It stops at the ends rather than wrapping — the shape Spotlight has,
    /// where running off the bottom and reappearing at the top loses your
    /// place. A highlight on nothing, or on a row the list no longer holds
    /// because the typing moved on, starts again from the top.
    static func moved<Line: Identifiable>(
        from highlighted: String?, by delta: Int, over list: [Line]
    ) -> String? where Line.ID == String {
        guard !list.isEmpty else { return nil }
        let at = list.firstIndex { $0.id == highlighted } ?? 0
        return list[min(max(at + delta, 0), list.count - 1)].id
    }

    private static func byName(_ a: Host, _ b: Host) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
