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

    // MARK: what the replace question's buttons say

    /// Singular where there is one, because "Skip them" over a single file
    /// reads as though something else is being left behind too.
    static func skipping(_ count: Int) -> String { count == 1 ? "Skip it" : "Skip them" }

    static func replacing(_ count: Int) -> String { count == 1 ? "Replace" : "Replace them" }
}
