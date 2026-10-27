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
        let read = options.configPath.isEmpty ? Config.defaultPath : options.configPath
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
