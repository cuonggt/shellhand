import AppKit
import Testing
@testable import Shellhand

/// What the font picker offers and what a stored name comes to, asked of
/// fonts every Mac ships: Menlo is monospaced and Helvetica is not.
///
/// Deliberately no `Host` here: `AppKit` brings `Foundation.Host` with it.
@MainActor
@Suite("Terminal font")
struct TerminalFontTests {
    private let size: CGFloat = 13
    private var system: NSFont { NSFont.monospacedSystemFont(ofSize: size, weight: .regular) }

    @Test("nothing chosen is SF Mono, the system's own")
    func nothingChosen() {
        let font = TerminalFont.font(named: "", size: size)
        #expect(font.fontName == system.fontName)
        #expect(font.pointSize == size)
    }

    @Test("a monospaced family installed here is the one drawn, at the size asked")
    func chosenFamily() {
        let font = TerminalFont.font(named: "Menlo", size: size)
        #expect(font.familyName == "Menlo")
        #expect(font.pointSize == size)
    }

    /// The setting travels with a migrated Mac, and SwiftTerm lays text on a
    /// grid of one cell width — so both of these fall back rather than leave
    /// a terminal in a font it cannot use.
    @Test("a family not installed, or not monospaced, falls back to SF Mono")
    func fallsBack() {
        #expect(TerminalFont.font(named: "No Such Family", size: size).fontName == system.fontName)
        #expect(TerminalFont.font(named: "Helvetica", size: size).fontName == system.fontName)
    }

    @Test("monospaced is asked of the family's own regular face")
    func monospaced() {
        #expect(TerminalFont.isMonospaced("Menlo"))
        #expect(!TerminalFont.isMonospaced("Helvetica"))
        #expect(!TerminalFont.isMonospaced("No Such Family"))
    }

    @Test("the picker offers monospaced families in reading order, without hidden ones or a second SF Mono")
    func choices() {
        let families = ["Menlo", ".SF NS Mono", "Helvetica", "SF Mono", "JetBrains Mono", "Courier"]
        let monospaced: Set = ["Menlo", ".SF NS Mono", "SF Mono", "JetBrains Mono", "Courier"]
        #expect(TerminalFont.choices(among: families, isMonospaced: monospaced.contains)
            == ["Courier", "JetBrains Mono", "Menlo"])
    }

    @Test("this Mac's list holds Menlo, and neither Helvetica nor SF Mono")
    func onThisMac() {
        #expect(TerminalFont.onThisMac.contains("Menlo"))
        #expect(!TerminalFont.onThisMac.contains("Helvetica"))
        #expect(!TerminalFont.onThisMac.contains(TerminalFont.systemName))
    }
}
