import Foundation

/// What a file pane calls itself, what it shows, and how it names a child of
/// what it is showing.
///
/// Out of `FilePlace` for the reason `Tree` and `Panes` are out of theirs: a
/// `FilePlace` only reaches these states by connecting to something, so a test
/// that wanted to ask "what does an unpointed pane call itself" would have to
/// open an SFTP session to find out. Here the same question is three
/// arguments.
nonisolated enum Places {
    /// What the pane says it is showing.
    ///
    /// **A pane that has not been pointed anywhere is not this Mac** — it is a
    /// question, and says so. Without that distinction an unpointed pane reads
    /// as "This Mac" over an empty listing, which looks exactly like an empty
    /// home directory.
    static func title(chosen: Bool, host: String?) -> String {
        guard chosen else { return "Choose a host" }
        return host ?? "This Mac"
    }

    /// Whether this side is this Mac.
    ///
    /// Carries more than it looks: it is what decides whether a name clash is
    /// judged case-insensitively, because this disk is and an SFTP server's
    /// usually is not. Asked the wrong way round it either invents a clash —
    /// and a file silently not carried is as bad as one silently overwritten —
    /// or misses the real one. An unpointed pane is **not** local, for the
    /// same reason it is not called "This Mac".
    static func isLocal(chosen: Bool, onAHost: Bool) -> Bool {
        chosen && !onAHost
    }

    /// The session a pane's operations go through: `""`, which the engine
    /// reads as this Mac, for a pane that is this Mac; the one open for a
    /// host; and **nothing at all** for a host still connecting or turned
    /// away. Handing over the empty session there acted on this Mac — a
    /// Delete removed the same path here while the dialog named the host.
    static func session(chosen: Bool, onAHost: Bool, open: String) -> String? {
        guard chosen else { return nil }
        guard onAHost else { return "" }
        return open.isEmpty ? nil : open
    }

    /// Where a pane says what went wrong.
    enum Notice: Equatable {
        case none
        /// Over an empty pane, in place of the listing.
        case instead
        /// Above a listing still on screen. Before this, a failure with a
        /// listing up was drawn nowhere: a refused rename, delete or new
        /// folder happened without a word.
        case banner
    }

    static func notice(listed: Bool, failure: String?) -> Notice {
        guard failure != nil else { return .none }
        return listed ? .banner : .instead
    }

    /// A message from somewhere else, ending as a sentence.
    static func sentence(_ text: String) -> String {
        text.hasSuffix(".") ? text : text + "."
    }

    /// What deleting asks first.
    struct DeleteQuestion: Equatable {
        var title: String
        var message: String
        /// What the button that goes ahead says.
        var confirm: String
    }

    /// On this Mac a deletion goes to the Trash, where it can be taken back;
    /// on a host there is no such place, and the question says so. It used
    /// to say "They are deleted" of a single file, and "This cannot be
    /// undone" of this Mac, where nothing should be that final.
    static func deleteQuestion(_ names: [String], local: Bool, on place: String) -> DeleteQuestion {
        let one = names.count == 1
        let what = one ? "“\(names[0])”" : "\(names.count) items"
        if local {
            return DeleteQuestion(
                title: "Move \(what) to the Trash?",
                message: one ? "You can put it back from the Trash."
                    : "You can put them back from the Trash.",
                confirm: "Move to Trash")
        }
        return DeleteQuestion(
            title: "Delete \(what)?",
            message: (one ? "It is deleted" : "They are deleted")
                + " on \(place). This cannot be undone.",
            confirm: "Delete")
    }

    /// Which of a listing's entries a pane shows. Dotfiles are hidden by
    /// default, as a file manager shows a home directory without forty of
    /// them in front of what you came for.
    static func shown(_ entries: [RemoteEntry], hidden: Bool) -> [RemoteEntry] {
        hidden ? entries : entries.filter { !$0.name.hasPrefix(".") }
    }

    /// How many a pane is holding back, for the line that offers to show them.
    static func hiddenCount(_ entries: [RemoteEntry], hidden: Bool) -> Int {
        entries.count - shown(entries, hidden: hidden).count
    }

    /// A child of the directory a pane is showing.
    ///
    /// The root is the case worth having: it already ends in a slash, and
    /// joining blindly would ask for `//etc`. Remote paths are the server's,
    /// so nothing here tries to tidy them beyond that.
    static func path(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    /// A folder on this Mac written from `~` when it is in the home folder,
    /// for a line with no room for `/Users/someone` before every path.
    static func abbreviated(_ path: String, home: String) -> String {
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        let inside = home.hasSuffix("/") ? home : home + "/"
        return path.hasPrefix(inside) ? "~/" + path.dropFirst(inside.count) : path
    }

    // MARK: a host it cannot reach

    /// What a pane says about a host SFTP could not open, and whether a
    /// terminal tab is the way past it.
    struct Trouble: Equatable {
        var title: String
        /// What it means and what to do, where that is known.
        var advice: String
        /// Whether a terminal tab on the host gets past this. It can answer
        /// ssh's question about a new key, and type a password, where SFTP
        /// can do neither: its ssh runs with `BatchMode=yes`, since there is
        /// nobody to ask.
        var offersTerminal: Bool
    }

    /// `said` is ssh's own sentence, which is what a pane's failure holds.
    ///
    /// "Host key verification failed." was all a host never connected to
    /// got, with no way on from there — and a host that takes only a password
    /// got "Permission denied", which reads as a wrong password nobody typed.
    static func trouble(_ said: String, on host: String) -> Trouble {
        let text = said.lowercased()
        if text.contains("remote host identification has changed") {
            return Trouble(
                title: "\(host)'s key has changed",
                advice: SessionEnding.reason(said) ?? "", offersTerminal: false)
        }
        if text.contains("host key verification failed") {
            return Trouble(
                title: "\(host) hasn't been connected to yet",
                advice: "SFTP can't answer ssh's question about a new machine's key. Open \(host) "
                    + "once in a terminal tab and say yes there, then try again here.",
                offersTerminal: true)
        }
        if text.contains("permission denied") {
            // "Permission denied (publickey,password)": the ways the host
            // takes, of which SFTP can use a key and nothing else.
            var ways = ""
            if let open = text.range(of: "permission denied ("),
               let close = text[open.upperBound...].firstIndex(of: ")") {
                ways = String(text[open.upperBound..<close])
            }
            let takesPassword = ways.contains("password") || ways.contains("keyboard-interactive")
            if takesPassword, !ways.contains("publickey") {
                return Trouble(
                    title: "SFTP needs a key for \(host)",
                    advice: "\(host) takes only a password, and SFTP has no way to type one. "
                        + "A terminal tab can: ssh asks for it there.",
                    offersTerminal: true)
            }
            return Trouble(
                title: "\(host) turned down the key",
                advice: "SFTP logs in with a key alone, and the host accepted none that ssh offered. "
                    + "Check the host's user and key."
                    + (takesPassword ? " A terminal tab can log in with its password." : ""),
                offersTerminal: takesPassword)
        }
        return Trouble(
            title: "Couldn't connect to \(host)",
            advice: SessionEnding.reason(said) ?? "", offersTerminal: false)
    }

    // MARK: what the replace question's buttons say

    /// Singular where there is one, because "Skip them" over a single file
    /// reads as though something else is being left behind too.
    static func skipping(_ count: Int) -> String { count == 1 ? "Skip it" : "Skip them" }

    static func replacing(_ count: Int) -> String { count == 1 ? "Replace" : "Replace them" }
}
