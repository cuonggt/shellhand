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
        tail(of: screen).contains { $0.contains(marker) }
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
        guard let end = lines.lastIndex(where: { $0.contains(marker) }) else { return screen }
        let start = lines[..<end].lastIndex { $0.contains(opening) } ?? max(0, end - 4)
        return lines[start...end].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// What ssh actually writes. Matched as a fragment rather than whole,
    /// because the rest of the line differs between versions and between the
    /// yes/no and the yes/no/[fingerprint] forms.
    private static let marker = "continue connecting (yes/no"
    private static let opening = "authenticity of host"

    /// The last couple of lines that carry anything, which is where the
    /// question sits when it is live.
    private static func tail(of screen: String) -> [String] {
        screen
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(2)
    }
}
