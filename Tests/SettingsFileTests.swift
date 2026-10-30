import Foundation
import Testing
@testable import Shellhand

/// What Create Settings File writes, held to being a file this app reads.
@Suite("The settings file's template")
nonisolated struct SettingsFileTests {
    /// Commented out whole, so making the file changes nothing until a line
    /// in it is taken back in — and a settings file that cannot be used is
    /// said at launch, so a template that broke would be met on every one.
    @Test("as written it sets nothing, and parses")
    func setsNothing() throws {
        #expect(try Config.parse(Config.template) == Config())
    }

    /// The example is what the template shows, and it is held to being
    /// settings this app takes rather than a sketch of them.
    @Test("its example, taken in, is two ssh options and a whole palette")
    func exampleIsReal() throws {
        let config = try Config.parse(Config.example)
        #expect(config.sshOptions == ["ServerAliveInterval=30", "IdentitiesOnly=yes"])
        #expect(config.themes.map(\.name) == ["Paper"])
        #expect(config.themes.first?.isComplete == true)
    }

    @Test("the template is the example commented out, a line at a time")
    func commentedExample() {
        for line in Config.example.split(separator: "\n") {
            #expect(Config.template.contains("# " + line), "missing: \(line)")
        }
    }

    /// Never over a file already there: that is somebody's settings.
    @Test("making it writes the template where there is none, and leaves one that is there")
    func neverOverwrites() throws {
        let path = TestScratch.directory("settings") + "/nested/config.yaml"
        try Config.create(at: path)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == Config.template)

        let own = "ssh_options:\n  - Compression=yes\n"
        try own.write(toFile: path, atomically: true, encoding: .utf8)
        try Config.create(at: path)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == own)
    }
}
