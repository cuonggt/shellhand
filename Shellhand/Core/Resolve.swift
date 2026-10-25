import Foundation

/// A hop on the way to a host: one of your own hosts, resolved like any other,
/// standing in front of another.
///
/// Kept as its own small shape rather than a nested host because what a hop
/// contributes to the command line is only this: where it is, who it logs in
/// as, and which key it uses. `ssh -J` would carry the name alone and silently
/// drop the port and the key, which is why the chain is built out by hand.
nonisolated struct Hop: Sendable, Hashable {
    var name = ""
    /// The name ssh's own config knows this machine by, where it knows one.
    var alias = ""
    var addr = ""
    /// As it is stored: nothing means ssh's own default, and `-p` is left off.
    var port = 0
    var user = ""
    var identity = ""
    /// This hop's own settings, which reach the ssh that reaches it and not
    /// the one beyond.
    var options: [String] = []
    var forwardAgent: Bool?

    /// What ssh is handed for this hop: the config's name where there is one,
    /// so the block written under it applies, and the address otherwise.
    var dest: String { alias.isEmpty ? addr : alias }
    /// Where a hop in front of this one has to connect.
    var dialPort: Int { Resolver.portOr22(port) }
}

/// A host with everything the groups above it filled in, and the name of
/// whatever supplied each value.
nonisolated struct Resolved: Sendable {
    var host = Host()
    var user = ""
    var userFrom = ""
    var identity = ""
    var identityFrom = ""
    var proxyJump = ""
    var proxyJumpFrom = ""
    /// The chain in front of this host, the first hop first.
    var jumps: [Hop] = []
    /// The name ssh's own config knows this host by, where that name goes to
    /// this same machine.
    var alias = ""
    /// The config's entry under this host's name when it goes somewhere else,
    /// so the detail pane can say why those settings are not in use.
    var aliasElsewhere: Alias?
    /// What ssh's own config would send this host through. Empty when the host
    /// has a jump host of its own: that goes on the command line, which ssh
    /// reads first and keeps.
    var configProxy = ""
    /// Every `-o` setting that reaches this host, nearest first — its own,
    /// then each group above it. ssh keeps the first value for a setting, so
    /// the order is the precedence.
    var sshOptions: [String] = []
    var forwardAgent: Bool?
    var forwardAgentFrom: String = ""
    /// The palette that reaches this host, and what supplied it. Empty means
    /// nothing in the chain chose one, and the Settings palette stands.
    var theme: String = ""
    var themeFrom: String = ""

    var port: Int { Resolver.portOr22(host.port) }
    var dest: String { alias.isEmpty ? host.addr : alias }

    /// The shape the window shows.
    var effective: Effective {
        Effective(
            user: user, userFrom: userFrom,
            identity: identity, identityFrom: identityFrom,
            proxyJump: proxyJump, proxyJumpFrom: proxyJumpFrom,
            port: port, aliasElsewhere: aliasElsewhere,
            sshOptions: sshOptions, forwardAgent: forwardAgent,
            forwardAgentFrom: forwardAgentFrom,
            theme: theme, themeFrom: themeFrom)
    }
}

/// What a group takes from the groups above it, and which one supplied each
/// value.
///
/// A group's own fields are what it **sets**; what its editor needs beside
/// each one is what would stand there if it set nothing. So this starts at
/// the parent and never reads the group itself.
///
/// It is here rather than in the sheet because it is a rule about the data,
/// and because the sheet had four hand-written copies of this walk — one per
/// field it shows — each carrying its own guard against a tree that loops.
/// One pass now answers all of them.
nonisolated struct FromAbove: Sendable, Equatable {
    var user = ""
    var userFrom = ""
    var identity = ""
    var identityFrom = ""
    var proxyJump = ""
    var proxyJumpFrom = ""
    var theme = ""
    var themeFrom = ""
    /// Nothing means no group above said either way, which is a third state
    /// and not the same as one of them saying no.
    var forwardAgent: Bool?
    var forwardAgentFrom = ""

    init() {}

    init(of group: Group, among groups: [Group]) {
        let byID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        // The group's own id seeds the guard: a group that is somehow its own
        // ancestor stops the walk rather than hanging it.
        var seen: Set<String> = [group.id]
        var id = group.parentId
        while !id.isEmpty, !seen.contains(id) {
            seen.insert(id)
            guard let parent = byID[id] else { break }
            if user.isEmpty, !parent.user.isEmpty {
                user = parent.user
                userFrom = parent.name
            }
            if identity.isEmpty, !parent.identity.isEmpty {
                identity = parent.identity
                identityFrom = parent.name
            }
            if proxyJump.isEmpty, !parent.proxyJump.isEmpty {
                proxyJump = parent.proxyJump
                proxyJumpFrom = parent.name
            }
            if theme.isEmpty, !parent.theme.isEmpty {
                theme = parent.theme
                themeFrom = parent.name
            }
            if forwardAgent == nil, let says = parent.forwardAgent {
                forwardAgent = says
                forwardAgentFrom = parent.name
            }
            id = parent.parentId
        }
    }
}

/// Group inheritance, and the jump host a host names turned into the host it
/// stands for.
///
/// The inheritance rules: a host's own value always wins,
/// then the nearest ancestor group that sets the value.
nonisolated struct Resolver: Sendable {
    /// Past a handful a chain of jump hosts is far more likely to be a mistake
    /// than a real topology, and the bound is what stops a pathological list
    /// building an enormous command line.
    static let maxJumpHops = 8

    private let groupsByID: [String: Group]
    private let hostsByName: [String: Host]
    private var aliases: [String: Alias] = [:]
    private var proxyFor: (@Sendable (String) -> String)?

    init(groups: [Group], hosts: [Host]) {
        groupsByID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        // Last one wins, which matches what the list shows for a duplicate.
        hostsByName = Dictionary(
            hosts.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { _, b in b })
    }

    /// The resolver knowing what ssh's own config calls machines, so a host the
    /// config names is reached by that name. Where two names differ only in
    /// case the first is kept, as names are matched without regard to case
    /// everywhere else.
    func withAliases(_ list: [Alias]) -> Resolver {
        var out = self
        var byName: [String: Alias] = [:]
        for alias in list {
            let key = alias.name.lowercased()
            if byName[key] == nil { byName[key] = alias }
        }
        out.aliases = byName
        return out
    }

    /// The resolver knowing what ssh's own config sends a connection through,
    /// asked by the name ssh is handed for it.
    func withProxies(_ proxy: @escaping @Sendable (String) -> String) -> Resolver {
        var out = self
        out.proxyFor = proxy
        return out
    }

    func resolve(_ host: Host) -> Resolved {
        var out = inherit(host)
        out.jumps = chain(from: out.proxyJump)
        let (alias, elsewhere) = aliasFor(host)
        out.alias = alias
        out.aliasElsewhere = elsewhere
        out.configProxy = configProxy(out)
        return out
    }

    /// Every host with its groups applied, which is what the window reads.
    func resolveAll(_ hosts: [Host]) -> [Host] {
        hosts.map { host in
            var out = host
            out.effective = resolve(host).effective
            return out
        }
    }

    // MARK: inheritance

    private func inherit(_ host: Host) -> Resolved {
        var out = Resolved(host: host)
        out.user = host.user
        out.identity = host.identity
        out.proxyJump = host.proxyJump
        // Its own first: ssh keeps the first value it sees for a setting, so
        // gathering them nearest-first is the whole of the precedence.
        out.sshOptions = host.sshOptions
        out.forwardAgent = host.forwardAgent
        out.theme = host.theme

        var seen: Set<String> = []
        var id = host.groupId
        while !id.isEmpty, !seen.contains(id) {
            seen.insert(id)
            guard let group = groupsByID[id] else { break }
            if out.user.isEmpty, !group.user.isEmpty {
                out.user = group.user
                out.userFrom = group.name
            }
            if out.identity.isEmpty, !group.identity.isEmpty {
                out.identity = group.identity
                out.identityFrom = group.name
            }
            if out.proxyJump.isEmpty, !group.proxyJump.isEmpty {
                out.proxyJump = group.proxyJump
                out.proxyJumpFrom = group.name
            }
            out.sshOptions += group.sshOptions
            if out.forwardAgent == nil, let says = group.forwardAgent {
                out.forwardAgent = says
                out.forwardAgentFrom = group.name
            }
            if out.theme.isEmpty, !group.theme.isEmpty {
                out.theme = group.theme
                out.themeFrom = group.name
            }
            id = group.parentId
        }
        return out
    }

    // MARK: jump hosts

    /// The chain a host's jump field names, each hop resolved like any other
    /// host. A name that is not one of yours stops the walk and is left for
    /// ssh to interpret, so `user@bastion.example.com` still works.
    private func chain(from name: String) -> [Hop] {
        var out: [Hop] = []
        var seen: Set<String> = []
        var next = name.trimmingCharacters(in: .whitespaces)
        while !next.isEmpty, out.count < Resolver.maxJumpHops {
            guard let host = hostsByName[next.lowercased()] else { break }
            // A jump host reached through itself, directly or in a loop.
            if seen.contains(host.id) { break }
            seen.insert(host.id)

            let hop = inherit(host)
            let (alias, _) = aliasFor(host)
            out.append(Hop(
                name: host.name, alias: alias, addr: host.addr, port: host.port,
                user: hop.user, identity: hop.identity,
                options: hop.sshOptions, forwardAgent: hop.forwardAgent))
            next = hop.proxyJump.trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    // MARK: what ssh's own config says

    /// The name to reach a host by, if ssh's own config has one for it.
    ///
    /// The name has to be the host's own and the machine the same: the entry
    /// has to take ssh to this host's address and port. A `Host web` that goes
    /// somewhere else is a different machine that happens to share a name, and
    /// its settings are not this one's to take — a ForwardAgent written for it
    /// would hand this machine your agent. That entry comes back as elsewhere
    /// instead, so the reason it is not used can be shown.
    private func aliasFor(_ host: Host) -> (String, Alias?) {
        let key = host.name.trimmingCharacters(in: .whitespaces).lowercased()
        guard let alias = aliases[key] else { return ("", nil) }
        let sameMachine = alias.addr.caseInsensitiveCompare(host.addr) == .orderedSame
            && Resolver.portOr22(alias.port) == Resolver.portOr22(host.port)
        return sameMachine ? (alias.name, nil) : ("", alias)
    }

    /// Asked by the name the argv builder hands ssh — the alias where there is
    /// one, the address otherwise — because that is what the file's Host lines
    /// are matched against. A host reached by its address is sent through a
    /// bastion by `Host 10.0.1.*` as surely as one reached by name is by its
    /// own block.
    private func configProxy(_ resolved: Resolved) -> String {
        guard let proxyFor, resolved.proxyJump.isEmpty else { return "" }
        let dest = resolved.dest
        return dest.isEmpty ? "" : proxyFor(dest)
    }

    /// The port ssh will use, which is 22 where none is given.
    static func portOr22(_ port: Int) -> Int { port == 0 ? 22 : port }
}
