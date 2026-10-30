import AppKit
import Testing
@testable import Shellhand

/// What closing a tab, the window or the app asks before it drops sessions.
///
/// Deliberately no `Host` here: `AppKit` brings `Foundation.Host` with it.
@MainActor
@Suite("Closing", .timeLimit(.minutes(1)))
struct ClosingTests {
    private let web = Closing.Open(host: "web", state: .connected)
    private let db = Closing.Open(host: "db", state: .connected)
    private let shell = Closing.Open(host: nil, state: .connected)
    private let ended = Closing.Open(host: "api", state: .ended(code: 0, diagnostic: ""))
    private let connecting = Closing.Open(host: "edge", state: .connecting)

    // MARK: whether to ask at all

    /// The switch shows on before anybody has touched it, so asking has to
    /// be on too — and `UserDefaults.bool(forKey:)` would have said off.
    @Test("asking is on until somebody turns it off")
    func onUntilTurnedOff() {
        #expect(Closing.confirms(nil))
        #expect(Closing.confirms(true))
        #expect(!Closing.confirms(false))
    }

    @Test("only a session somebody is in counts as live")
    func whatIsLive() {
        #expect(Closing.isLive(.connected))
        #expect(!Closing.isLive(.connecting))
        #expect(!Closing.isLive(.askingHostKey("Are you sure you want to continue connecting?")))
        #expect(!Closing.isLive(.ended(code: 0, diagnostic: "")))
        #expect(!Closing.isLive(.ended(code: nil, diagnostic: "")))
    }

    @Test("with the switch off, nothing asks")
    func switchedOff() {
        for act in [Closing.Act.closingTab, .reconnecting, .closingOthers, .closingWindow, .quitting] {
            #expect(Closing.question(act, dropping: [web, shell], confirming: false) == nil)
        }
    }

    @Test("nothing asks when nothing would be lost")
    func nothingLive() {
        for act in [Closing.Act.closingTab, .reconnecting, .closingOthers, .closingWindow, .quitting] {
            #expect(Closing.question(act, dropping: [], confirming: true) == nil)
            #expect(Closing.question(act, dropping: [ended, connecting], confirming: true) == nil)
        }
    }

    // MARK: what it asks

    @Test("a tab asks by its host's name, or as the local shell")
    func tab() {
        let onWeb = Closing.question(.closingTab, dropping: [web], confirming: true)
        #expect(onWeb?.title == "Close the session on web?")
        #expect(onWeb?.confirm == "Close")
        #expect(Closing.question(.closingTab, dropping: [shell], confirming: true)?.title
            == "Close the local shell?")
    }

    @Test("reconnecting asks by the host's name, with a button that says so")
    func reconnect() {
        let asked = Closing.question(.reconnecting, dropping: [web], confirming: true)
        #expect(asked?.title == "Reconnect to web?")
        #expect(asked?.confirm == "Reconnect")
    }

    /// A count that took in the ended and the connecting would ask about
    /// sessions that lose nothing by closing — and name the wrong one when
    /// only one of them is live.
    @Test("closing the window counts only the live sessions")
    func window() {
        let several = Closing.question(
            .closingWindow, dropping: [web, ended, connecting, db], confirming: true)
        #expect(several?.title == "Close the window and end 2 sessions?")
        #expect(several?.message == "They are all still running.")
        #expect(Closing.question(.closingWindow, dropping: [ended, web], confirming: true)?.title
            == "Close the window and end the session on web?")
    }

    /// The tabs counted are every one going; the sessions named are only the
    /// live ones among them, since closing an ended tab loses nothing.
    @Test("Close Other Tabs counts the tabs going and names what is live among them")
    func others() {
        #expect(Closing.question(.closingOthers, dropping: [web], confirming: true)?.title
            == "Close the other tab and end the session on web?")
        #expect(Closing.question(.closingOthers, dropping: [web, ended], confirming: true)?.title
            == "Close the other tabs and end the session on web?")
        #expect(Closing.question(.closingOthers, dropping: [web, db, ended], confirming: true)?.title
            == "Close the other tabs and end 2 sessions?")
        #expect(Closing.question(.closingOthers, dropping: [ended, connecting], confirming: true) == nil)
    }

    @Test("quitting asks the same way, with its own button")
    func quit() {
        let several = Closing.question(.quitting, dropping: [web, shell, ended], confirming: true)
        #expect(several?.title == "Quit and end 2 sessions?")
        #expect(several?.confirm == "Quit")
        #expect(Closing.question(.quitting, dropping: [shell], confirming: true)?.title
            == "Quit and end the local shell?")
    }

    // MARK: what puts the question

    /// **The one real process in this file**, because a session is only live
    /// once somebody is in it, and a local shell is in from the start. Asked
    /// with `confirming: true` rather than whatever Settings holds, so the
    /// check means the same on a machine whose switch is off.
    @Test("quitting sees a session in any window, and stops seeing it once closed")
    func quittingSeesEveryWindow() {
        let window = Sessions()
        let shell = window.openLocalShell()

        #expect(Sessions.inEveryWindow.contains { $0 === shell })
        #expect(ShellhandAppDelegate.question(confirming: true) != nil)

        window.close(shell)
        #expect(!Sessions.inEveryWindow.contains { $0 === shell })
    }

    /// A guard on a window of its own, never shown, asking about the
    /// sessions it was handed rather than anybody else's.
    @Test("a window's guard asks about its own sessions")
    func guardAsksAboutItsOwn() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let mine = Sessions()
        ClosingGuard.stand(in: window, for: mine)
        let guarding = window.delegate as? ClosingGuard
        #expect(guarding != nil, "nothing stood in front of the window's delegate")
        #expect(guarding?.question(confirming: true) == nil)

        let shell = mine.openLocalShell()
        defer { mine.close(shell) }
        #expect(guarding?.question(confirming: true)?.title
            == "Close the window and end the local shell?")
    }

    /// The host window is SwiftUI's, and so is its delegate — the window
    /// controller, which answers `windowShouldClose` itself. A guard that
    /// replaced it rather than standing in front would cut SwiftUI off from
    /// its own window, so the chain is checked as well as the guard. The test
    /// host is the app, so the window is really there to look at.
    @Test("the host window has a guard, with SwiftUI's delegate still behind it")
    func hostWindowIsGuarded() async {
        var guarding: ClosingGuard?
        let deadline = ContinuousClock.now + .seconds(10)
        while guarding == nil, ContinuousClock.now < deadline {
            guarding = NSApp.windows
                .first { $0.identifier == HostsWindow.identifier }?.delegate as? ClosingGuard
            if guarding == nil { try? await Task.sleep(for: .milliseconds(50)) }
        }
        guard let guarding else {
            Issue.record("the host window's delegate never became a ClosingGuard")
            return
        }
        let window = NSApp.windows.first { $0.identifier == HostsWindow.identifier }
        #expect(guarding.inFrontOf != nil)
        #expect(guarding.inFrontOf === window?.windowController)
        #expect(guarding.responds(to: #selector(NSWindowDelegate.windowWillClose(_:))))
    }

    // MARK: transfers

    /// Closing the SFTP window stops every transfer still to go, and used to
    /// without a word while Settings said closing would ask.
    @Test("closing SFTP asks while files are still moving")
    func closingFilesAsks() {
        let two = Closing.question(.closingFiles, dropping: [], stopping: 2, confirming: true)
        #expect(two?.title == "Close SFTP and stop 2 transfers?")
        #expect(two?.message == "They have not finished.")
        #expect(two?.confirm == "Close")
        let one = Closing.question(.closingFiles, dropping: [], stopping: 1, confirming: true)
        #expect(one?.title == "Close SFTP and stop a transfer?")
        #expect(one?.message == "It has not finished.")
    }

    @Test("closing SFTP goes straight ahead with nothing moving, or the switch off")
    func closingFilesQuietly() {
        #expect(Closing.question(.closingFiles, dropping: [], stopping: 0, confirming: true) == nil)
        #expect(Closing.question(.closingFiles, dropping: [], stopping: 3, confirming: false) == nil)
        // Sessions are the host window's business, not this window's.
        #expect(Closing.question(.closingFiles, dropping: [web], stopping: 0, confirming: true) == nil)
    }

    @Test("quitting counts transfers as well as sessions")
    func quittingCountsTransfers() {
        let onlyFiles = Closing.question(.quitting, dropping: [], stopping: 1, confirming: true)
        #expect(onlyFiles?.title == "Quit and stop a transfer?")
        let both = Closing.question(.quitting, dropping: [web], stopping: 2, confirming: true)
        #expect(both?.title == "Quit, ending the session on web and stopping 2 transfers?")
        let onlySessions = Closing.question(.quitting, dropping: [web], stopping: 0, confirming: true)
        #expect(onlySessions?.title == "Quit and end the session on web?")
        #expect(Closing.question(.quitting, dropping: [ended], stopping: 0, confirming: true) == nil)
    }
}
