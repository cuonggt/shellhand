import SwiftTerm
import Testing
@testable import Shellhand

/// What a session does when the far end tells it something.
///
/// The pty itself is SwiftTerm's, and running one means spawning a real
/// process — but the delegate callbacks it drives are ordinary methods, so
/// what the session *makes of* an exit code or a title can be asked without
/// any of that. What is left needing a pty after this is the watchdog and the
/// reading of the screen.
@MainActor
@Suite("Terminal session")
struct TerminalSessionTests {
    private func session(host: Host? = nil) -> TerminalSession {
        TerminalSession(title: "web", host: host)
    }

    /// The delegate hops to the main actor to do its work, so give the queued
    /// task a turn rather than sleeping on it.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield() }
    }

    // MARK: the title the shell sends

    @Test("a title from the far end becomes the session's")
    func takesTheTitle() async {
        let session = session()
        session.setTerminalTitle(source: session.view, title: "root@web:~/srv")
        await settle { session.title == "root@web:~/srv" }
        #expect(session.title == "root@web:~/srv")
    }

    /// A shell that clears its title would otherwise leave the tab blank, and
    /// a tab with no name is worse than a stale one.
    @Test("an empty title is ignored rather than adopted")
    func keepsTheOldTitle() async {
        let session = session()
        session.setTerminalTitle(source: session.view, title: "root@web:~/srv")
        await settle { session.title == "root@web:~/srv" }

        session.setTerminalTitle(source: session.view, title: "")
        await settle { false }
        #expect(session.title == "root@web:~/srv")
    }

    // MARK: how it ends

    @Test("the far end's exit status is kept, not swallowed")
    func keepsTheExitCode() async {
        let session = session()
        session.processTerminated(source: session.view, exitCode: 255)
        await settle {
            if case .ended = session.state { return true }
            return false
        }
        guard case let .ended(code, _) = session.state else {
            Issue.record("the session did not end")
            return
        }
        #expect(code == 255)
    }

    /// Killed rather than exited: there is no status, and saying so is not
    /// the same as saying zero.
    @Test("a session that ended without a status says so")
    func noExitCode() async {
        let session = session()
        session.processTerminated(source: session.view, exitCode: nil)
        await settle {
            if case .ended = session.state { return true }
            return false
        }
        guard case let .ended(code, _) = session.state else {
            Issue.record("the session did not end")
            return
        }
        #expect(code == nil)
    }

    @Test("a session starts out connecting, and nothing else")
    func startsConnecting() {
        #expect(session().state == .connecting)
    }

    // MARK: adopting a host that changed

    /// Repainting is the only thing adopting does. A session keeps the host
    /// it was opened with for its title and its argv, so the match on id is
    /// what stops one session being redrawn as another.
    @Test("a session takes up the same host, edited")
    func adoptsTheSameHost() {
        let before = Host(id: "h1", name: "web", addr: "198.51.100.1")
        let session = session(host: before)

        var after = before
        after.addr = "198.51.100.9"
        session.adopt(after)
        #expect(session.host?.addr == "198.51.100.9")
    }

    @Test("a session does not take up a different host")
    func ignoresAnotherHost() {
        let mine = Host(id: "h1", name: "web", addr: "198.51.100.1")
        let session = session(host: mine)

        session.adopt(Host(id: "h2", name: "api", addr: "198.51.100.2"))
        #expect(session.host?.id == "h1")
        #expect(session.host?.name == "web")
    }

    @Test("a local session has no host to take up")
    func localTakesNothing() {
        let session = session(host: nil)
        session.adopt(Host(id: "h1", name: "web", addr: "198.51.100.1"))
        #expect(session.host == nil)
    }
}
