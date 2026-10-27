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
        // A question too long for the terminal's width arrives as **rows with
        // the phrase split between them** — two, three, six, however narrow —
        // because the buffer is read row by row and nothing rejoins what
        // wrapped; so the tail's rows are put back together. Whitespace comes
        // out of both sides of the comparison, because every row is
        // right-trimmed: a wrap that falls on a space loses that space
        // altogether, and no search for the phrase as written would find it.
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
    /// otherwise the fingerprint's own line, which is enough to carry what a
    /// person is being asked to vouch for. A screen with no question in it
    /// comes back whole rather than empty: showing everything is a worse
    /// answer than showing the question, and a much better one than showing
    /// nothing.
    static func question(in screen: String) -> String {
        let rows = screen.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Where it ends. While it is being asked that is the last row on the
        // screen — nothing may follow its `?` — however many rows the terminal
        // wrapped it across; otherwise the last row carrying the whole phrase.
        let end: Int
        if isBeingAsked(screen), let last = rows.indices.last {
            end = last
        } else if let found = rows.lastIndex(where: { $0.contains(marker) }) {
            end = found
        } else {
            return screen
        }
        // Where it starts, found by putting rows back together rather than in
        // any one row: a terminal narrow enough to wrap the question wraps the
        // warning and the fingerprint as well, and a start looked for in a
        // single row fell back to four rows — which at those widths cut the
        // fingerprint out, at the one moment somebody has to read it.
        let start =
            firstRow(holding: tightOpening, in: rows, upTo: end)
            ?? firstRow(holding: tightFingerprintLine, in: rows, upTo: end)
            ?? max(0, end - 4)
        return rows[start...end].joined(separator: "\n")
    }

    /// Going back from `end`, the row on which `phrase` begins, with the rows
    /// put back together and their whitespace taken out.
    ///
    /// Linear however long the scrollback: a phrase beginning on a row can run
    /// on into the next only by a few characters fewer than its own length,
    /// so each row is checked with just that much of what follows it, rather
    /// than with everything after it joined again on every step back.
    private static func firstRow(holding phrase: String, in rows: [String], upTo end: Int) -> Int? {
        var following = ""
        for row in stride(from: end, through: 0, by: -1) {
            let window = tightened(rows[row]) + following
            if window.contains(phrase) { return row }
            following = String(window.prefix(phrase.count - 1))
        }
        return nil
    }

    /// What ssh actually writes. Matched as a fragment rather than whole,
    /// because the rest of the line differs between versions and between the
    /// yes/no and the yes/no/[fingerprint] forms.
    private static let marker = "continue connecting (yes/no"
    private static let opening = "authenticity of host"
    /// The line carrying the fingerprint, found without its key type or its
    /// version's punctuation: `fingerprint is SHA256:` in older releases,
    /// `fingerprint is: SHA256:` in 10.3.
    private static let fingerprintLine = "key fingerprint is"

    /// The same phrase with the spaces taken out, for comparing against rows
    /// that have been put back together. Derived rather than written twice,
    /// so the two cannot drift apart.
    private static let tightMarker = tightened(marker)
    private static let tightOpening = tightened(opening)
    private static let tightFingerprintLine = tightened(fingerprintLine)

    private static func tightened(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    /// The last rows that carry anything, which is where the question sits
    /// while it is live.
    ///
    /// **Sixteen**, which is the prompt at any width a terminal is ever given:
    /// OpenSSH's prompt is 68 characters with the phrase starting 25 in, so it
    /// takes three rows under 34 columns, four at 16, five at 13, six at 8 —
    /// and sixteen rows hold it down to about three. It used to be two, because
    /// this depth was what kept an answered question from reading as live, and
    /// a deeper tail would have let the reply sit inside it. That job is
    /// `isBeingAsked`'s now — nothing may follow the closing `?` — so depth only
    /// has to reach far enough back to find the phrase. It is bounded rather
    /// than the whole screen because the screen includes scrollback and the
    /// watchdog asks five times a second for as long as a session runs.
    private static func tail(of screen: String) -> [String] {
        screen
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(16)
    }
}
