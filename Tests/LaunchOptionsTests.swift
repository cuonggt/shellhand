import Foundation
import Testing

@testable import Shellhand

/// Where a run under test is pointed, rather than the user's own files.
///
/// The suite is hosted by the app, so running it launches the app — and both
/// of the files `LaunchOptions` decides about are the user's: the host list,
/// which an early run opened and migrated, and the config, whose ssh options
/// become every connection's. These check the decision, not the file, so
/// neither real file is touched to find out.
@MainActor
@Suite("Where a run under test is pointed")
struct LaunchOptionsTests {
    @Test("a run under test reads a config of its own, not the user's")
    func scratchConfig() {
        let options = LaunchOptions(arguments: ["Shellhand"])
        #expect(options.configPath == LaunchOptions.scratchConfig)
        // The path actually read, by `Core.configure`'s own rule — empty means
        // the default. Comparing `configPath` itself would pass with the
        // redirect gone, since its empty sentinel *is* the user's file.
        let read = Config.path(options.configPath)
        #expect(read != Config.defaultPath)
        #expect(read.hasPrefix(NSTemporaryDirectory()))
    }

    @Test("a run under test opens a store of its own, not the user's")
    func scratchStore() {
        let options = LaunchOptions(arguments: ["Shellhand"])
        #expect(options.db == LaunchOptions.scratchStore)
        #expect(options.db != Store.defaultPath)
    }

    /// What `--config` and `--db` name still wins: the redirect is a default,
    /// not a lock, and `window-check.sh` depends on `--db` being honoured.
    @Test("a path named on the command line still wins")
    func namedPathsWin() {
        let options = LaunchOptions(arguments: [
            "Shellhand", "--db", "/somewhere/else.sqlite", "--config", "/somewhere/else.yaml",
        ])
        #expect(options.db == "/somewhere/else.sqlite")
        #expect(options.configPath == "/somewhere/else.yaml")
    }
}

/// What launching makes of the settings file.
///
/// Only files that fail are read here: one that works would set the ssh
/// options of every connection the rest of the suite makes beside these, and
/// a file that fails applies nothing. The user's own is never read.
@Suite("What launching makes of the settings file")
nonisolated struct LaunchConfigTests {
    private func config(_ text: String) throws -> String {
        let path = TestScratch.directory("config") + "/config.yaml"
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// The bug: a `try?` dropped this, and the app ran without the file
    /// while nothing anywhere said so.
    @Test("a settings file that is not YAML is said, not dropped")
    func notYAMLIsSaid() throws {
        let path = try config("ssh_options:\n  - \"ServerAliveInterval=30\n")
        let launched = LaunchConfig.read(path)
        #expect(launched.path == path)
        let problem = try #require(launched.problem, "the problem was dropped")
        #expect(problem.contains("not valid YAML"))
        #expect(problem.contains("line 2"))
        #expect(problem.contains("Nothing in it applies"))
    }

    /// Every refusal `Config.parse` makes was dropped the same way, not only
    /// broken YAML.
    @Test("a key that is not a setting is said too")
    func unknownKeyIsSaid() throws {
        let path = try config("ssh_option:\n  - BatchMode=yes\n")
        #expect(LaunchConfig.read(path).problem?.contains("is not a setting") == true)
    }

    @Test("no file named is the usual one")
    func usualPath() {
        #expect(Config.path("") == Config.defaultPath)
        #expect(Config.path("/somewhere/else.yaml") == "/somewhere/else.yaml")
    }
}
