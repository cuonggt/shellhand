import CoreGraphics
import Testing
@testable import Shellhand

/// A sheet over the host window fits the room below its toolbar: the host
/// editor, 720 tall, hung below the window at its default 1100×720 in 0.1.7.
@Suite("A sheet's height over the host window")
nonisolated struct SheetHeightTests {
    @Test("a sheet is as tall as it was measured to be wherever that fits")
    func fits() {
        #expect(SheetHeight.fitted(720, in: nil) == 720)
        // The README's window, 1220×798: 746 below its toolbar.
        #expect(SheetHeight.fitted(720, in: 746) == 720)
        // The group editor and the import fit the window at its default.
        #expect(SheetHeight.fitted(570, in: 668) == 570)
        #expect(SheetHeight.fitted(560, in: 668) == 560)
    }

    @Test("over a window too short for it, a sheet is the room less a margin")
    func shorter() {
        // The window at its default 1100×720: 668 below its toolbar.
        #expect(SheetHeight.fitted(720, in: 668) == 668 - SheetHeight.margin)
        // However little room, never so short that nothing fits in it…
        #expect(SheetHeight.fitted(720, in: 200) == SheetHeight.least)
        // …nor taller than it asked to be.
        #expect(SheetHeight.fitted(300, in: 200) == 300)
    }

    @Test("the host editor's command gives way before its form does")
    func commandGivesWay() {
        #expect(HostEditorSheet.commandCap(wanted: 720, height: 720) == HostEditorSheet.commandRoom)
        // 30pt short: the command's box is 30pt shorter and the form untouched.
        #expect(HostEditorSheet.commandCap(wanted: 720, height: 690)
            == HostEditorSheet.commandRoom - 30)
        // 68 short, at the window's default: two lines of it are left.
        #expect(HostEditorSheet.commandCap(wanted: 720, height: 652) == HostEditorSheet.leastCommand)
        #expect(HostEditorSheet.commandCap(wanted: 720, height: 400) == HostEditorSheet.leastCommand)
    }
}
