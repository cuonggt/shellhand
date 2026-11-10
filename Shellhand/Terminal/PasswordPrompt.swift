import Foundation

/// Whether ssh is asking a terminal tab for a password, and which machine on
/// the way it is asking for — so a tab can type the password kept for that
/// one, at the owner's word (2026-11-08).
///
/// **Only ssh's own prompt, for a machine on the route, logging in as the
/// user it should.** Two shapes, in OpenSSH's own words: `deploy@db-01's
/// password:` for password authentication, and `(deploy@db-01) Password:` for
/// a keyboard-interactive one whose server asks for the password by that
/// name. Anything else — a code from an authenticator, a server's prompt worded
/// some other way, `sudo` asking inside a session — is left to the person: a
/// password typed into the wrong question is a password given away.
///
/// ssh names the machine as it was handed it — a config's `HostName`, or the
/// address — so a stop is matched by either, and by no port, since the
/// prompt carries none. A stop with no user is the one ssh fills in itself,
/// this Mac's own login name; a config's `User` the resolver cannot see
/// leaves the prompt unmatched, and so untyped, which is the safe way round.
///
/// Out of `TerminalSession` as `HostKey` is: it is nothing but strings, and
/// checking it through a session needs a pty, an ssh and a window.
nonisolated enum PasswordPrompt {
    /// A prompt live at the end of the screen.
    nonisolated struct Asked: Equatable, Sendable {
        /// The stop it asks for, by its place in the route.
        var stop: Int
        /// The prompt as the screen holds it, its whitespace out: what is
        /// counted to tell ssh asking again from the same prompt still
        /// standing, and what the watchdog does not take for the far side.
        var tight: String
    }

    /// The prompt standing at the very end of the screen, and the stop it is
    /// for, or nil.
    ///
    /// Read as `HostKey` reads its question: the last rows that carry
    /// anything, put back together with the whitespace out, since a terminal
    /// narrow enough wraps the prompt across rows and a wrap that falls on a
    /// space loses it. Nothing may follow the colon — a prompt with anything
    /// after it is one already answered, or not ssh's — and **the prompt
    /// starts a row**, as ssh writes it: matched as the tail of a longer row,
    /// `redeploy@db-01's password:` would have been typed deploy's.
    static func asked(in screen: String, route: Route, localUser: String = NSUserName())
        -> Asked?
    {
        let rows = lastRows(of: screen).map(tightened)
        // Put back together before looking: a wrap can split "password:".
        guard rows.joined().lowercased().hasSuffix("password:") else { return nil }
        // The last row, the last two put back together, and so on: a prompt
        // wrapped across rows is one of these, and starts where its row does.
        var endings: [String] = []
        var joined = ""
        for row in rows.reversed() {
            joined = row + joined
            endings.append(joined)
        }
        for (index, stop) in route.stops.enumerated() {
            for prompt in prompts(for: stop, localUser: localUser) {
                if let hit = endings.first(where: { $0.lowercased() == prompt.lowercased() }) {
                    return Asked(stop: index, tight: hit)
                }
            }
        }
        return nil
    }

    /// How many times `asked` stands on the screen, whitespace out: once
    /// while it is first asked, and once more each time ssh asks again.
    static func count(_ asked: Asked, in screen: String) -> Int {
        let tight = tightened(screen)
        var count = 0
        var rest = tight[...]
        while let found = rest.range(of: asked.tight) {
            count += 1
            rest = rest[found.upperBound...]
        }
        return count
    }

    /// The two shapes ssh asks for a stop's password in, whitespace out.
    static func prompts(for stop: Route.Stop, localUser: String) -> [String] {
        let user = stop.user.trimmingCharacters(in: .whitespaces).isEmpty
            ? localUser : stop.user.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty else { return [] }
        var machines: [String] = []
        for machine in [stop.dest, stop.addr].map({ tightened($0) }) where !machine.isEmpty {
            if !machines.contains(where: { $0.caseInsensitiveCompare(machine) == .orderedSame }) {
                machines.append(machine)
            }
        }
        let login = tightened(user)
        return machines.flatMap { machine in
            ["\(login)@\(machine)'spassword:", "(\(login)@\(machine))password:"]
        }
    }

    private static func tightened(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    /// The last rows that carry anything — sixteen, as `HostKey` takes, which
    /// holds a prompt wrapped across rows down to a terminal a few columns
    /// wide. Split on any newline: Swift reads `\r\n` as one character, which
    /// a split on `"\n"` passes straight over.
    private static func lastRows(of screen: String) -> [String] {
        screen
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(16)
    }
}
