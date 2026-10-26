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
    static func next(
        from state: TerminalSession.State, screen: String
    ) -> TerminalSession.State? {
        // An ended session is finished. Whatever is still on the screen, it is
        // the last thing that process ever said.
        if case .ended = state { return nil }

        if HostKey.isBeingAsked(screen) {
            // Already asking: re-posing it would rebuild the question under
            // the person reading it, every 200ms.
            if case .askingHostKey = state { return nil }
            return .askingHostKey(HostKey.question(in: screen))
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
}
