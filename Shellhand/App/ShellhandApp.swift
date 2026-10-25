import SwiftUI

/// Shellhand's Mac app: the host list, in a window, with ssh on a pty for
/// every tab.
///
/// `--db <path>` points at a store other than the real one, and
/// `--config <path>` at ssh options somewhere other than their usual place.
@main
struct ShellhandApp: App {
    private let options: LaunchOptions
    /// Where the ssh options came from, for Settings to show.
    private let configPath: String

    init() {
        let options = LaunchOptions()
        self.options = options
        // Before any window, so nothing connects without the settings the
        // file names.
        self.configPath = (try? Core.configure(configPath: options.configPath))?.path
            ?? options.configPath
        // Sparkle wants its controller made before any window exists, which
        // is here; `start()` holds the first look until launching is done,
        // because there is no app delegate to put it in.
        Updates.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dbPath: options.db, configPath: options.configPath)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            ShellhandCommands(storePath: options.db, configPath: configPath)
        }
    }
}

/// What the run was asked for, read from the arguments LaunchServices passed.
struct LaunchOptions {
    var db: String
    /// The ssh options to read; empty means their usual place.
    var configPath = ""

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        // The test bundle is hosted by this app, so running the suite launches
        // it — with no `--db`, that opened and migrated the real host list.
        // Nothing was lost, but a test run is not allowed anywhere near it.
        var db = LaunchOptions.underTest
            ? LaunchOptions.scratchStore : Store.defaultPath
        var config = ""
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "--db" where i + 1 < arguments.count:
                db = arguments[i + 1]
                i += 1
            case "--config" where i + 1 < arguments.count:
                config = arguments[i + 1]
                i += 1
            default:
                break
            }
            i += 1
        }
        self.db = db
        self.configPath = config
    }

    /// Whether the suite is running. XCTest puts this in the environment of
    /// whatever hosts it, and an app-hosted bundle means that is this app.
    static var underTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
    }

    /// A store of this run's own, thrown away with the temporary directory.
    static var scratchStore: String {
        NSTemporaryDirectory() + "shellhand-under-test/shellhand.sqlite"
    }
}
