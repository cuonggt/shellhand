// `Foundation` is imported for the log-file write, which brings
// `Foundation.Host` with it -- hence `Shellhand.Host` spelled out below.
import Foundation
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
@Suite("Terminal session", .timeLimit(.minutes(1)))
struct TerminalSessionTests {
    private func session(host: Shellhand.Host? = nil) -> TerminalSession {
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
        let before = Shellhand.Host(id: "h1", name: "web", addr: "198.51.100.1")
        let session = session(host: before)

        var after = before
        after.addr = "198.51.100.9"
        session.adopt(after)
        #expect(session.host?.addr == "198.51.100.9")
    }

    @Test("a session does not take up a different host")
    func ignoresAnotherHost() {
        let mine = Shellhand.Host(id: "h1", name: "web", addr: "198.51.100.1")
        let session = session(host: mine)

        session.adopt(Shellhand.Host(id: "h2", name: "api", addr: "198.51.100.2"))
        #expect(session.host?.id == "h1")
        #expect(session.host?.name == "web")
    }

    @Test("a local session has no host to take up")
    func localTakesNothing() {
        let session = session(host: nil)
        session.adopt(Shellhand.Host(id: "h1", name: "web", addr: "198.51.100.1"))
        #expect(session.host == nil)
    }

    /// The watchdog sleeps 200ms between looks, so yielding is not enough
    /// here: this one waits on the clock, with a ceiling so a rule that never
    /// fires fails rather than hangs.
    private func waitUntil(_ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if done() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return done()
    }

    /// What ssh writes, kept well short of the terminal's width on purpose:
    /// how a *wrapped* question reads is a separate question from whether an
    /// unwrapped one is seen at all.
    private static let prompt =
        "The authenticity of host 'web' can't be established.\r\n"
        + "ED25519 key fingerprint is SHA256:abcdefgh.\r\n"
        + "Are you sure you want to continue connecting (yes/no)?"

    // MARK: reading the screen

    /// **The buffer is not empty, and that was a bug.** A terminal that has
    /// heard nothing hands back its own blank rows, so the watchdog's old
    /// `!screen.isEmpty` test read them as output and took every session to
    /// `.connected` on its first look. Both halves are pinned here, because
    /// the rule in `SessionProgress` is only correct while this stays true.
    @Test("a session that has heard nothing has a blank screen, not an empty one")
    func freshScreenIsBlank() {
        let screen = session().screen
        #expect(!screen.isEmpty)
        #expect(screen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("the screen is what the terminal was fed")
    func readsTheScreen() {
        let session = session()
        session.view.feed(text: "deploy@web:~$ ls\r\nDocuments  notes.txt\r\n")
        #expect(session.screen.contains("deploy@web:~$ ls"))
        #expect(session.screen.contains("Documents  notes.txt"))
    }

    // MARK: the watchdog, against a screen fed by hand

    @Test("the watchdog sees output and takes the session through")
    func watchdogConnects() async {
        let session = session()
        session.view.feed(text: "deploy@web:~$ \r\n")
        session.watch()

        #expect(await waitUntil { session.state == .connected })
        #expect(session.ticks > 0)
    }

    /// The watchdog ran and the state did not move, which is the pair of facts
    /// `ticks` exists to tell apart.
    @Test("the watchdog leaves a silent session connecting")
    func watchdogLeavesSilenceAlone() async {
        let session = session()
        session.watch()

        #expect(await waitUntil { session.ticks > 0 })
        #expect(session.state == .connecting)
    }

    @Test("the watchdog raises a host key question off the real screen")
    func watchdogAsks() async {
        let session = session()
        session.view.feed(text: Self.prompt)
        session.watch()

        let asked = await waitUntil {
            if case .askingHostKey = session.state { return true }
            return false
        }
        #expect(asked)
        guard case let .askingHostKey(question) = session.state else { return }
        #expect(question.contains("SHA256:abcdefgh"))
    }

    @Test("the watchdog picks up what ssh wrote to its own log")
    func watchdogReadsTheLog() async throws {
        let session = session()
        try "debug1: Connecting to web port 22\n".write(
            toFile: session.logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: session.logPath) }
        session.watch()

        #expect(await waitUntil { session.diagnostics.contains("Connecting to web") })
    }
}
