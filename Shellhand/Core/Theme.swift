import Foundation

/// A colour, as a terminal palette writes one.
nonisolated struct RGB: Sendable, Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    /// `#1d1f21`, `1d1f21` or `#abc`. Anything else is not a colour, and a
    /// palette that holds one is refused rather than half-applied.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        red = UInt8((value >> 16) & 0xFF)
        green = UInt8((value >> 8) & 0xFF)
        blue = UInt8(value & 0xFF)
    }

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var hex: String { String(format: "#%02x%02x%02x", red, green, blue) }
}

/// What a terminal is painted with.
///
/// Sixteen ANSI colours in the order every terminal uses them — black, red,
/// green, yellow, blue, magenta, cyan, white, then the bright eight — and the
/// four the terminal itself needs.
nonisolated struct Palette: Sendable, Equatable {
    var name: String
    var ansi: [RGB]
    var background: RGB
    var foreground: RGB
    var cursor: RGB
    var selection: RGB

    var isComplete: Bool { ansi.count == 16 }
}

/// The palettes on offer: the ones that ship, and any the settings file adds.
nonisolated enum Themes {
    /// What a terminal uses when nothing has been chosen — SwiftTerm's own,
    /// left alone rather than replaced by a guess at what the system wants.
    static let systemName = "System"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var custom: [Palette] = []

    /// Palettes from the settings file, which is where anyone with a palette
    /// of their own already keeps it. Typing eighteen colours into a form is
    /// nobody's idea of an afternoon.
    static func setCustom(_ palettes: [Palette]) {
        lock.lock()
        defer { lock.unlock() }
        custom = palettes
    }

    static var all: [Palette] {
        lock.lock()
        defer { lock.unlock() }
        return builtIn + custom
    }

    /// Every name that can be chosen, the system one first.
    static var names: [String] { [systemName] + all.map(\.name) }

    /// Nil for the system palette, and for a name nothing answers to — a
    /// theme that was renamed in the settings file should leave the terminal
    /// as it was rather than blank it.
    static func named(_ name: String) -> Palette? {
        guard name != systemName else { return nil }
        return all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: the ones that ship

    static let builtIn: [Palette] = [solarizedDark, solarizedLight, nord, gruvboxDark, tomorrowNight]

    private static func rgb(_ hex: String) -> RGB { RGB(hex: hex) ?? RGB(0, 0, 0) }

    static let solarizedDark = Palette(
        name: "Solarized Dark",
        ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198",
               "#eee8d5", "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4",
               "#93a1a1", "#fdf6e3"].map(rgb),
        background: rgb("#002b36"), foreground: rgb("#839496"),
        cursor: rgb("#93a1a1"), selection: rgb("#073642"))

    static let solarizedLight = Palette(
        name: "Solarized Light",
        ansi: ["#eee8d5", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198",
               "#073642", "#fdf6e3", "#cb4b16", "#93a1a1", "#839496", "#657b83", "#6c71c4",
               "#586e75", "#002b36"].map(rgb),
        background: rgb("#fdf6e3"), foreground: rgb("#657b83"),
        cursor: rgb("#586e75"), selection: rgb("#eee8d5"))

    static let nord = Palette(
        name: "Nord",
        ansi: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0",
               "#e5e9f0", "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead",
               "#8fbcbb", "#eceff4"].map(rgb),
        background: rgb("#2e3440"), foreground: rgb("#d8dee9"),
        cursor: rgb("#d8dee9"), selection: rgb("#434c5e"))

    static let gruvboxDark = Palette(
        name: "Gruvbox Dark",
        ansi: ["#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a",
               "#a89984", "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b",
               "#8ec07c", "#ebdbb2"].map(rgb),
        background: rgb("#282828"), foreground: rgb("#ebdbb2"),
        cursor: rgb("#ebdbb2"), selection: rgb("#504945"))

    static let tomorrowNight = Palette(
        name: "Tomorrow Night",
        ansi: ["#1d1f21", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb", "#8abeb7",
               "#c5c8c6", "#969896", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb",
               "#8abeb7", "#ffffff"].map(rgb),
        background: rgb("#1d1f21"), foreground: rgb("#c5c8c6"),
        cursor: rgb("#c5c8c6"), selection: rgb("#373b41"))
}
