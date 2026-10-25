import Testing
@testable import Shellhand

@Suite("Colours")
nonisolated struct RGBTests {
    @Test("a colour is six hex digits, with or without the hash")
    func sixDigits() {
        #expect(RGB(hex: "#1d1f21") == RGB(0x1D, 0x1F, 0x21))
        #expect(RGB(hex: "1d1f21") == RGB(0x1D, 0x1F, 0x21))
        #expect(RGB(hex: "#1D1F21") == RGB(0x1D, 0x1F, 0x21))
        #expect(RGB(hex: "  #1d1f21 ") == RGB(0x1D, 0x1F, 0x21))
    }

    @Test("three digits are the short way of writing the same thing")
    func threeDigits() {
        #expect(RGB(hex: "#abc") == RGB(0xAA, 0xBB, 0xCC))
        #expect(RGB(hex: "fff") == RGB(255, 255, 255))
    }

    @Test("anything that is not a colour is refused rather than guessed at")
    func refusals() {
        #expect(RGB(hex: "") == nil)
        #expect(RGB(hex: "#12345") == nil)
        #expect(RGB(hex: "#1234567") == nil)
        #expect(RGB(hex: "#zzzzzz") == nil)
        #expect(RGB(hex: "rebeccapurple") == nil)
    }

    @Test("it writes back the way it was read")
    func roundTrip() {
        #expect(RGB(hex: "#1d1f21")?.hex == "#1d1f21")
        #expect(RGB(0, 0, 0).hex == "#000000")
        #expect(RGB(255, 255, 255).hex == "#ffffff")
    }
}

@Suite("Themes", .serialized)
nonisolated struct ThemeTests {
    @Test("every palette that ships has all sixteen colours")
    func builtInsAreComplete() {
        for palette in Themes.builtIn {
            #expect(palette.isComplete, "\(palette.name) has \(palette.ansi.count)")
            #expect(!palette.name.isEmpty)
        }
    }

    @Test("no two of them share a name, since the name is how one is chosen")
    func namesAreDistinct() {
        let names = Themes.builtIn.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count)
    }

    @Test("the system palette is nothing to install, not a palette of its own")
    func systemIsNil() {
        #expect(Themes.named(Themes.systemName) == nil)
        #expect(Themes.names.first == Themes.systemName)
    }

    @Test("a palette is found by name, however it is cased")
    func lookup() {
        #expect(Themes.named("Nord")?.name == "Nord")
        #expect(Themes.named("nord")?.name == "Nord")
    }

    @Test("a name nothing answers to leaves the terminal alone")
    func unknownName() {
        // A theme renamed in the settings file should not blank the terminal.
        #expect(Themes.named("Something Else Entirely") == nil)
    }

    @Test("palettes from the settings file join the ones that ship")
    func customJoinsIn() {
        defer { Themes.setCustom([]) }
        let mine = Palette(
            name: "Mine", ansi: Array(repeating: RGB(1, 2, 3), count: 16),
            background: RGB(0, 0, 0), foreground: RGB(255, 255, 255),
            cursor: RGB(255, 0, 0), selection: RGB(0, 0, 255))
        Themes.setCustom([mine])
        #expect(Themes.named("Mine")?.background == RGB(0, 0, 0))
        #expect(Themes.names.contains("Mine"))
        #expect(Themes.all.count == Themes.builtIn.count + 1)
    }
}

@Suite("Themes in the settings file")
nonisolated struct ThemeConfigTests {
    private let sixteen = (0..<16).map { _ in "\"#102030\"" }.joined(separator: ", ")

    private func file(_ body: String) -> String {
        """
        themes:
          - name: Mine
            ansi: [\(sixteen)]
        \(body)
        """
    }

    @Test("a palette is read whole")
    func reads() throws {
        let config = try Config.parse(file("""
                background: "#000000"
                foreground: "#ffffff"
                cursor: "#ff0000"
                selection: "#0000ff"
            """))
        let palette = try #require(config.themes.first)
        #expect(palette.name == "Mine")
        #expect(palette.ansi.count == 16)
        #expect(palette.foreground == RGB(255, 255, 255))
        #expect(palette.cursor == RGB(255, 0, 0))
    }

    @Test("a colour that is not one is refused, and the palette with it")
    func badColour() {
        #expect(throws: ConfigError.self) {
            try Config.parse(file("""
                    background: "not a colour"
                    foreground: "#ffffff"
                    cursor: "#ff0000"
                    selection: "#0000ff"
                """))
        }
    }

    @Test("a palette missing a colour is refused rather than half-applied")
    func missingColour() {
        #expect(throws: ConfigError.self) {
            try Config.parse(file("""
                    background: "#000000"
                    foreground: "#ffffff"
                """))
        }
    }

    @Test("a palette with the wrong number of ansi colours is refused")
    func wrongCount() {
        #expect(throws: ConfigError.self) {
            try Config.parse("""
                themes:
                  - name: Short
                    ansi: ["#000000", "#ffffff"]
                    background: "#000000"
                    foreground: "#ffffff"
                    cursor: "#ff0000"
                    selection: "#0000ff"
                """)
        }
    }

    @Test("a field that is not part of a palette is an error, as elsewhere")
    func unknownField() {
        #expect(throws: ConfigError.self) {
            try Config.parse(file("""
                    background: "#000000"
                    foreground: "#ffffff"
                    cursor: "#ff0000"
                    selection: "#0000ff"
                    bold: "#ffffff"
                """))
        }
    }

    @Test("a file with no themes still reads, and has none")
    func noThemes() throws {
        #expect(try Config.parse("ssh_options:\n  - BatchMode=yes\n").themes.isEmpty)
    }
}
