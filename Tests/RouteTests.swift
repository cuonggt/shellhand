import Testing
@testable import Shellhand

/// The machines a connection passes through, as the connecting screen and the
/// host-key question name them — taken from the resolver's own walk of the
/// jump chain, not a second one.
@Suite("Route")
nonisolated struct RouteTests {
    private func route(of host: Host, among hosts: [Host]) -> Route {
        Resolver(groups: [], hosts: hosts).resolve(host).route
    }

    @Test("a host reached directly is a route of one, through nothing")
    func direct() {
        let web = Host(id: "w", name: "web", addr: "192.0.2.21", port: 2222)
        let route = route(of: web, among: [web])
        #expect(route.stops == [Route.Stop(name: "web", dest: "192.0.2.21", addr: "192.0.2.21", port: 2222)])
        #expect(route.through == "")
        #expect(route.position(of: 0) == nil)
    }

    /// The resolver keeps the nearest hop first, the order the argv nests
    /// them in. A connection meets them the other way round, and that is the
    /// order they are said in.
    @Test("a chain is in the order it is reached, the host itself last")
    func travelOrder() {
        let db = Host(id: "d", name: "db-01", addr: "192.0.2.21", proxyJump: "bastion")
        let bastion = Host(id: "b", name: "bastion", addr: "192.0.2.10", proxyJump: "edge")
        let edge = Host(id: "e", name: "edge", addr: "203.0.113.5", port: 2200)
        let route = route(of: db, among: [db, bastion, edge])
        #expect(route.stops.map(\.name) == ["edge", "bastion", "db-01"])
        #expect(route.stops.map(\.port) == [2200, 22, 22])
        #expect(route.through == "through edge, then bastion")
        #expect(route.position(of: 0) == "the first of 3 hops on the way to db-01")
        #expect(route.position(of: 1) == "the second of 3 hops on the way to db-01")
        #expect(route.position(of: 2) == "reached through edge, then bastion")
    }

    /// A jump that is not one of yours is handed to ssh as it stands, so it
    /// is said as it stands.
    @Test("a jump the list does not hold is said as written")
    func notOurs() {
        let db = Host(id: "d", name: "db-01", addr: "192.0.2.21", proxyJump: "someone@elsewhere.net")
        let route = route(of: db, among: [db])
        #expect(route.stops.map(\.name) == ["db-01"])
        #expect(route.through == "through someone@elsewhere.net")
    }

    @Test("ssh's own config's jump is said where the host names none")
    func theConfigs() {
        var resolved = Resolved(host: Host(id: "d", name: "db-01", addr: "10.0.1.5"))
        resolved.configProxy = "bastion"
        #expect(resolved.route.through == "through bastion")
        resolved.proxyJump = "jump.example.net"
        #expect(resolved.route.through == "through jump.example.net")
    }

    // MARK: which machine a question is about

    /// ssh names a machine on 22 bare and any other port as `[address]:port`,
    /// and a question through a jump host names the host behind it so.
    @Test("a question's machine is found by address and port")
    func byAddress() {
        let db = Host(id: "d", name: "db-01", addr: "192.0.2.21", port: 2222, proxyJump: "bastion")
        let bastion = Host(id: "b", name: "bastion", addr: "192.0.2.10")
        let route = route(of: db, among: [db, bastion])
        #expect(route.index(asked: "192.0.2.10") == 0)
        #expect(route.index(asked: "[192.0.2.21]:2222") == 1)
        // The right address on the wrong port is some other machine.
        #expect(route.index(asked: "192.0.2.21") == nil)
        #expect(route.index(asked: "[192.0.2.10]:2200") == nil)
        #expect(route.index(asked: "198.51.100.1") == nil)
    }

    /// Handed a config's name, ssh asks about the address that name stands
    /// for; the name is only used where it goes to the same machine, so
    /// either finds it.
    @Test("a machine reached by ssh's own name for it is found by either")
    func byAlias() {
        var resolved = Resolved(host: Host(id: "d", name: "db-01", addr: "192.0.2.21"))
        resolved.jumps = [Hop(name: "bastion", alias: "jump-box", addr: "192.0.2.10")]
        let route = resolved.route
        #expect(route.index(asked: "jump-box") == 0)
        #expect(route.index(asked: "JUMP-BOX") == 0)
        #expect(route.index(asked: "192.0.2.10") == 0)
    }

    @Test("a machine on another port is taken apart, an IPv6 address included")
    func split() {
        #expect(Route.split("[192.0.2.21]:2222") == ("192.0.2.21", 2222))
        #expect(Route.split("[2001:db8::5]:2222") == ("2001:db8::5", 2222))
        #expect(Route.split("web") == ("web", 22))
        #expect(Route.split("[web]") == ("web", 22))
    }

    @Test("hops are counted in words as far as a route can go")
    func ordinals() {
        #expect(Route.ordinal(1) == "first")
        #expect(Route.ordinal(Resolver.maxJumpHops + 1) == "ninth")
        #expect(Route.ordinal(12) == "12th")
    }
}
