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
        // The window at its default 1106×720: 668 below its toolbar.
        #expect(SheetHeight.fitted(720, in: 668) == 668 - SheetHeight.margin)
        // However little room, never so short that nothing fits in it…
        #expect(SheetHeight.fitted(720, in: 200) == SheetHeight.least)
        // …nor taller than it asked to be.
        #expect(SheetHeight.fitted(300, in: 200) == 300)
    }

    @Test("the host editor's command gives way before its form does")
    func commandGivesWay() {
        let room = HostEditorSheet.commandRoom
        let spare = HostEditorSheet.formSpare
        #expect(HostEditorSheet.commandCap(wanted: 736, height: 736) == room)
        // Less short than the form can spare: the form gives it all.
        #expect(HostEditorSheet.commandCap(wanted: 736, height: 736 - spare) == room)
        // 84 short, at the window's default: the box gives what the form
        // cannot, where it gave all of it and kept two lines and a half.
        #expect(HostEditorSheet.commandCap(wanted: 736, height: 652) == room - (84 - spare))
        #expect(HostEditorSheet.commandCap(wanted: 736, height: 400) == HostEditorSheet.leastCommand)
    }

    @Test("a line along the foot takes what the form could spare the command")
    func footLinesTakeTheSpare() {
        let room = HostEditorSheet.commandRoom
        let spare = HostEditorSheet.formSpare - HostEditorSheet.footLine
        #expect(HostEditorSheet.commandCap(wanted: 736, height: 652, lines: 1) == room - (84 - spare))
        // Two lines take more than there is to spare, down to the least.
        #expect(HostEditorSheet.commandCap(wanted: 736, height: 652, lines: 2)
            == HostEditorSheet.leastCommand)
        // With room enough, a line along the foot changes nothing.
        #expect(HostEditorSheet.commandCap(wanted: 736, height: 736, lines: 2) == room)
    }

    /// Cut on a line's edge, the editor at the window's default size showed
    /// three lines that read as the whole command.
    @Test("a command cut short ends partway down a line, and one that fits is whole")
    func cutPartway() {
        let inset = HostEditorSheet.commandInset
        let line = HostEditorSheet.commandLine
        // Two lines in a box that holds three: whole.
        #expect(HostEditorSheet.commandShown(48, cap: 56) == 48)
        // The window's default, 84 short: two lines and half the third.
        let atDefault = HostEditorSheet.commandCap(wanted: 736, height: 652)
        #expect(HostEditorSheet.commandShown(140, cap: atDefault) == inset + 2 * line + 8)
        // However the cap falls, what is shown stops inside a line, some of
        // it in sight, and never past the cap.
        for cap in stride(from: HostEditorSheet.leastCommand, through: HostEditorSheet.commandRoom, by: 1) {
            let shown = HostEditorSheet.commandShown(400, cap: cap)
            #expect(shown <= cap)
            let into = (shown - inset).truncatingRemainder(dividingBy: line)
            #expect(into >= 4 && into <= 9, "a cap of \(cap) shows \(into) of a line")
        }
    }

    /// Read off the form as drawn, the box takes what the form leaves, up to
    /// six lines — and nothing where not a line fits, which held to a line
    /// left New group…'s form scrolling at the window's default size.
    /// Guessed from db-01's General, Save as Host… cut a three-line command
    /// under 58pt of empty form.
    @Test("the command's box takes what the form as drawn leaves it")
    func commandTakesWhatIsLeft() {
        #expect(HostEditorSheet.commandCap(room: 108) == 108)
        #expect(HostEditorSheet.commandCap(room: 400) == HostEditorSheet.commandRoom)
        #expect(HostEditorSheet.commandCap(room: HostEditorSheet.leastCommand)
            == HostEditorSheet.leastCommand)
        #expect(HostEditorSheet.commandCap(room: 10) == 0)
        #expect(HostEditorSheet.commandCap(room: -7) == 0)
        #expect(HostEditorSheet.commandShown(140, cap: 0) == 0)
        // Save as Host…'s three lines, whole in its 50pt of box and 58 of form.
        let three = 2 * HostEditorSheet.commandInset + 3 * HostEditorSheet.commandLine
        #expect(HostEditorSheet.commandShown(three, cap: HostEditorSheet.commandCap(room: 50 + 58))
            == three)
    }
}
