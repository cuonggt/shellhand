import SwiftUI

/// Shellhand's Mac app: the host list, in a window, with ssh on a pty for
/// every tab.
///
/// `--db <path>` points at a store other than the real one, and
/// `--config <path>` at ssh options somewhere other than their usual place.
@main
struct ShellhandApp: App {
    /// For ⌘Q and nothing else: whether to quit is the one question SwiftUI
    /// has no way to ask the app.
    @NSApplicationDelegateAdaptor(ShellhandAppDelegate.self) private var appDelegate
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
        // is here; `start()` holds the first look until launching is done.
        // That hop was written when there was no app delegate to put it in;
        // there is one now, for ⌘Q, and the hop is left because it works.
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

/// Asks before quitting takes live sessions down with it.
///
/// Every window's sessions, not only the front one's, which is why `Sessions`
/// keeps a list of itself: quitting ends all of them, and this delegate has
/// no way into a window's state otherwise.
final class ShellhandAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let question = Self.question() else { return .terminateNow }
        return NSAlert(asking: question).runModal() == .alertFirstButtonReturn
            ? .terminateNow : .terminateCancel
    }

    /// What quitting would ask now, or nil to quit straight away.
    static func question(confirming: Bool = Closing.confirmsNow) -> Closing.Question? {
        Closing.question(
            .quitting, dropping: Sessions.inEveryWindow.map(Closing.Open.init),
            confirming: confirming)
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
        // The same for the config, and for a reason of the same size: its ssh
        // options become every connection's, so a run reading the real one
        // would take whatever the user wrote there — a `ProxyCommand` included
        // — into every connection the suite makes to its own `sshd`.
        var config = LaunchOptions.underTest ? LaunchOptions.scratchConfig : ""
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

    /// Whether the suite is running. The decision lives in `TestRun`, in
    /// `Core`, because `Core` redirects two files on the strength of it and
    /// cannot reach up into `App/` — and two copies of it would drift.
    static var underTest: Bool { TestRun.active }

    /// A store of this run's own, thrown away with the temporary directory.
    static var scratchStore: String { TestRun.store }

    /// A config of this run's own, beside the store. Nothing writes one, and
    /// a missing config reads as an empty one, so a run's ssh options are its
    /// own: none.
    static var scratchConfig: String { TestRun.config }
}
