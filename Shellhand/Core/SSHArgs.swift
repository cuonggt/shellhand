import Foundation

/// One end of a connection, as the argv builder needs it: a host of yours, or
/// a hop standing in front of one.
nonisolated struct Endpoint: Sendable, Hashable {
    var addr = ""
    /// As stored. Nothing means ssh's own default, and `-p` is left off.
    var port = 0
    var user = ""
    var identity = ""
    /// The name ssh's own config knows this machine by, where it knows one.
    var alias = ""
    /// A jump host that is not one of yours, left for ssh to interpret.
    var proxyJumpText = ""
    /// This end's own `-o` settings, nearest first.
    var options: [String] = []
    var forwardAgent: Bool?

    /// user@addr, or the address alone.
    var target: String { user.isEmpty ? addr : user + "@" + addr }

    /// The address a hop in front of this one has to reach, written out rather
    /// than left to ssh's %h and %p.
    var forwardTarget: String { "[\(addr)]:\(Resolver.portOr22(port))" }
}

extension Resolved {
    /// This host and the chain in front of it, nearest hop first — what the
    /// argv builder walks.
    nonisolated var endpoints: [Endpoint] {
        var out = [Endpoint(
            addr: host.addr, port: host.port, user: user, identity: identity,
            alias: alias,
            // Where the chain resolved, the hops carry it; what is left here is
            // a destination ssh has to make sense of on its own.
            proxyJumpText: jumps.isEmpty ? proxyJump : "",
            options: sshOptions, forwardAgent: forwardAgent)]
        out += jumps.map {
            Endpoint(
                addr: $0.addr, port: $0.port, user: $0.user, identity: $0.identity,
                alias: $0.alias,
                options: $0.options, forwardAgent: $0.forwardAgent)
        }
        return out
    }
}

/// The OpenSSH invocations Shellhand makes.
///
/// Every connection goes through here — the sessions, the tunnels, the script
/// runs and the file browser — so connection behaviour cannot drift between
/// them. `SSHArgsTests` pins the line it produces, so a change that alters
/// how a host is reached shows up as a failing test rather than a surprise.
nonisolated enum SSHArgs {
    // MARK: options that hold for every connection

    private static let lock = NSLock()
    nonisolated(unsafe) private static var options: [String] = []

    /// `-o` settings applied to every invocation, mirroring ssh's own flag.
    /// Set once at startup, before any connection is made.
    static func setGlobalOptions(_ list: [String]) {
        lock.lock()
        defer { lock.unlock() }
        options = list
    }

    static var globalOptions: [String] {
        lock.lock()
        defer { lock.unlock() }
        return options
    }

    /// What is wrong with an `-o` setting, or nil where ssh will take it.
    ///
    /// ssh reads one as it reads a line of a config file: a keyword, then
    /// whitespace or an `=`, then the argument. `BatchMode=yes`, `BatchMode
    /// yes` and `SetEnv FOO=bar` are all fine. What this refuses is a keyword
    /// with nothing after it — written into a config that was carried to every
    /// connection, and every one of them failed with ssh's words for a command
    /// line nobody had typed. The keyword itself is left to ssh, which knows
    /// them all and says which one it did not recognise.
    static func optionProblem(_ option: String) -> String? {
        let text = option.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return "is empty" }
        guard let i = text.firstIndex(where: { $0 == "=" || $0.isWhitespace }) else {
            return "has no value"
        }
        if i == text.startIndex { return "starts with its separator, so it names no setting" }
        let rest = text[i...].trimmingCharacters(in: .whitespaces)
        let value = rest.drop { $0 == "=" }.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? "has no value" : nil
    }

    // MARK: the invocation

    /// The argv to reach a host, without the program name.
    ///
    /// `extra` is inserted before the target, which is where ssh wants flags
    /// like `-N` and `-W`. `fixed` are settings the caller cannot let anything
    /// override, so they lead — ssh keeps the first value it sees — and they
    /// are carried down every hop, because a hop stopping at a prompt inside a
    /// detached session is a tunnel that reports itself up while carrying
    /// nothing.
    static func build(
        _ resolved: Resolved, fixed: [String] = [], extra: [String] = []
    ) -> [String] {
        build(resolved.endpoints, at: 0, fixed: fixed, extra: extra)
    }

    /// The argv for invoking a remote subsystem, such as `sftp`. ssh puts the
    /// subsystem name where a remote command would go.
    ///
    /// `opts` are preferences and go where `build` puts them, after the global
    /// options, so LogLevel can still be raised for a look at what ssh is
    /// doing.
    static func subsystem(
        _ resolved: Resolved, _ name: String, fixed: [String] = [], opts: [String] = []
    ) -> [String] {
        build(resolved, fixed: fixed, extra: ["-s"] + opts) + [name]
    }

    private static func build(
        _ chain: [Endpoint], at index: Int, fixed: [String], extra: [String]
    ) -> [String] {
        guard index < chain.count else { return [] }
        let end = chain[index]
        var args = fixed

        // This host's own, and its groups', before the ones every connection
        // gets: a setting written against one machine should beat the default
        // written for all of them, and ssh keeps the first it is given.
        if let forwardAgent = end.forwardAgent {
            args += ["-o", "ForwardAgent=" + (forwardAgent ? "yes" : "no")]
        }
        for option in end.options { args += ["-o", option] }
        for option in globalOptions { args += ["-o", option] }

        if end.port != 0 && end.port != 22 { args += ["-p", String(end.port)] }
        if !end.identity.isEmpty { args += ["-i", end.identity] }

        if index + 1 < chain.count {
            // ssh -J hands the hop only -l, -p and -v, so the hop's own key and
            // options would be dropped. Spelling the inner connection out is
            // what ssh does internally anyway, and it composes: a hop behind
            // another hop carries its own ProxyCommand.
            let inner = proxyCommand(chain, at: index + 1, reaching: end.forwardTarget, fixed: fixed)
            args += ["-o", "ProxyCommand=" + inner]
        } else if !end.proxyJumpText.isEmpty {
            // Not one of ours, so it is already an ssh destination.
            args += ["-J", end.proxyJumpText]
        }

        args += extra

        if end.alias.isEmpty || end.alias == end.addr {
            // Where the alias is the address itself, the address already names
            // the block and there is nothing to add.
            return args + [end.target]
        }
        // By the name ssh's own config gives this machine, so the block written
        // under it applies — ssh picks blocks by the name it is handed, and
        // handed the address it passed over all of them. HostName pins the
        // address, so the alias decides only which settings apply and never
        // which machine is reached.
        //
        // A % is doubled because ssh expands tokens in HostName and nowhere in
        // the destination: an address holding one, as an IPv6 address with its
        // zone does — fe80::1%en0 — would otherwise be refused outright.
        let dest = end.user.isEmpty ? end.alias : end.user + "@" + end.alias
        return args + ["-o", "HostName=" + end.addr.replacingOccurrences(of: "%", with: "%%"), dest]
    }

    /// The ssh invocation that opens a channel through a hop to an address, for
    /// use as another connection's ProxyCommand.
    ///
    /// `-W` makes the hop forward stdio to that address, which is what ssh's
    /// own implicit ProxyCommand does. The address is written out rather than
    /// left to ssh's %h and %p: those are expanded by the outermost ssh across
    /// the whole nested command, so in a chain every hop was handed the final
    /// destination — the first hop dialled it directly and the ones in between
    /// were never contacted at all.
    private static func proxyCommand(
        _ chain: [Endpoint], at index: Int, reaching dest: String, fixed: [String]
    ) -> String {
        let inner = ["ssh"] + build(chain, at: index, fixed: fixed, extra: ["-W", dest])
        return inner.map(shellQuote).joined(separator: " ")
    }

    /// Makes one argument safe for the shell that runs a ProxyCommand.
    ///
    /// ssh runs it through the login shell, not /bin/sh, so glob characters
    /// matter: an unquoted `-W [%h]:%p` is a bracket expression, and zsh treats
    /// a pattern that matches nothing as a fatal error rather than passing it
    /// through. Key paths and addresses are yours to write, so they can hold
    /// spaces and anything else a shell would act on. %h and %p survive
    /// quoting: ssh substitutes them before the shell ever sees the string.
    static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let safe = s.allSatisfy { c in
            c.isASCII && (c.isLetter || c.isNumber || "@%_+=:,./-".contains(c))
        }
        if safe { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    // MARK: connections nobody is sitting in front of

    /// The options for a connection with nobody in front of it: a tunnel in a
    /// detached tmux session, or an sftp child whose stdin carries the protocol
    /// rather than a keyboard.
    ///
    /// BatchMode is how that is said: every prompt off, so a connection
    /// nobody is watching fails rather than waits. It also means a host that
    /// takes only a password cannot be reached this way at all — there is
    /// nothing left to answer with now that credentials are gone, and a
    /// transfer that hangs on an invisible prompt is the worse of the two.
    static let unattended = ["-o", "BatchMode=yes"]
}
