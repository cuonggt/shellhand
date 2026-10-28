import Foundation

/// Reading OpenSSH's own client config as a host list.
///
/// Only what Shellhand needs to list and reach a host is taken: the name, the
/// address behind it, and the user, port, key and jump host. Everything else
/// in that file keeps working without being copied, because Shellhand runs the
/// real ssh, which reads the file itself — ControlMaster, certificates and
/// Match blocks are honoured whether or not anything here knows about them.
/// Import is for discovery, not for taking over OpenSSH's configuration.
nonisolated enum SSHConfigFile {
    /// Where that config lives when nothing says otherwise.
    static var defaultPath: String {
        NSString(string: "~/.ssh/config").expandingTildeInPath
    }

    /// The config a run actually reads, which under test is **not** the
    /// user's own.
    ///
    /// The store and this app's own config are both sent to scratch for a run
    /// (see `LaunchOptions`), and this needs it for a reason of the same size
    /// now that these names reach the resolver: a run reading the real file
    /// would take whatever somebody happens to have written there into every
    /// host the suite resolves, so a `Host web` of theirs would quietly change
    /// what a test about a host called `web` sees. Nothing writes the scratch
    /// one, and a missing config reads as no names at all.
    static var pathInUse: String {
        TestRun.active ? TestRun.sshConfig : defaultPath
    }

    /// The names this config gives machines.
    ///
    /// A host whose own name matches one of these is either reached by that
    /// name — so the block written under it applies, with `HostName` pinning
    /// the address — or told that the name goes somewhere else. `Resolver`
    /// decides which; this only reports what the file says.
    static func aliases(in blocks: [Block]) -> [Alias] {
        document(from: blocks).hosts.map { Alias(name: $0.name, addr: $0.addr, port: $0.port) }
    }

    /// What this config would send a connection to `destination` through, as
    /// a host that can be named in a sentence. Empty when it sends it
    /// straight there.
    ///
    /// Asked by the name ssh is handed — the alias where there is one, the
    /// address otherwise — because that is what `Host` and `Match` lines are
    /// matched against. A host reached by its address is caught by
    /// `Host 10.0.1.*` as surely as one reached by name is by its own block.
    ///
    /// **`ProxyJump` only, on purpose.** A `ProxyCommand` routes a connection
    /// too, but it is a command line rather than a jump host — `ssh -W %h:%p
    /// gateway`, or something that is not ssh at all — and putting that in a
    /// field labelled "Jump host" would be a different wrong answer rather
    /// than a right one. A host reached through one still reads as having no
    /// jump host, which is where this started; saying so needs a row of its
    /// own, and nobody has asked for one.
    static func proxy(reaching destination: String, in blocks: [Block]) -> String {
        let jump = values(for: destination, in: blocks)["proxyjump"] ?? ""
        return jump.lowercased() == "none" ? "" : jump
    }

    /// The machines a config names, as a document ready to merge.
    static func read(path: String) -> Portable.Document {
        document(from: parse(path: path))
    }

    /// The same, from blocks already parsed, so a caller wanting more than
    /// one thing out of a config pays for reading it once.
    static func document(from blocks: [Block]) -> Portable.Document {
        var document = Portable.Document()

        // One name may be declared more than once, its settings merging, so
        // each is collected once and then asked for every value.
        var names: [String] = []
        var seen: Set<String> = []
        for block in blocks {
            guard case let .host(patterns) = block.header else { continue }
            for pattern in patterns where concrete(pattern) && !seen.contains(pattern.lowercased()) {
                seen.insert(pattern.lowercased())
                names.append(pattern)
            }
        }
        names.sort { $0.lowercased() < $1.lowercased() }

        for name in names {
            let settings = values(for: name, in: blocks)
            // `Host myserver` with no HostName means connect to the literal
            // name, which is how a great many entries are written.
            var addr = settings["hostname"] ?? name
            addr = addr.replacingOccurrences(of: "%h", with: name)
            var host = Portable.Host(name: name, addr: addr)
            // Port 22 is stored as unset: it is what ssh does anyway, and
            // leaving it out keeps an exported document free of noise.
            if let port = settings["port"].flatMap(Int.init), port != 22 { host.port = port }
            host.user = settings["user"] ?? ""
            if let identity = settings["identityfile"] {
                host.identity = NSString(string: identity).expandingTildeInPath
            }
            let jump = settings["proxyjump"] ?? ""
            host.jump = jump.lowercased() == "none" ? "" : jump
            document.hosts.append(host)
        }
        document.version = 1
        return document
    }

    // MARK: the file

    enum Header: Equatable {
        case host([String])
        /// `Match all`, and `Match host <patterns>`. Any other Match is
        /// carried but never applied: its condition cannot be answered from
        /// here — `exec` runs a command, and `user` depends on who is asking —
        /// and guessing at one would hand ssh settings it was never going to
        /// use.
        case matchAll
        case matchHost([String])
        case matchUnsupported
    }

    struct Block {
        var header: Header
        var settings: [(String, String)] = []
    }

    /// Reads a config and everything it includes, in order.
    /// **Nothing here throws, and it must not start looking as though it
    /// does.** A file that cannot be read is an empty list, which is the
    /// right answer for the common case of no config at all; an `Include`
    /// that loops is cut off by the depth. Declaring this `throws` cost
    /// nothing at the time and made three callers write `try?`, so each read
    /// like failure handling where there is no failure to handle.
    static func parse(path: String, depth: Int = 0) -> [Block] {
        var read: Set<String> = []
        return parse(path: path, depth: depth, read: &read)
    }

    /// **Each file is read once per parse, and the depth cap is not what
    /// saves you.** A cap alone terminates a cycle and does nothing about its
    /// *width*: `Include conf.d/*` written inside a file that is itself in
    /// `conf.d` — a plausible copy-paste — branches by however many files are
    /// in that directory, at every level. Measured, with a cap of 8 and
    /// nothing else: fan-out 2 took 29ms, 3 took 346ms and 4 took 2.4
    /// seconds, so a `conf.d` of ten would not finish today. That was
    /// survivable while the only caller was an import somebody asks for; the
    /// resolver reads this config now, so it would be a window that never
    /// opens.
    ///
    /// Reading a file once is also what ssh ends up doing with it: a setting
    /// keeps its **first** value, so a second copy of the same blocks can
    /// never win anything, and the names it declares are the same names. So
    /// this is cheaper and not weaker.
    private static func parse(path: String, depth: Int, read: inout Set<String>) -> [Block] {
        guard depth < 8 else { return [] }
        // Settled first, so that two spellings of one file are one file.
        let settled = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard read.insert(settled).inserted else { return [] }
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }

        var blocks: [Block] = []
        // Settings before any Host line apply to everything, as ssh reads them.
        var current = Block(header: .matchAll)
        for line in raw.components(separatedBy: .newlines) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("#") { continue }
            guard let (keyword, argument) = split(text) else { continue }
            switch keyword.lowercased() {
            case "host":
                blocks.append(current)
                current = Block(header: .host(words(argument)))
            case "match":
                blocks.append(current)
                current = Block(header: match(argument))
            case "include":
                // Textual inclusion at this point in the file, so what it
                // brings is read here, inside whatever block is open.
                // An Include is read here, where it is written. What comes
                // after it goes on under the same header, which is the common
                // case: an include at the top of a file whose own Host blocks
                // follow.
                let header = current.header
                blocks.append(current)
                for included in includePaths(argument, relativeTo: path) {
                    blocks += parse(path: included, depth: depth + 1, read: &read)
                }
                current = Block(header: header)
            default:
                current.settings.append((keyword.lowercased(), argument))
            }
        }
        blocks.append(current)
        return blocks.filter { !$0.settings.isEmpty || isHost($0.header) }
    }

    private static func isHost(_ header: Header) -> Bool {
        if case .host = header { return true }
        return false
    }

    /// Every setting that applies to a name, first one winning — which is
    /// ssh's rule: a value written under the host's own name beats one from a
    /// pattern further down.
    static func values(for name: String, in blocks: [Block]) -> [String: String] {
        var out: [String: String] = [:]
        for block in blocks {
            guard applies(block.header, to: name) else { continue }
            for (keyword, value) in block.settings where out[keyword] == nil {
                out[keyword] = value
            }
        }
        return out
    }

    private static func applies(_ header: Header, to name: String) -> Bool {
        switch header {
        case .matchAll: true
        case .matchUnsupported: false
        case let .host(patterns), let .matchHost(patterns): matches(name, patterns)
        }
    }

    private static func match(_ argument: String) -> Header {
        let parts = words(argument)
        guard let first = parts.first?.lowercased() else { return .matchUnsupported }
        if first == "all" { return .matchAll }
        if first == "host", parts.count > 1 {
            return .matchHost(parts.dropFirst().flatMap { $0.components(separatedBy: ",") })
        }
        return .matchUnsupported
    }

    // MARK: patterns

    /// Whether a name is one a host list can hold: a pattern is a rule about
    /// many machines, not a machine.
    static func concrete(_ pattern: String) -> Bool {
        !pattern.contains("*") && !pattern.contains("?") && !pattern.hasPrefix("!")
    }

    /// ssh's rule: any positive pattern matching, and no negative one.
    static func matches(_ name: String, _ patterns: [String]) -> Bool {
        var hit = false
        for pattern in patterns {
            if pattern.hasPrefix("!") {
                if glob(String(pattern.dropFirst()), name) { return false }
            } else if glob(pattern, name) {
                hit = true
            }
        }
        return hit
    }

    /// `*` for any run and `?` for one character, matched without regard to
    /// case, as ssh matches host names.
    /// Whether a name matches one of ssh's patterns: `*` for any run of
    /// characters, including none, and `?` for exactly one.
    ///
    /// **A scan with a single backtrack point, not a table.** This was a full
    /// dynamic-programming matrix — correct, and it allocated a nested array
    /// of (pattern × name) `Bool`s on every pattern tried against every name.
    /// Nothing noticed while the only caller was an import somebody asks for;
    /// once the resolver began asking what the config routes each host
    /// through, it became a walk over every block for every host, and a
    /// 500-host list against a 400-block config took **5.1 seconds** a
    /// snapshot where everything else in the resolve took 4ms. Measured both
    /// ways rather than guessed at: with the proxy lookup taken out the same
    /// list resolved in 4ms, so the table was the whole of it.
    ///
    /// The backtrack is the part worth reading. A `*` takes as much as it can
    /// and gives one character back each time what follows it fails to line
    /// up further along, which is what `a*b*c` against `axxbyyc` needs and
    /// what a scan without `star`/`mark` gets wrong.
    static func glob(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern.lowercased()), s = Array(name.lowercased())
        var i = 0, j = 0
        // Where the last `*` was, and how much it had taken when we passed it.
        var star = -1, taken = 0
        while j < s.count {
            if i < p.count, p[i] == "?" || p[i] == s[j] {
                i += 1
                j += 1
            } else if i < p.count, p[i] == "*" {
                star = i
                taken = j
                i += 1
            } else if star >= 0 {
                // Give the star one more character and try again from there.
                i = star + 1
                taken += 1
                j = taken
            } else {
                return false
            }
        }
        // Stars left over match nothing, which is allowed; anything else is
        // pattern the name ran out before reaching.
        while i < p.count, p[i] == "*" { i += 1 }
        return i == p.count
    }

    // MARK: lines

    /// A keyword, then whitespace or an `=`, then the rest of the line — which
    /// is how ssh reads one.
    static func split(_ line: String) -> (String, String)? {
        guard let i = line.firstIndex(where: { $0 == "=" || $0.isWhitespace }) else { return nil }
        let keyword = String(line[line.startIndex..<i])
        var rest = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("=") { rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) }
        guard !keyword.isEmpty, !rest.isEmpty else { return nil }
        return (keyword, unquote(rest))
    }

    private static func unquote(_ s: String) -> String {
        guard s.count > 1, s.hasPrefix("\""), s.hasSuffix("\"") else { return s }
        return String(s.dropFirst().dropLast())
    }

    private static func words(_ s: String) -> [String] {
        s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.map(unquote)
    }

    /// The files an Include names. Relative paths are to ~/.ssh for a user's
    /// config, which is what ssh does, and a pattern brings everything it
    /// matches in sorted order.
    static func includePaths(_ argument: String, relativeTo parent: String) -> [String] {
        var out: [String] = []
        for token in words(argument) {
            var pattern = NSString(string: token).expandingTildeInPath
            if !pattern.hasPrefix("/") {
                let base = (parent as NSString).deletingLastPathComponent
                pattern = (base as NSString).appendingPathComponent(pattern)
            }
            if pattern.contains("*") || pattern.contains("?") {
                let folder = (pattern as NSString).deletingLastPathComponent
                let leaf = (pattern as NSString).lastPathComponent
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
                out += names.filter { glob(leaf, $0) }.sorted()
                    .map { (folder as NSString).appendingPathComponent($0) }
            } else {
                out.append(pattern)
            }
        }
        return out
    }
}
