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

    /// The machines a config names, as a document ready to merge.
    static func read(path: String) throws -> Portable.Document {
        let blocks = try parse(path: path)
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
    static func parse(path: String, depth: Int = 0) throws -> [Block] {
        guard depth < 8 else { return [] }  // An Include that includes itself.
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
                    blocks += try parse(path: included, depth: depth + 1)
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
    static func glob(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern.lowercased()), s = Array(name.lowercased())
        var table = Array(repeating: Array(repeating: false, count: s.count + 1), count: p.count + 1)
        table[0][0] = true
        for i in 0..<p.count where p[i] == "*" { table[i + 1][0] = table[i][0] }
        for i in 0..<p.count {
            for j in 0..<s.count {
                switch p[i] {
                case "*": table[i + 1][j + 1] = table[i][j + 1] || table[i + 1][j]
                case "?": table[i + 1][j + 1] = table[i][j]
                default: table[i + 1][j + 1] = table[i][j] && p[i] == s[j]
                }
            }
        }
        return table[p.count][s.count]
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
