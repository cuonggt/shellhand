import Foundation

/// Whose turn it is to move.
///
/// Asking for six files used to start six transfers at once, all on the one
/// ssh connection: they competed for the same link, so none of them finished
/// quickly and every progress bar crawled at a sixth of the speed. A queue
/// makes the first file arrive while the sixth is still waiting, which is
/// almost always what someone watching wants.
///
/// The rule lives here rather than in the actor that runs them, so what
/// starts when can be tested without moving a byte.
nonisolated enum TransferQueue {
    /// How many move at once unless something says otherwise.
    ///
    /// Two rather than one: a file's turn ends with a close and the next one
    /// begins with an open and a stat, and a second transfer keeps the link
    /// busy across that gap. Much more than two and they are back to
    /// competing.
    static let defaultWidth = 2

    /// Sane bounds for anything a person can set.
    static let widths = 1...8

    // MARK: the states a transfer passes through

    static let queued = "queued"
    static let running = "running"
    static let done = "done"
    static let failed = "failed"
    static let cancelled = "cancelled"

    /// Which of these should begin now.
    ///
    /// The longest-waiting first, counting what is already moving, so a queue
    /// that is already full starts nothing. `transfers` is in the order they
    /// were asked for — the order is the fairness.
    static func toStart(_ transfers: [Transfer], width: Int) -> [String] {
        let room = clamped(width) - transfers.count { $0.state == running }
        guard room > 0 else { return [] }
        return transfers.filter { $0.state == queued }.prefix(room).map(\.id)
    }

    /// A width somebody typed, brought into the range that makes sense. Zero
    /// would stop everything for ever, which is not a setting anyone means.
    static func clamped(_ width: Int) -> Int {
        min(widths.upperBound, max(widths.lowerBound, width))
    }

    /// What a strip along the bottom should say, in the fewest words that
    /// still say whether anything needs attention.
    static func summary(_ transfers: [Transfer]) -> String {
        guard !transfers.isEmpty else { return "" }
        let moving = transfers.count { $0.state == running }
        let waiting = transfers.count { $0.state == queued }
        let failed = transfers.count { $0.state == failed }

        var parts: [String] = []
        if moving > 0 { parts.append("\(moving) moving") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if failed > 0 { parts.append("\(failed) failed") }
        guard parts.isEmpty else { return parts.joined(separator: ", ") }

        // Nothing moving, waiting or broken: everything that was asked for
        // has arrived, or was called off.
        let carried = transfers.count { $0.state == done }
        if carried == 0 { return "Nothing to carry" }
        return carried == 1 ? "1 done" : "\(carried) done"
    }

    /// Whether anything is still to happen, which is what decides if the
    /// strip is worth the room it takes.
    static func busy(_ transfers: [Transfer]) -> Bool {
        transfers.contains { $0.state == running || $0.state == queued }
    }
}
