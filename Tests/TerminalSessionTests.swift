// `Foundation` is imported for the log-file write, which brings
// `Foundation.Host` with it -- hence `Shellhand.Host` spelled out below.
// `AppKit`, for the terminal's font, brings it too.
import AppKit
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

    // MARK: the Option key

    /// Both ways round, because SwiftTerm's own default is Meta: a session
    /// that never handed its setting to the terminal would pass the second
    /// and fail only the first — and that terminal is the bug, Option turning
    /// the `@` or `|` a keyboard puts on it into Esc and a letter.
    @Test("a session's terminal takes the Option setting it is given")
    func takesTheOptionSetting() {
        #expect(!TerminalSession(title: "web", host: nil, optionAsMeta: false).view.optionAsMetaKey)
        #expect(TerminalSession(title: "web", host: nil, optionAsMeta: true).view.optionAsMetaKey)
    }

    /// Started the other way round from what Settings holds, then told the
    /// defaults changed: it has to come round to what Settings says. The
    /// notification is posted rather than the key written, because the test
    /// host shares the app's bundle id and its defaults are the user's own —
    /// and posting it holds whichever way the user's switch happens to be.
    @Test("an open session follows the Option switch in Settings")
    func followsTheOptionSwitch() async {
        let stored = TerminalSession.prefersOptionAsMeta
        let session = TerminalSession(title: "web", host: nil, optionAsMeta: !stored)
        #expect(session.view.optionAsMetaKey == !stored)

        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
        await settle { session.view.optionAsMetaKey == stored }
        #expect(session.view.optionAsMetaKey == stored)
    }

    // MARK: the font

    @Test("a session's terminal is drawn in the font it is given")
    func takesTheFont() {
        #expect(TerminalSession(title: "web", host: nil, fontFamily: "Menlo").view.font.familyName
            == "Menlo")
        let system = NSFont.monospacedSystemFont(
            ofSize: TerminalSession.preferredFontSize, weight: .regular)
        #expect(TerminalSession(title: "web", host: nil, fontFamily: "").view.font.fontName
            == system.fontName)
    }

    /// Started in a family other than the one stored and made bigger, then
    /// told the defaults changed: it takes Settings' family and keeps its own
    /// size, which ⌘+ put somewhere other than Settings'. Posted rather than
    /// written, as the Option test is, so it holds whichever font the user
    /// has chosen.
    @Test("an open session follows the font chosen in Settings, keeping its size")
    func followsTheFont() async {
        let stored = TerminalFont.preferred
        let session = TerminalSession(
            title: "web", host: nil, fontFamily: stored == "Menlo" ? "" : "Menlo")
        session.changeFontSize(by: 3)
        let size = session.view.font.pointSize
        let wanted = TerminalFont.font(named: stored, size: size).fontName

        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
        await settle { session.view.font.fontName == wanted }
        #expect(session.view.font.fontName == wanted)
        #expect(session.view.font.pointSize == size)
    }

    // MARK: clearing the scrollback

    /// Numbered so that no line's text is the start of another's.
    private static func lines(_ prefix: String, _ range: ClosedRange<Int>) -> String {
        range.map { "\(prefix) \(String(format: "%03d", $0))\r\n" }.joined()
    }

    /// A hundred lines into a screen a few dozen high leaves the first ones
    /// above it. Clearing drops those and keeps what is on the screen — and
    /// lines that arrive afterwards are kept again, which is the half that
    /// would fail if the history were left shrunk to nothing.
    @Test("clearing the scrollback drops what is above the screen, and only that")
    func clearsTheScrollback() {
        let session = session()
        session.view.feed(text: Self.lines("old", 1...100))
        #expect(session.screen.contains("old 001"), "the first line never reached the scrollback")

        session.clearScrollback()
        #expect(!session.screen.contains("old 001"))
        #expect(session.screen.contains("old 100"), "the screen itself went too")

        session.view.feed(text: Self.lines("new", 1...100))
        #expect(session.screen.contains("new 001"), "the scrollback no longer keeps anything")
    }

    /// Actual Size used to put back SF Mono outright, which was harmless
    /// while there was nothing else and would undo the choice now.
    @Test("Actual Size goes back to Settings' size in the session's own font")
    func actualSizeKeepsTheFont() {
        let session = TerminalSession(title: "web", host: nil, fontFamily: "Menlo")
        session.changeFontSize(by: 4)
        session.resetFontSize()
        #expect(session.view.font.familyName == "Menlo")
        #expect(session.view.font.pointSize == TerminalSession.preferredFontSize)
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

    /// The next hop of a jump chain asking: another host and another key, so
    /// it is a new question rather than `prompt` again.
    private static let nextHop =
        "\r\nThe authenticity of host 'db' can't be established.\r\n"
        + "ED25519 key fingerprint is SHA256:ijklmnop.\r\n"
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

    /// The race held open. No process sits behind a fed view, so an answer is
    /// typed into nothing and nothing ever echoes it: every watchdog look after
    /// the answer is the look *before* the echo, which a real session passes
    /// through in a millisecond and this one never leaves. Five looks — a whole
    /// second — and the answered question must not have been asked again.
    @Test("an answered question is not asked again while its echo is on the way")
    func answeredStaysAnswered() async {
        let session = session()
        defer { session.close() }
        session.view.feed(text: Self.prompt)
        session.watch()
        let asked = await waitUntil {
            if case .askingHostKey = session.state { return true }
            return false
        }
        guard asked else {
            Issue.record("the question was never asked to begin with")
            return
        }

        session.answerHostKey(accept: true)
        let looked = session.ticks
        _ = await waitUntil { session.ticks >= looked + 5 }
        #expect(session.ticks >= looked + 5, "the watchdog stopped looking")
        #expect(session.state == .connecting, "the answered question came back: \(session.state)")
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

    /// The same question against a terminal narrow enough to wrap it, which
    /// is what a person gets from ⌘+ in a small window. The pure tests pin
    /// the rule; this pins that a real buffer really does split a line this
    /// way, because the rule is only worth anything if it does.
    @Test("a host key question wrapped by a narrow terminal is still seen")
    func watchdogAsksWhenWrapped() async {
        let session = session()
        session.view.resize(cols: 40, rows: 24)
        session.view.feed(
            text: "The authenticity of host 'web.example.com (198.51.100.11)'"
                + " can't be established.\r\n"
                + "ED25519 key fingerprint is"
                + " SHA256:uN8Fh2kLqW3xYvZ9pR5tS7mB1cD4eG6jH0iJ2kL3nOp.\r\n"
                + "Are you sure you want to continue connecting"
                + " (yes/no/[fingerprint])? ")
        session.watch()

        let asked = await waitUntil {
            if case .askingHostKey = session.state { return true }
            return false
        }
        #expect(asked, "screen was: \(session.screen.debugDescription)")
    }

    // MARK: the watchdog, once a session settles

    /// What the 10,000-line scrollback rests on: the screen is the whole
    /// history, so once a session has settled the watchdog goes on ticking —
    /// ssh's log is still read — but stops reading it.
    @Test("a settled session's screen is not read")
    func settledIsNotRead() async {
        let session = session()
        defer { session.close() }
        session.view.feed(text: "deploy@web:~$ \r\n")
        session.watch()
        #expect(await waitUntil { session.state == .connected })
        #expect(session.looks > 0, "the watchdog never read the screen at all")

        session.connectedAt = Date(timeIntervalSinceNow: -SessionProgress.settling - 1)
        let looked = session.looks
        let ticked = session.ticks
        #expect(await waitUntil { session.ticks >= ticked + 3 }, "the watchdog stopped ticking")
        #expect(session.looks == looked,
                "the screen was read \(session.looks - looked) times after settling")
    }

    /// The control for the one above: a rule that never read a connected
    /// session's screen would pass that and lose a jump chain's next hop.
    @Test("a session just through is still read")
    func justThroughIsRead() async {
        let session = session()
        defer { session.close() }
        session.view.feed(text: "deploy@web:~$ \r\n")
        session.watch()
        #expect(await waitUntil { session.state == .connected })
        let looked = session.looks
        #expect(await waitUntil { session.looks >= looked + 3 },
                "a session just through stopped being read")
    }

    /// A jump chain asks once per hop, and the first answer on screen reads
    /// as being through — so the next hop asks after `.connected`. The echo
    /// is fed by hand: a fed view has no pty to echo the answer.
    @Test("a jump chain's next hop is still asked, after the first is answered")
    func nextHopIsAsked() async {
        let session = session()
        defer { session.close() }
        session.view.feed(text: Self.prompt)
        session.watch()
        let first = await waitUntil {
            if case .askingHostKey = session.state { return true }
            return false
        }
        guard first else {
            Issue.record("the first hop's question was never asked")
            return
        }
        session.answerHostKey(accept: true)
        session.view.feed(text: " yes\r\n")
        #expect(await waitUntil { session.state == .connected })

        session.view.feed(text: Self.nextHop)
        let next = await waitUntil {
            if case let .askingHostKey(question) = session.state {
                return question.contains("SHA256:ijklmnop")
            }
            return false
        }
        #expect(next, "the next hop was not asked: \(session.state)")
    }

    /// What the rule gives up, pinned so that it is a decision rather than an
    /// accident: a question turning up after the session settled is something
    /// run inside it asking — an `ssh` typed there — and the terminal is where
    /// it gets answered, as in any terminal.
    @Test("a question long after coming through is left to the terminal")
    func lateQuestionIsLeft() async {
        let session = session()
        defer { session.close() }
        session.view.feed(text: "deploy@web:~$ ssh db\r\n")
        session.watch()
        #expect(await waitUntil { session.state == .connected })
        session.connectedAt = Date(timeIntervalSinceNow: -SessionProgress.settling - 1)

        session.view.feed(text: Self.nextHop)
        let ticked = session.ticks
        #expect(await waitUntil { session.ticks >= ticked + 3 }, "the watchdog stopped ticking")
        #expect(session.state == .connected, "this app asked: \(session.state)")
    }

    // MARK: the history

    /// SwiftTerm's own default kept 500 lines, so a thousand in, the first
    /// was gone.
    @Test("a session keeps a long history")
    func keepsALongHistory() {
        let session = session()
        session.view.feed(text: Self.lines("line", 1...1000))
        #expect(session.screen.contains("line 001"), "the first of a thousand lines was not kept")
    }

    // MARK: a real shell on a real pty

    /// **The one test here that spawns a process**, and it is worth it: it
    /// asks the shell itself where it started, which is the only answer that
    /// cannot be wrong. A forked shell inherits the app's working directory
    /// and an app launched by LaunchServices has `/`, so a local shell used to
    /// open at the root of the disk.
    ///
    /// The oracle is the filesystem rather than the screen: reading the
    /// terminal back would depend on what SwiftTerm's own accessibility
    /// exposes and on the shell's prompt, neither of which is this test's
    /// business. A file either says `$HOME` or it does not.
    @Test("a local shell starts in the home directory, not at the root")
    func localShellStartsAtHome() async throws {
        let out = TestScratch.directory("shell") + "/pwd"
        let session = session()
        session.startLocalShell()
        defer { session.close() }

        // The shell has to be up before it can be typed at, and a login shell
        // reads the user's own rc files first, which is not instant.
        #expect(await waitUntil { session.state == .connected })
        session.send("pwd > \(out)\n")

        let landed = await waitUntil { FileManager.default.fileExists(atPath: out) }
        #expect(landed, "the shell never wrote to \(out)")
        guard landed else { return }

        let said = try String(contentsOfFile: out, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(said == home, "the shell started in \(said), not \(home)")
    }

    /// `Forking`'s lock is only worth anything if every terminal goes through
    /// it, and a start that skipped it would look exactly like one that did —
    /// the shell comes up either way. So these hold the lock from another
    /// thread and check the start **waited** for it. Both doors are tried,
    /// because they are two separate calls to `startProcess`.
    @Test("a local shell does not start while a pipe is being made")
    func localShellWaitsForTheLock() {
        let session = session()
        defer { session.close() }
        let waited = Self.secondsTaken(whileTheLockIsHeld: { session.startLocalShell() })
        #expect(waited >= 0.3, "the shell started \(waited)s in, with the lock still held")
    }

    /// To `127.0.0.1` port 1, which refuses at once and reaches nothing.
    @Test("an ssh session does not start while a pipe is being made")
    func sshWaitsForTheLock() {
        let session = session()
        defer { session.close() }
        let waited = Self.secondsTaken(whileTheLockIsHeld: {
            session.start(argv: ["-o", "BatchMode=yes", "-p", "1", "127.0.0.1"])
        })
        #expect(waited >= 0.3, "ssh started \(waited)s in, with the lock still held")
    }

    /// Holds the lock on another thread for 0.4s, and times `start` from the
    /// moment the lock is certainly held.
    private static func secondsTaken(whileTheLockIsHeld start: () -> Void) -> Double {
        let held = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            Forking.exclusively {
                held.signal()
                usleep(400_000)
            }
        }
        held.wait()
        let began = Date()
        start()
        return Date().timeIntervalSince(began)
    }
}
