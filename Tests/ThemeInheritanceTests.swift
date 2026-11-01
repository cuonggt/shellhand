import Foundation
import Testing
@testable import Shellhand

/// A palette is inherited the way every other group setting is: the nearest
/// thing that names one wins, per parameter, however deep the nesting.
@Suite("A palette down the group chain")
nonisolated struct ThemeInheritanceTests {
    /// Production → Production/EU, and a group that names nothing.
    /// `Shellhand.Host` because Foundation has a `Host` of its own.
    private func resolver(
        hosts: [Shellhand.Host], groups: [Shellhand.Group]
    ) -> Resolver {
        Resolver(groups: groups, hosts: hosts)
    }

    private let groups: [Shellhand.Group] = [
        Group(id: "prod", name: "Production", theme: "Gruvbox Dark"),
        Group(id: "eu", name: "Production/EU", parentId: "prod"),
        Group(id: "staging", name: "Staging", parentId: "", theme: "Solarized Light"),
        Group(id: "plain", name: "Plain"),
    ]

    /// The inherit row of a host with a palette of its own was named after
    /// that same palette — "Dracula from above" — since what inheriting
    /// gives was read off a host that set one. It is read with its own left
    /// out.
    @Test("what inheriting gives is said without the host's own palette")
    func inheritedWithoutItsOwn() {
        let host = Host(id: "1", name: "web", groupId: "prod", theme: "Dracula")
        let asked = HostDetailView.inheriting(host)
        let out = resolver(hosts: [host], groups: groups).resolve(asked).effective
        #expect(out.inheritedPalette == "Gruvbox Dark from Production")
        // In two parts for the inspector's row, which says where from as a
        // caption: the sentence wrapped a word to a line there.
        #expect(out.inheritedPaletteParts.name == "Gruvbox Dark")
        #expect(out.inheritedPaletteParts.from == "Production")
        #expect(host.theme == "Dracula", "the host itself was changed")
    }

    @Test("a host that names none takes its group's")
    func fromItsGroup() {
        let host = Host(id: "1", name: "web", groupId: "prod")
        let out = resolver(hosts: [host], groups: groups).resolve(host)
        #expect(out.theme == "Gruvbox Dark")
        #expect(out.themeFrom == "Production")
    }

    @Test("a group that names none takes its parent's, however deep")
    func fromAGrandparent() {
        let host = Host(id: "1", name: "web", groupId: "eu")
        let out = resolver(hosts: [host], groups: groups).resolve(host)
        #expect(out.theme == "Gruvbox Dark")
        // The name recorded is the group that actually said so, not the one
        // the host is filed under.
        #expect(out.themeFrom == "Production")
    }

    @Test("a host's own beats anything above it")
    func itsOwnWins() {
        let host = Host(id: "1", name: "web", groupId: "prod", theme: "Nord")
        let out = resolver(hosts: [host], groups: groups).resolve(host)
        #expect(out.theme == "Nord")
        // Nothing above supplied it, so there is nothing to credit.
        #expect(out.themeFrom.isEmpty)
    }

    @Test("a group's own beats its parent's")
    func nearestGroupWins() {
        var nested = groups
        nested[1].theme = "Nord"
        let host = Host(id: "1", name: "web", groupId: "eu")
        let out = resolver(hosts: [host], groups: nested).resolve(host)
        #expect(out.theme == "Nord")
        #expect(out.themeFrom == "Production/EU")
    }

    @Test("nothing anywhere in the chain leaves it to Settings")
    func nothingChosen() {
        let host = Host(id: "1", name: "web", groupId: "plain")
        let out = resolver(hosts: [host], groups: groups).resolve(host)
        #expect(out.theme.isEmpty)
        #expect(out.themeFrom.isEmpty)
    }

    @Test("an ungrouped host is left to Settings too")
    func ungrouped() {
        let host = Host(id: "1", name: "loose")
        #expect(resolver(hosts: [host], groups: groups).resolve(host).theme.isEmpty)
    }

    @Test("two groups give their own hosts their own colours")
    func sideBySide() {
        let hosts: [Shellhand.Host] = [
            Host(id: "1", name: "prod-web", groupId: "prod"),
            Host(id: "2", name: "staging-web", groupId: "staging"),
        ]
        let r = resolver(hosts: hosts, groups: groups)
        #expect(r.resolve(hosts[0]).theme == "Gruvbox Dark")
        #expect(r.resolve(hosts[1]).theme == "Solarized Light")
    }

    @Test("it reaches the shape the window reads")
    func intoEffective() {
        let host = Host(id: "1", name: "web", groupId: "prod")
        let effective = resolver(hosts: [host], groups: groups).resolve(host).effective
        #expect(effective.theme == "Gruvbox Dark")
        #expect(effective.themeFrom == "Production")
    }
}

/// What a terminal is actually painted with, which is not quite what was
/// resolved: a name nothing answers to has to fall back rather than blank the
/// screen, and "System" means something different from saying nothing.
@Suite("Choosing what to paint with", .serialized)
@MainActor
struct ThemeChoiceTests {
    private func host(_ theme: String) -> Shellhand.Host {
        var host = Shellhand.Host(id: "1", name: "web")
        host.effective.theme = theme
        return host
    }

    @Test("a palette the chain named is the one installed")
    func named() {
        #expect(TerminalSession.theme(for: host("Nord"))?.name == "Nord")
    }

    @Test("the case it was written in does not matter")
    func cased() {
        #expect(TerminalSession.theme(for: host("nord"))?.name == "Nord")
    }

    @Test("System means the terminal's own colours, not the Settings palette")
    func system() {
        UserDefaults.standard.set("Nord", forKey: "terminalTheme")
        defer { UserDefaults.standard.removeObject(forKey: "terminalTheme") }
        // Saying nothing falls through to Settings …
        #expect(TerminalSession.theme(for: host(""))?.name == "Nord")
        // … while asking for System plainly does not.
        #expect(TerminalSession.theme(for: host(Themes.systemName)) == nil)
    }

    @Test("a name nothing answers to falls back rather than blanking the terminal")
    func renamedAway() {
        UserDefaults.standard.set("Nord", forKey: "terminalTheme")
        defer { UserDefaults.standard.removeObject(forKey: "terminalTheme") }
        // A palette the settings file used to define and no longer does.
        #expect(TerminalSession.theme(for: host("Gone Away"))?.name == "Nord")
    }

    @Test("a local shell, which has no host, takes the Settings palette")
    func noHost() {
        UserDefaults.standard.set("Nord", forKey: "terminalTheme")
        defer { UserDefaults.standard.removeObject(forKey: "terminalTheme") }
        #expect(TerminalSession.theme(for: nil)?.name == "Nord")
    }
}

/// A field that does not survive the export is worse than not having one.
@Suite("A palette through the file")
nonisolated struct ThemePortableTests {
    @Test("a host's and a group's palette are both written and read back")
    func roundTrip() throws {
        let groups: [Shellhand.Group] = [
            Group(id: "g", name: "Production", theme: "Gruvbox Dark"),
        ]
        let hosts: [Shellhand.Host] = [
            Host(id: "1", name: "web", addr: "10.0.0.1", groupId: "g", theme: "Nord"),
            Host(id: "2", name: "db", addr: "10.0.0.2", groupId: "g"),
        ]
        let yaml = try Portable.export(groups: groups, hosts: hosts)
        let read = try Portable.parse(yaml)
        #expect(read.groups.first?.theme == "Gruvbox Dark")
        #expect(read.hosts.first { $0.name == "web" }?.theme == "Nord")
        // The one that chose nothing stays having chosen nothing, rather than
        // having its group's written onto it.
        #expect(read.hosts.first { $0.name == "db" }?.theme == "")
    }

    @Test("a file that names no palette anywhere still reads")
    func absent() throws {
        let yaml = try Portable.export(
            groups: [], hosts: [Shellhand.Host(id: "1", name: "web", addr: "10.0.0.1")])
        #expect(!yaml.contains("theme"))
        #expect(try Portable.parse(yaml).hosts.first?.theme == "")
    }

    @Test("a palette in a file reaches the store through the merge")
    func merges() throws {
        let store = try Store(path: TestScratch.database())
        let document = try Portable.parse("""
            groups:
              - name: Production
                theme: Gruvbox Dark
            hosts:
              - name: web
                addr: 10.0.0.1
                group: Production
                theme: Nord
            """)
        try store.apply(try Portable.merge(
            document, into: try store.snapshot()))
        let snapshot = try store.snapshot()
        #expect(snapshot.groups.first?.theme == "Gruvbox Dark")
        #expect(snapshot.hosts.first?.theme == "Nord")
    }

    @Test("a theme that is not part of a record is still an error, as elsewhere")
    func unknownField() {
        #expect(throws: PortableError.self) {
            try Portable.parse("""
                hosts:
                  - name: web
                    addr: 10.0.0.1
                    colours: Nord
                """)
        }
    }
}

/// The picker over a window too short for it: Settings, 500 tall and down to
/// 420, hung the picker's Done below the window's edge.
@Suite("The palette picker's height")
nonisolated struct PalettePickerHeightTests {
    @Test("the picker fits under the toolbar of the window it opens over")
    func fits() {
        let seven = PalettePicker.chrome + 7 * PalettePicker.rowHeight
        // Every row, the inherit row with the palettes, where there is room:
        // held to 460, the last palette was out of sight in a window of 668.
        #expect(PalettePicker.height(rows: 7, in: nil) == seven)
        #expect(PalettePicker.height(rows: 7, in: 700) == seven)
        // Settings at its default: within the room below its toolbar, less a
        // margin — four palettes and half the fifth.
        #expect(PalettePicker.height(rows: 6, in: 420) == PalettePicker.chrome + 4.5 * PalettePicker.rowHeight)
        // However little room, never so short that nothing fits in it.
        #expect(PalettePicker.height(rows: 7, in: 100) == 240)
    }

    /// Cut on a row's edge, Settings showed five palettes of six and nothing
    /// to say there was a sixth.
    @Test("a list cut short ends partway down a row, never on its edge")
    func cutPartway() {
        for room in stride(from: 300.0, through: 560.0, by: 1.0) {
            let height = PalettePicker.height(rows: 7, in: room)
            let shown = (height - PalettePicker.chrome) / PalettePicker.rowHeight
            guard shown < 7 else { continue }
            #expect(height <= max(240, room - 40))
            let into = shown - shown.rounded(.down)
            #expect(into > 0.25 && into < 0.75, "at \(room) it shows \(shown) rows")
        }
    }
}
