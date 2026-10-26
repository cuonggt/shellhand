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
    /// Only the end of the buffer counts. ssh writes the question last and
    /// then waits, so a match anywhere else is a question that has already
    /// been answered — and matching the whole buffer left the session stuck
    /// on a prompt that was gone, with the shell's own output scrolling past
    /// underneath it.
    static func isBeingAsked(_ screen: String) -> Bool {
        let tail = tail(of: screen)
        if tail.contains(where: { $0.contains(marker) }) { return true }
        // A question too long for the terminal's width arrives as **two rows
        // with the phrase split between them**, because the buffer is read
        // row by row and nothing rejoins what wrapped. So the rows are put
        // back together before giving up. Whitespace comes out of both sides
        // of the comparison, because every row is right-trimmed: a wrap that
        // falls on a space loses that space altogether, and no search for the
        // phrase as written would find it again.
        return tightened(tail.joined()).contains(tightMarker)
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
    /// **Two, and not more**, even though a narrow enough terminal wraps the
    /// question across three rows or four. Widening this is the obvious fix
    /// and it is the wrong one: it would let the shell's own reply sit inside
    /// the tail beside the question it answered, which is the stuck-prompt bug
    /// this rule exists to prevent — `howFarBack` pins that boundary. So a
    /// question wrapped across three rows or more, which needs a terminal
    /// under about 34 columns, is still missed. Fixing that properly wants the
    /// width, and SwiftTerm keeps both `cols` and the buffer's own
    /// `isWrapped` flag internal, so the app cannot ask.
    private static func tail(of screen: String) -> [String] {
        screen
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(2)
    }
}
