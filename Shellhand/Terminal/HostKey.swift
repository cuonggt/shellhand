import Foundation

/// Whether ssh is waiting to be told about a host key, and which part of the
/// screen is the question.
///
/// Out of `TerminalSession` because it is the whole of a rule that has been
/// wrong before, and because it is nothing but a string: asking it needs no
/// pty, no ssh and no window, where reaching it through a session needs all
/// three.
nonisolated enum HostKey {
    /// Whether the **last thing on screen** is ssh waiting for an answer.
    ///
    /// ssh writes the question last and then waits, so the question is live
    /// only while **nothing follows its closing `?`** — no answer echoed onto
    /// its own row, no output below it. A match anywhere else is a question
    /// already answered. Matching the whole buffer once left a session stuck on
    /// a prompt that was gone, and matching the last two rows did it again on
    /// a quieter screen: after a `yes` the pty echoes the answer onto the
    /// question's own row, and `ssh -E` sends its "Permanently added" to the
    /// log rather than the screen, so a server that logs in quietly leaves the
    /// answered row and one line of its own as the whole tail. The question
    /// was asked again, the dialog came back, and a second Accept typed `yes`
    /// into the live shell. Only a real prompt showed it, from a real `ssh`;
    /// `TerminalOverSSHTests` is the guard.
    static func isBeingAsked(_ screen: String) -> Bool {
        // A question too long for the terminal's width arrives as **two rows
        // with the phrase split between them**, because the buffer is read
        // row by row and nothing rejoins what wrapped — so the rows are put
        // back together. Whitespace comes out of both sides of the comparison,
        // because every row is right-trimmed: a wrap that falls on a space
        // loses that space altogether, and no search for the phrase as written
        // would find it again.
        let joined = tightened(tail(of: screen).joined())
        guard let found = joined.range(of: tightMarker, options: .backwards) else { return false }
        // The rest of the prompt, up to and including its closing `?`, and
        // then nothing at all. Up to the first `?` rather than an exact
        // spelling, because the rest of the prompt differs between versions.
        let rest = joined[found.upperBound...]
        guard let closing = rest.firstIndex(of: "?") else { return false }
        return rest.index(after: closing) == rest.endIndex
    }

    /// The fingerprint and the question, without the rest of the screen.
    ///
    /// Back as far as the line that opens the warning where there is one, and
    /// otherwise a few lines, which is enough to carry the fingerprint a
    /// person is being asked to vouch for. A screen with no question in it
    /// comes back whole rather than empty: showing everything is a worse
    /// answer than showing the question, and a much better one than showing
    /// nothing.
    static func question(in screen: String) -> String {
        let lines = screen.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let end: Int
        if let found = lines.lastIndex(where: { $0.contains(marker) }) {
            end = found
        } else if isBeingAsked(screen), let last = lines.lastIndex(where: { !$0.isEmpty }) {
            // Wrapped, so no single row carries the phrase: the question runs
            // to the last row with anything on it. Without this the fallback
            // below hands back the whole screen and buries the fingerprint in
            // it, which is the one thing a person is being asked to read.
            end = last
        } else {
            return screen
        }
        let start = lines[..<end].lastIndex { $0.contains(opening) } ?? max(0, end - 4)
        return lines[start...end].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// What ssh actually writes. Matched as a fragment rather than whole,
    /// because the rest of the line differs between versions and between the
    /// yes/no and the yes/no/[fingerprint] forms.
    private static let marker = "continue connecting (yes/no"
    private static let opening = "authenticity of host"

    /// The same phrase with the spaces taken out, for comparing against rows
    /// that have been put back together. Derived rather than written twice,
    /// so the two cannot drift apart.
    private static let tightMarker = tightened(marker)

    private static func tightened(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    /// The last couple of lines that carry anything, which is where the
    /// question sits when it is live.
    ///
    /// **Two**, which is enough to rejoin a question wrapped once. This depth
    /// used to be what kept an answered question from reading as live, and it
    /// never quite did: a quiet server's single line after a `yes` left the
    /// answered row inside it. That job belongs to `isBeingAsked`'s rule now —
    /// nothing may follow the closing `?` — so a wider tail no longer risks the
    /// stuck prompt, and would let a question wrapped across three rows be
    /// found, which needs a terminal under about 34 columns and is still
    /// missed. It has not been widened. The proper fix still wants the width,
    /// and SwiftTerm keeps both `cols` and the buffer's own `isWrapped` flag
    /// internal, so the app cannot ask.
    private static func tail(of screen: String) -> [String] {
        screen
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(2)
    }
}
