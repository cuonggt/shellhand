import Foundation

/// The machines a connection passes through, in the order it reaches them:
/// each jump host of yours, then the host itself.
///
/// What the connecting screen says a session is going through, and what the
/// host-key question uses to say which machine is asking. In a jump chain
/// every hop asks for itself, and a question about "192.0.2.10" said nothing
/// to somebody who knows that machine as bastion — nor whether it was the
/// bastion or the host behind it.
nonisolated struct Route: Sendable, Equatable {
    nonisolated struct Stop: Sendable, Equatable {
        /// What the list calls it.
        var name: String
        /// What ssh is handed for it: its name in ssh's own config, or its
        /// address.
        var dest: String
        /// Its address, which is what ssh names in a question when it was
        /// handed a config's name: the config's `HostName` is the same
        /// machine, or the name would not have been used.
        var addr: String
        /// The port dialled, 22 where none is stored.
        var port: Int
    }

    /// The first machine reached first, and the host itself last.
    var stops: [Stop] = []
    /// A jump ssh is left to make sense of by itself — one not in the list,
    /// or one ssh's own config adds.
    var beyond = ""

    var end: Stop? { stops.last }

    /// The jump hosts, in the order they are reached.
    var jumps: ArraySlice<Stop> { stops.dropLast() }

    /// "through bastion", "through edge, then bastion", or nothing for a
    /// machine reached directly.
    var through: String {
        let names = jumps.map(\.name) + (beyond.isEmpty ? [] : [beyond])
        return names.isEmpty ? "" : "through " + names.joined(separator: ", then ")
    }

    /// Which stop a host-key question is about, from the machine as ssh named
    /// it: a name or an address, or `[address]:port` where the port is not 22.
    func index(asked host: String) -> Int? {
        let (name, port) = Route.split(host)
        return stops.firstIndex { stop in
            stop.port == port
                && (stop.dest.caseInsensitiveCompare(name) == .orderedSame
                    || stop.addr.caseInsensitiveCompare(name) == .orderedSame)
        }
    }

    /// Where stop `index` sits, for a question one machine of several is
    /// asking: "the first of 2 hops on the way to db-01", or for the host
    /// itself "reached through bastion". Nil for a route of one machine.
    func position(of index: Int) -> String? {
        guard stops.count > 1, stops.indices.contains(index), let end else { return nil }
        if index == stops.count - 1 { return "reached " + through }
        return "the \(Route.ordinal(index + 1)) of \(stops.count) hops on the way to \(end.name)"
    }

    /// `[address]:port` taken apart, as ssh writes a machine on a port other
    /// than 22; anything else is the name alone, on 22.
    static func split(_ host: String) -> (name: String, port: Int) {
        guard host.hasPrefix("["), let close = host.lastIndex(of: "]") else { return (host, 22) }
        let name = String(host[host.index(after: host.startIndex)..<close])
        let rest = host[host.index(after: close)...]
        guard rest.hasPrefix(":"), let port = Int(rest.dropFirst()) else { return (name, 22) }
        return (name, port)
    }

    /// Words up to the ninth, which is as long as a route gets: eight jump
    /// hosts, `Resolver.maxJumpHops`, and the host behind them.
    static func ordinal(_ number: Int) -> String {
        let words = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth"]
        return words.indices.contains(number - 1) ? words[number - 1] : "\(number)th"
    }
}

/// What opening a session takes: the argv, and the route it goes by.
nonisolated struct Connection: Sendable, Equatable {
    var argv: [String]
    var route: Route
}

extension Resolved {
    /// The route this host is reached by. `jumps` is nearest hop first, the
    /// order the argv builder nests them in, and a connection reaches them
    /// the other way round.
    nonisolated var route: Route {
        let hops = jumps.reversed().map {
            Route.Stop(name: $0.name, dest: $0.dest, addr: $0.addr, port: $0.dialPort)
        }
        let end = Route.Stop(name: host.name, dest: dest, addr: host.addr, port: port)
        // A jump the chain could not resolve is handed to ssh as it stands,
        // and the config's applies only where the host names none.
        let beyond = !jumps.isEmpty ? "" : !proxyJump.isEmpty ? proxyJump : configProxy
        return Route(stops: hops + [end], beyond: beyond)
    }
}
