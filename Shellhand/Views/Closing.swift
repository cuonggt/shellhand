import Foundation

/// Whether dropping sessions asks first, and what it asks.
///
/// **The setting behind this switched nothing for its whole life before
/// it.** "Ask before closing a live session" was a toggle in Settings from
/// the day it was added, and nothing read its key: ⌘W, a tab's ×, the
/// window's close button and ⌘Q all dropped live sessions without a word
/// while Settings said they would ask. A sweep for dead declarations cannot
/// see that shape, because a preference key is a string, not a declaration.
///
/// Out here rather than in the views for the reason `Panes` is: a decision
/// inside a dialog can only be checked by driving the dialog, and this app's
/// dialogs do not answer to a script. What asks — the window for one tab,
/// the window's delegate for itself, the app's delegate for quitting — puts
/// this question and obeys the answer.
nonisolated enum Closing {
    /// What is about to drop sessions.
    enum Act {
        case closingTab
        /// ⌘R on a session that is still up closes it before opening the
        /// new one, which drops it as surely as ⌘W does.
        case reconnecting
        /// A tab's Close Other Tabs: every session but the one clicked.
        case closingOthers
        case closingWindow
        /// Closing the SFTP window, which stops every transfer still
        /// moving or waiting its turn. It used to, without a word.
        case closingFiles
        case quitting
    }

    /// A session as this needs it: whose it is, and how it is doing.
    struct Open: Equatable {
        /// The host's name, or nil for a local shell.
        var host: String?
        var state: TerminalSession.State
    }

    struct Question: Equatable {
        var title: String
        var message: String
        /// What the button that goes ahead says.
        var confirm: String
    }

    /// Where Settings keeps the switch — under the key it has always had, so
    /// anybody who turned it off before it did anything finds it still off.
    static let setting = "confirmCloseLiveSession"

    /// Whether to ask at all, given what is stored: **yes** while nothing is,
    /// which is what the switch shows on a fresh install. Not
    /// `UserDefaults.bool(forKey:)`, which answers no for a key never written.
    static func confirms(_ stored: Any?) -> Bool { stored as? Bool ?? true }

    /// What Settings says now.
    static var confirmsNow: Bool { confirms(UserDefaults.standard.object(forKey: setting)) }

    /// Whether dropping a session loses anything: it does if somebody is in
    /// it. Still connecting, there is nothing on it yet; waiting on a host-key
    /// answer, it is already asking something; ended, there is nothing left.
    /// A local shell is connected from the start, so it counts until it
    /// exits.
    static func isLive(_ state: TerminalSession.State) -> Bool { state == .connected }

    /// The question to put before going ahead, or nil to go straight ahead.
    ///
    /// `stopping` is how many transfers are still moving or waiting their
    /// turn: closing the SFTP window stops them, and so does quitting.
    static func question(
        _ act: Act, dropping sessions: [Open], stopping transfers: Int = 0, confirming: Bool
    ) -> Question? {
        guard confirming else { return nil }
        let live = sessions.filter { isLive($0.state) }
        let moving = transfers == 1 ? "a transfer" : "\(transfers) transfers"
        let unfinished = transfers == 1 ? "It has not finished." : "They have not finished."
        if act == .closingFiles || (act == .quitting && live.isEmpty) {
            guard transfers > 0 else { return nil }
            return act == .closingFiles
                ? Question(title: "Close SFTP and stop \(moving)?", message: unfinished,
                           confirm: "Close")
                : Question(title: "Quit and stop \(moving)?", message: unfinished,
                           confirm: "Quit")
        }
        guard let first = live.first else { return nil }
        let them = live.count == 1 ? name(of: first) : "\(live.count) sessions"
        let still = live.count == 1 ? "It is still running." : "They are all still running."
        switch act {
        case .closingTab:
            return Question(
                title: "Close \(name(of: first))?",
                message: "It is still running, and closing the tab ends it.",
                confirm: "Close")
        case .reconnecting:
            return Question(
                title: first.host.map { "Reconnect to \($0)?" } ?? "Reconnect?",
                message: "The session is still running, and reconnecting ends it "
                    + "before opening a new one.",
                confirm: "Reconnect")
        case .closingOthers:
            // The tabs counted are every one going, live or not; the
            // sessions named are only the live ones among them.
            let tabs = sessions.count == 1 ? "tab" : "tabs"
            return Question(
                title: "Close the other \(tabs) and end \(them)?", message: still, confirm: "Close")
        case .closingWindow:
            return Question(
                title: "Close the window and end \(them)?", message: still, confirm: "Close")
        case .closingFiles:
            return nil
        case .quitting:
            guard transfers > 0 else {
                return Question(title: "Quit and end \(them)?", message: still, confirm: "Quit")
            }
            return Question(
                title: "Quit, ending \(them) and stopping \(moving)?",
                message: "None of them has finished.", confirm: "Quit")
        }
    }

    /// "the session on web", or "the local shell".
    static func name(of session: Open) -> String {
        session.host.map { "the session on \($0)" } ?? "the local shell"
    }
}

extension Closing.Open {
    /// Read off a session, which only the main actor may do.
    @MainActor init(_ session: TerminalSession) {
        self.init(host: session.host?.name, state: session.state)
    }
}
