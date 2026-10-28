import Foundation

/// Where an arrow key takes the selection in the host pane's grid.
///
/// Out here for the reason `Panes`, `Browsing` and `SidebarRows` are: a rule
/// that lives in a view can only be checked by driving the view, and this
/// app's window does not answer to `click at`. The list gets its arrows free
/// from `List(selection:)`; a `LazyVGrid` has no selection of its own, so
/// every step of this is a decision somebody has to make.
///
/// **The grid is two grids** — the groups, then the hosts — each laid out
/// with adaptive columns, which is why this takes the sections rather than
/// one flat run of cards. Flat arithmetic gets the boundary wrong: with two
/// groups and four columns, "down" from the first group would land four cards
/// into the hosts instead of on the card drawn directly below it.
nonisolated enum GridMove {
    enum Direction { case left, right, up, down }

    /// Where the selection lands, as an index into the flat order the cards
    /// are drawn in — every group, then every host. Nil when it would not
    /// move, so a view can leave the key unhandled and let something else
    /// have it.
    static func next(
        _ direction: Direction, from index: Int, sections: [Int], columns: Int
    ) -> Int? {
        let total = sections.reduce(0, +)
        guard total > 0, columns > 0, (0..<total).contains(index) else { return nil }

        var starts: [Int] = []
        var running = 0
        for count in sections {
            starts.append(running)
            running += count
        }
        // An empty section contains nothing, so the test never matches it and
        // it is skipped without a special case.
        let here = (0..<sections.count).first {
            starts[$0] <= index && index < starts[$0] + sections[$0]
        } ?? 0
        let offset = index - starts[here]
        let column = offset % columns

        let moved: Int
        switch direction {
        case .left:
            moved = index - 1
        case .right:
            moved = index + 1
        case .down:
            let count = sections[here]
            let lastRow = ((count - 1) / columns) * columns
            if offset + columns < count {
                moved = index + columns
            } else if offset < lastRow {
                // Above the **ragged gap**: this is not the last row, but the
                // card below it was never drawn. A grid falls to the last
                // card rather than refusing to move.
                //
                // This has to be told apart from already being in the last
                // row, and conflating the two is a bug the tests did not
                // reach: it sent "down" sideways along the final row, which
                // is a direction nobody pressed.
                moved = starts[here] + count - 1
            } else if let below = (here + 1..<sections.count).first(where: { sections[$0] > 0 }) {
                // Into the next section at the same column, which is the card
                // drawn below — and clamped, since that section may be
                // narrower than this one is wide.
                moved = starts[below] + min(column, sections[below] - 1)
            } else {
                moved = index
            }
        case .up:
            if offset - columns >= 0 {
                moved = index - columns
            } else if let above = (0..<here).last(where: { sections[$0] > 0 }) {
                let count = sections[above]
                // The same column of that section's **last** row, which is
                // where the eye expects to arrive — not its first row.
                let lastRow = ((count - 1) / columns) * columns
                moved = starts[above] + min(lastRow + column, count - 1)
            } else {
                // The top row of the first section: nothing is above it, and
                // sliding to the first card is not "up".
                moved = index
            }
        }

        let landed = max(0, min(total - 1, moved))
        return landed == index ? nil : landed
    }
}
