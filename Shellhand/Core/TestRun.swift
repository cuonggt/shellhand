import Foundation

/// Whether this process is a test run, and where its files go instead.
///
/// The test bundle is **hosted by the app**, so running the suite launches it
/// — and with nothing redirected that meant opening and migrating the real
/// host list. Three files now have to be sent somewhere else for a run, each
/// for a reason of its own size:
///
/// - the **store**, or a run edits the user's own list;
/// - this app's own **config**, whose ssh options become every connection's,
///   so a `ProxyCommand` written there would reach every connection the suite
///   makes to its own `sshd`;
/// - **ssh's config**, whose names now reach the resolver, so a `Host web`
///   somebody happens to have written would quietly change what a test about
///   a host called `web` sees.
///
/// It lives here rather than beside `LaunchOptions` because `Core` reads two
/// of these and cannot reach up into `App/` — and because one copy of the
/// decision is the point. `LaunchOptions` reads it from here.
///
/// Nothing writes the scratch config or the scratch ssh config, and both read
/// as empty when absent, so a run's ssh options and known names are its own:
/// none.
nonisolated enum TestRun {
    /// XCTest puts this in the environment of whatever hosts it, and an
    /// app-hosted bundle means that is this app.
    static var active: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
    }

    /// One directory per machine rather than per run, reused — which is why
    /// it is not litter when something goes looking for where the disk went.
    private static var directory: String {
        NSTemporaryDirectory() + "shellhand-under-test/"
    }

    static var store: String { directory + "shellhand.sqlite" }
    static var config: String { directory + "config.yaml" }
    static var sshConfig: String { directory + "ssh_config" }
}
