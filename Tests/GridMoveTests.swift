import Foundation
import Testing

@testable import Shellhand

/// Arrow keys in the host pane's grid.
///
/// A `LazyVGrid` has no selection of its own, so every step here is a decision
/// rather than something AppKit does — which is exactly what makes it worth
/// testing away from the window. The cases that matter are the seams: the
/// boundary between the two grids, the ragged last row, and the edges where a
/// key should do nothing at all.
///
/// Sections are `[groups, hosts]`, in the order the pane draws them, and an
/// index is into the flat run of cards across both.
@Suite("Grid moves")
nonisolated struct GridMoveTests {
    // MARK: along a row

    @Test("right goes to the next card, left to the one before")
    func alongTheRow() {
        #expect(GridMove.next(.right, from: 0, sections: [0, 4], columns: 2) == 1)
        #expect(GridMove.next(.left, from: 1, sections: [0, 4], columns: 2) == 0)
    }

    /// Left and right walk the flat order, so they cross from the groups into
    /// the hosts without a special case — there is no row to stay on.
    @Test("right off the end of the groups lands on the first host")
    func rightCrossesTheSections() {
        #expect(GridMove.next(.right, from: 1, sections: [2, 3], columns: 2) == 2)
        #expect(GridMove.next(.left, from: 2, sections: [2, 3], columns: 2) == 1)
    }

    @Test("right at the very end and left at the very start do nothing")
    func theEndsAreEnds() {
        #expect(GridMove.next(.right, from: 4, sections: [2, 3], columns: 2) == nil)
        #expect(GridMove.next(.left, from: 0, sections: [2, 3], columns: 2) == nil)
    }

    // MARK: down a column

    @Test("down moves a row within a section")
    func downARow() {
        // Six hosts, three across: 0 1 2 / 3 4 5
        #expect(GridMove.next(.down, from: 1, sections: [0, 6], columns: 3) == 4)
        #expect(GridMove.next(.up, from: 4, sections: [0, 6], columns: 3) == 1)
    }

    /// The case a flat model gets wrong, and the reason this takes sections.
    /// Two groups, four columns: flat arithmetic would send "down" from the
    /// first group four cards into the hosts, rather than to the one drawn
    /// directly beneath it.
    @Test("down out of the groups lands in the hosts at the same column")
    func downCrossesTheBoundary() {
        #expect(GridMove.next(.down, from: 0, sections: [2, 5], columns: 4) == 2)
        #expect(GridMove.next(.down, from: 1, sections: [2, 5], columns: 4) == 3)
    }

    /// And back the other way, arriving in that section's **last** row rather
    /// than its first — which is the row the eye came from.
    @Test("up out of the hosts lands in the groups' last row")
    func upCrossesTheBoundary() {
        // Five groups, two across: 0 1 / 2 3 / 4 — last row starts at 4.
        #expect(GridMove.next(.up, from: 5, sections: [5, 4], columns: 2) == 4)
        // Column 1 of that last row does not exist, so it clamps to the card
        // that does.
        #expect(GridMove.next(.up, from: 6, sections: [5, 4], columns: 2) == 4)
    }

    /// A narrower section cannot hold the column arrived from.
    @Test("down into a section too narrow for the column clamps to its last")
    func downClampsIntoANarrowSection() {
        #expect(GridMove.next(.down, from: 3, sections: [4, 2], columns: 4) == 5)
    }

    // MARK: the ragged last row

    /// Five cards, three across: 0 1 2 / 3 4. Down from 2 has nothing beneath
    /// it, and a grid falls to the last card rather than refusing to move.
    @Test("down from above the ragged gap falls to the last card")
    func downFallsToTheLast() {
        #expect(GridMove.next(.down, from: 2, sections: [0, 5], columns: 3) == 4)
    }

    @Test("down from the last card itself does nothing")
    func downFromTheLastDoesNothing() {
        #expect(GridMove.next(.down, from: 4, sections: [0, 5], columns: 3) == nil)
    }

    /// Found by fixing the one above: "down" from a card already in the last
    /// row was sliding **sideways** to the last card, because the ragged-gap
    /// rule and the last-row case had been conflated. Nobody pressed right.
    @Test("down from inside the last row does nothing")
    func downFromTheLastRowDoesNothing() {
        // 0 1 2 / 3 4 — card 3 is in the last row with nothing beneath it.
        #expect(GridMove.next(.down, from: 3, sections: [0, 5], columns: 3) == nil)
    }

    @Test("up from the first row of the first section does nothing")
    func upFromTheTopDoesNothing() {
        #expect(GridMove.next(.up, from: 1, sections: [0, 5], columns: 3) == nil)
    }

    // MARK: sections that are not there

    /// The pane draws no "Groups" heading when there are none, so the hosts
    /// are the only grid and an empty section must not be landed in.
    @Test("an empty section is stepped over rather than entered")
    func emptySectionsAreSkipped() {
        #expect(GridMove.next(.down, from: 0, sections: [0, 4], columns: 2) == 2)
        #expect(GridMove.next(.up, from: 2, sections: [0, 4], columns: 2) == 0)
        #expect(GridMove.next(.down, from: 1, sections: [2, 0], columns: 2) == nil)
    }

    // MARK: nothing to move through

    @Test("no cards, no columns, or an index off the end move nowhere")
    func nothingToMoveThrough() {
        #expect(GridMove.next(.right, from: 0, sections: [], columns: 3) == nil)
        #expect(GridMove.next(.right, from: 0, sections: [0, 0], columns: 3) == nil)
        #expect(GridMove.next(.right, from: 0, sections: [0, 4], columns: 0) == nil)
        #expect(GridMove.next(.right, from: 9, sections: [0, 4], columns: 2) == nil)
        #expect(GridMove.next(.right, from: -1, sections: [0, 4], columns: 2) == nil)
    }

    /// One card is every edge at once.
    @Test("a single card cannot be left")
    func oneCardGoesNowhere() {
        for direction in [GridMove.Direction.left, .right, .up, .down] {
            #expect(GridMove.next(direction, from: 0, sections: [0, 1], columns: 3) == nil)
        }
    }
}
