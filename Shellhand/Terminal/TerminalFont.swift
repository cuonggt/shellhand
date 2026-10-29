import AppKit

/// Which font a terminal is drawn in: the family Settings names, or SF Mono.
///
/// Out of the session and out of Settings so the decisions — what the picker
/// offers, and what a stored name comes to — can be asked without a window.
/// The fonts are the system's, so the tests ask real ones: Menlo and
/// Helvetica ship with every Mac.
enum TerminalFont {
    /// Where Settings keeps the family, named once so the picker and the
    /// sessions cannot read two different keys.
    nonisolated static let setting = "terminalFont"

    /// What the first row of the picker says, and what an empty name means:
    /// the system's own monospaced face.
    nonisolated static let systemName = "SF Mono"

    /// The family a new terminal is drawn in, or empty for SF Mono — which
    /// is also what nothing stored means.
    nonisolated static var preferred: String {
        UserDefaults.standard.string(forKey: setting) ?? ""
    }

    /// The font for a stored family at a size.
    ///
    /// **SF Mono for anything that cannot draw a terminal**: a family not
    /// installed here — the setting travels with a migrated Mac — and one
    /// installed but not monospaced, since SwiftTerm lays text on a grid of
    /// one cell width. A name nothing answers to falls back rather than
    /// leaving a terminal in a font it cannot use, which is the rule a
    /// palette renamed in the settings file follows too.
    static func font(named family: String, size: CGFloat) -> NSFont {
        guard !family.isEmpty, isMonospaced(family), let font = regular(family, size: size)
        else { return NSFont.monospacedSystemFont(ofSize: size, weight: .regular) }
        return font
    }

    /// Whether a family can draw a terminal: its regular face says it is
    /// monospaced, either way a font can say so.
    static func isMonospaced(_ family: String) -> Bool {
        guard let font = regular(family, size: 12) else { return false }
        return font.isFixedPitch || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
    }

    /// What the picker offers below SF Mono: the families given that can
    /// draw a terminal, in the order a person reads them. The system's hidden
    /// families — their names start with a dot — are left out, and so is an
    /// installed SF Mono, which the first row already is.
    nonisolated static func choices(
        among families: [String], isMonospaced: (String) -> Bool
    ) -> [String] {
        families
            .filter { !$0.hasPrefix(".") && $0 != systemName && isMonospaced($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The choices on this Mac, worked out once a run: a font installed
    /// while the app is open is offered from the next launch. Each family is
    /// asked here, on the main actor that owns the font manager, so `choices`
    /// is handed a plain lookup and stays callable from anywhere.
    static let onThisMac: [String] = {
        let families = NSFontManager.shared.availableFontFamilies
        var monospaced = Set<String>()
        for family in families where isMonospaced(family) { monospaced.insert(family) }
        return choices(among: families, isMonospaced: monospaced.contains)
    }()

    /// A family's regular face — weight 5 is NSFontManager's regular.
    private static func regular(_ family: String, size: CGFloat) -> NSFont? {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
    }
}
