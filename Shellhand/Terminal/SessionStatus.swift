import Foundation

/// What a session is doing, as its tab, its pane and the window's subtitle
/// say it — in words and a symbol, never a colour alone.
///
/// A 6pt dot was the whole of it: one colour for connecting and another for
/// a question nobody could see from another tab, and "status 255" for every
/// ending — the words typing `exit` got too. Out of the views for the reason
/// `SessionProgress` is: what a state means is a rule worth holding still,
/// and it takes two values to check rather than a pty.
nonisolated enum SessionStatus: Equatable, Sendable {
    case connecting
    /// A host-key question waits on somebody, in the background too.
    case needsAnswer
    case connected
    /// Ended by Stop Connecting, which is no failure to report.
    case stopped
    /// ssh gave up before the session was through.
    case couldNotConnect
    /// ssh failed once the session was through: the connection dropped.
    case lost
    /// The far end finished it: `exit`, a logout, a signal.
    case ended

    /// `gotThrough` is whether the session ever came through, which is no
    /// proof of having logged in: an answered question or a password prompt
    /// on screen reads as through. So what ssh said decides first.
    static func of(
        _ state: TerminalSession.State, stopped: Bool, gotThrough: Bool
    ) -> SessionStatus {
        switch state {
        case .connecting: return .connecting
        case .askingHostKey: return .needsAnswer
        case .connected: return .connected
        case let .ended(code, said):
            if stopped { return .stopped }
            switch code {
            case 255?:
                // ssh's own status, which every refusal and every drop share.
                if SessionEnding.isDrop(said) { return .lost }
                if SessionEnding.isBeforeLogin(said) || !gotThrough { return .couldNotConnect }
                return .lost
            case nil:
                // A signal, or an ssh that never started.
                return gotThrough ? .ended : .couldNotConnect
            default:
                // Any other status is the far end's, so it got that far.
                return .ended
            }
        }
    }

    /// The state in words, for the window's subtitle.
    var words: String {
        switch self {
        case .connecting: "connecting"
        case .needsAnswer: "needs you"
        case .connected: "connected"
        case .stopped: "stopped"
        case .couldNotConnect: "couldn't connect"
        case .lost: "connection lost"
        case .ended: "ended"
        }
    }

    /// What a tab says when it is read out, which can take the longer form.
    var spoken: String {
        self == .needsAnswer ? "needs you to answer a host-key question" : words
    }

    /// The tab's symbol. Connecting is drawn as a spinner instead, and
    /// connected keeps the dot it always had: the one shape that is not a
    /// warning.
    var symbol: String {
        switch self {
        case .connecting: "circle.dotted"
        case .needsAnswer: "key.fill"
        case .connected: "circle.fill"
        case .stopped: "stop.circle"
        case .couldNotConnect, .lost: "exclamationmark.triangle.fill"
        case .ended: "checkmark.circle"
        }
    }

    /// Whether ssh failed, as against being stopped or finishing.
    var isFailure: Bool { self == .couldNotConnect || self == .lost }

    /// Whether the pane has nothing worth reading under what is said about
    /// it, so that it is said in the middle — rather than in a band across
    /// the top of a session's last output, which is where an ending after
    /// some use goes.
    var isBeforeAnything: Bool {
        self == .connecting || self == .stopped || self == .couldNotConnect
    }

    /// What the pane says, naming the machine — nil for a local shell.
    func headline(for name: String?) -> String {
        guard let name else {
            switch self {
            case .ended: return "The local shell ended"
            case .couldNotConnect: return "The local shell couldn't start"
            default: return "The local shell"
            }
        }
        switch self {
        case .connecting: return "Connecting to \(name)"
        case .needsAnswer: return "\(name) needs an answer"
        case .connected: return name
        case .stopped: return "Stopped connecting to \(name)"
        case .couldNotConnect: return "Couldn't connect to \(name)"
        case .lost: return "The connection to \(name) was lost"
        case .ended: return "The session on \(name) ended"
        }
    }

    /// Said first after an ending before anything ran there.
    var reassurance: String? {
        switch self {
        case .couldNotConnect: "The connection never opened, so nothing was lost."
        case .stopped: "Nothing was connected, so nothing was lost."
        default: nil
        }
    }

    /// Under the window's title: where the session goes, and how it is doing
    /// when that is anything but through.
    func subtitle(destination: String) -> String {
        self == .connected ? destination : "\(destination) · \(words)"
    }

    /// Under "Connecting to": where it is going, the way there, and how long
    /// it has taken — "deploy@192.0.2.21:2222, through bastion · 4 s".
    static func connectingLine(destination: String, through: String, seconds: Int) -> String {
        let way = [destination, through].filter { !$0.isEmpty }.joined(separator: ", ")
        let time = seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
        return way.isEmpty ? time : "\(way) · \(time)"
    }

    /// A far end's own status, said only where it is not plain success.
    /// 255 is ssh's and is said by the rest of the ending instead.
    static func exitNote(_ code: Int32?) -> String? {
        guard let code, code != 0, code != 255 else { return nil }
        return "It exited with status \(code)."
    }
}

/// What ssh's own words at the end of a session mean, for somebody who did
/// not write ssh. The line itself is shown too, so this only has to be right
/// where it says anything at all, and says nothing for a line it does not
/// know.
nonisolated enum SessionEnding {
    /// Whether ssh says the connection dropped once it was through: the far
    /// end gone quiet, or the network under it.
    static func isDrop(_ said: String) -> Bool {
        let text = said.lowercased()
        return text.contains("client_loop:") || text.contains("packet_write_wait")
            || text.contains("timeout, server")
            || (text.contains("connection to ") && text.contains("closed by remote host"))
    }

    /// Whether ssh says it stopped before logging in: it never reached the
    /// machine, the machine turned it away, or a key was not trusted.
    static func isBeforeLogin(_ said: String) -> Bool {
        let text = said.lowercased()
        return beforeLogin.contains { text.contains($0) }
    }

    private static let beforeLogin = [
        "connect to host", "could not resolve hostname", "permission denied",
        "host key verification failed", "remote host identification has changed",
        "kex_exchange_identification", "connection closed by", "connection reset by",
        "banner exchange", "too many authentication failures", "unable to negotiate",
        "no matching", "unprotected private key file", "bad owner or permissions",
        "stdio forwarding failed", "channel 0: open failed",
    ]

    /// What went wrong, in plain words, where ssh's line is one this knows.
    static func reason(_ said: String) -> String? {
        let text = said.lowercased()
        if text.contains("remote host identification has changed") {
            return "The machine's key isn't the one your known_hosts holds for it. It may have "
                + "been reinstalled, or something may be in the way: check with whoever runs it "
                + "before removing the old key."
        }
        if text.contains("host key verification failed") {
            return "Its key wasn't trusted, so ssh stopped before logging in."
        }
        if text.contains("stdio forwarding failed") || text.contains("channel 0: open failed") {
            return text.contains("connection refused")
                ? "The jump host reached the machine behind it, but nothing is listening there."
                : "The jump host couldn't reach the machine behind it."
        }
        if text.contains("connection refused") {
            let port = number(after: "port ", in: said).map { " on port \($0)" } ?? ""
            return "The machine answered, but nothing is listening\(port)."
        }
        if text.contains("could not resolve hostname") {
            return "This Mac can't look that name up. Check it for a typo, or whether it needs a VPN."
        }
        if text.contains("no route to host") || text.contains("network is unreachable")
            || text.contains("host is down")
        {
            return "This Mac has no way through to that address. Check the network, or a VPN the "
                + "machine needs."
        }
        if text.contains("timed out") {
            return "Nothing answered in time. The machine may be off or asleep, or a firewall may "
                + "be dropping the connection."
        }
        if text.contains("too many authentication failures") {
            return "ssh offered more keys than the machine accepts, and it stopped listening."
        }
        if text.contains("permission denied") {
            return "The machine turned down every way ssh tried to log in. Check the user and the key."
        }
        if text.contains("unprotected private key file") || text.contains("bad owner or permissions") {
            return "Others can read the key file, so ssh won't use it."
        }
        if text.contains("unable to negotiate") || text.contains("no matching") {
            return "This Mac's ssh and the machine have no way of talking in common, which usually "
                + "means an old server."
        }
        if isDrop(said) {
            return "The connection dropped while the session was open."
        }
        if text.contains("kex_exchange_identification") || text.contains("connection closed by")
            || text.contains("connection reset by")
        {
            return "The machine hung up before anything was said."
        }
        return nil
    }

    /// The digits after the last `word`: the port in "connect to host … port
    /// 22: Connection refused".
    private static func number(after word: String, in text: String) -> Int? {
        guard let found = text.range(of: word, options: .backwards) else { return nil }
        return Int(text[found.upperBound...].prefix { $0.isNumber })
    }
}
