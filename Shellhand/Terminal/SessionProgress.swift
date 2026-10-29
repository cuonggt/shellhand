import Foundation

/// What a session's state becomes, given what is on its screen.
///
/// This is the whole of what the watchdog decides, lifted out of the loop that
/// runs it. The loop is machinery — sleep, tick, read the log, look — and the
/// decision is the part worth holding still: that a host-key question is only
/// taken from the end of the buffer, that it is not re-posed while it is being
/// answered, that any output at all means the connection is through, and that
/// a session which has ended is not moved by anything.
///
/// Driving it needed a pty, an unknown host and a window before this; it needs
/// two values now. `nonisolated` deliberately, along with `TerminalSession.State`
/// itself, or the app target's MainActor default makes both unreachable from a
/// test looking in from outside.
nonisolated enum SessionProgress {
    /// The state to move to, or nil to leave it alone.
    ///
    /// **Nil is the common answer and it matters.** The watchdog looks five
    /// times a second, and writing the same state back each time would churn
    /// an `@Observable` into redrawing the terminal for nothing.
    ///
    /// `answered` is the question most recently answered, if the session has
    /// not got through since — see where it is used below.
    static func next(
        from state: TerminalSession.State, screen: String, answered: String? = nil
    ) -> TerminalSession.State? {
        // An ended session is finished. Whatever is still on the screen, it is
        // the last thing that process ever said.
        if case .ended = state { return nil }

        if HostKey.isBeingAsked(screen) {
            // Already asking: re-posing it would rebuild the question under
            // the person reading it, every 200ms.
            if case .askingHostKey = state { return nil }
            let question = HostKey.question(in: screen)
            // The question just answered, still on screen exactly as it was
            // because the pty has not echoed the answer yet. A look in that
            // instant used to ask it again: the dialog came back for a tick,
            // and an Accept inside that tick typed `yes` into the shell. Only
            // **that** question is held back — a different one is new and is
            // asked, as a jump chain asks one per hop.
            if question == answered { return nil }
            return .askingHostKey(question)
        }

        // Nothing said yet is no evidence of a connection, and **a terminal
        // that has heard nothing does not come back empty**: its buffer is its
        // own blank rows, which `isEmpty` happily called output. That took
        // every session to `.connected` on the watchdog's first look, 200ms
        // after opening, whether or not anything had answered — so
        // `.connecting` never meant anything and a host that was refusing to
        // answer looked connected. Blank is the test, not empty.
        guard !screen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        switch state {
        case .connecting, .askingHostKey:
            // Anything at all from the far side means we are through. A
            // question that has been answered leaves its own text on screen,
            // which is why `.askingHostKey` moves on from here too.
            return .connected
        case .connected, .ended:
            return nil
        }
    }

    /// How long after a session comes through its screen is still read, in
    /// seconds. **Through is not settled.** An answered question on screen
    /// reads as being through, so a jump chain's next hop asks after
    /// `.connected`, and so does a host behind a bastion that printed a
    /// banner first. Two minutes covers both with room to spare.
    static let settling: TimeInterval = 120

    /// Whether the watchdog reads the screen at all on this look.
    ///
    /// **Reading it means reading the whole history.** SwiftTerm 1.99 gives
    /// the app no part of the buffer, only all of it, and at 10,000 lines
    /// that measured 90–214ms a look in an optimized build — five looks a
    /// second, on the main thread, for every session. So it is read only
    /// while there can be something of this app's to ask: connecting, a
    /// question up, and `settling` seconds after coming through. Every
    /// connect is a fresh session, so the history is short whenever it is
    /// read. After that a host-key question is something run inside the
    /// session asking — an `ssh` typed there — and it is answered in the
    /// terminal, as in any terminal, rather than with this app's dialog.
    ///
    /// A session through with no time on it is read, as every session was
    /// before there was a rule.
    static func watches(
        _ state: TerminalSession.State, connectedAt: Date?, now: Date = Date()
    ) -> Bool {
        switch state {
        case .connecting, .askingHostKey:
            return true
        case .ended:
            return false
        case .connected:
            guard let connectedAt else { return true }
            return now.timeIntervalSince(connectedAt) < settling
        }
    }
}
