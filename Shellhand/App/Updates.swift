import AppKit
import Sparkle

/// Updates for a build that came from GitHub rather than the App Store.
///
/// The app is GPL, so anyone can build it; what a release offers is a
/// notarized, signed build that keeps itself current, and this is the half of
/// that which ships inside the app. `scripts/release.sh` is the other half.
///
/// **The feed is served from the repository, not from a domain.** No
/// `shellhand.app` host exists yet, and the URL compiled into a build is
/// permanent once that build is out — an app in the wild asks the address it
/// was born with, for ever. GitHub serves `appcast.xml` from `main` and the
/// DMGs from Releases, so nothing here waits on a registrar, and nothing has
/// to be migrated if a domain arrives later: a new build can be born with a
/// new address while the old ones keep asking GitHub.
///
/// **Nothing runs in a Debug build.** Sparkle would happily offer a Debug
/// build the latest release DMG and install it over itself, which is a
/// confusing way to lose your working copy. `start()` and `check()` both
/// return early, and `canCheck` is false, so the menu item greys out rather
/// than looking live and doing nothing.
@MainActor
@Observable
final class Updates {
    static let shared = Updates()

    /// Whether Sparkle looks on its own schedule. Stored rather than read
    /// through on every access so the Settings toggle redraws when it is
    /// flipped; the write goes straight on to Sparkle, which owns the
    /// preference.
    var automatic: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automatic }
    }

    /// Whether Check for Updates… can do anything right now.
    ///
    /// Deliberately **not** observable, which is where this differs from
    /// Sparkle's own sample code: that bridges `canCheckForUpdates` into a
    /// `@Published` through Combine, and the bridge costs an
    /// `ObservableObject` in a codebase that is otherwise `@Observable`, plus
    /// a KVO callback that has to hop back to the main actor to be legal under
    /// Swift 6. All it buys is the item greying out for the second or two a
    /// check is already in flight — and asking twice is harmless, because
    /// Sparkle brings the check already running to the front. The menu reads
    /// this each time it is built, which is often enough.
    var canCheck: Bool {
        #if DEBUG
            false
        #else
            controller.updater.canCheckForUpdates
        #endif
    }

    private let controller: SPUStandardUpdaterController

    private init() {
        // `startingUpdater: false`: when it starts is decided below, not by
        // the initialiser.
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        automatic = controller.updater.automaticallyChecksForUpdates
    }

    /// Begins the automatic schedule, a turn of the run loop from now.
    ///
    /// Called from `ShellhandApp.init()`, which runs *during* launching —
    /// early enough that the controller exists before any window, which is
    /// what Sparkle asks for, but too early to start checking: that belongs
    /// after the app has finished launching, where an `AppDelegate` would put
    /// it. There is no delegate here and adding one to reach a single
    /// notification is not worth it, so the start is deferred a turn, the
    /// same hop the inspector needs for its own reasons.
    func start() {
        #if DEBUG
            return
        #else
            DispatchQueue.main.async { [controller] in
                controller.startUpdater()
            }
        #endif
    }

    /// Looks now, because someone asked. Sparkle puts up its own window.
    func check() {
        #if DEBUG
            return
        #else
            controller.checkForUpdates(nil)
        #endif
    }
}
