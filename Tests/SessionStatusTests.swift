import Testing
@testable import Shellhand

/// What a session's tab, pane and subtitle say it is doing, and what ssh's
/// own words at the end mean. The lines below are ssh's as it writes them —
/// the refusal and the unresolvable name taken from this Mac's own
/// OpenSSH 10.3, reaching nothing.
@Suite("Session status")
nonisolated struct SessionStatusTests {
    private static let refused = "ssh: connect to host 127.0.0.1 port 1: Connection refused"
    private static let unresolved =
        "ssh: Could not resolve hostname nowhere.invalid: nodename nor servname provided, or not known"
    private static let declined = "Host key verification failed."
    private static let dropped = "client_loop: send disconnect: Broken pipe"
    private static let closed = "Connection to 192.0.2.21 closed by remote host."

    private func status(
        _ code: Int32?, _ said: String = "", stopped: Bool = false, through: Bool = false
    ) -> SessionStatus {
        SessionStatus.of(.ended(code: code, diagnostic: said), stopped: stopped, gotThrough: through)
    }

    // MARK: what a state is

    @Test("connecting, a question and through are what they say")
    func underWay() {
        #expect(SessionStatus.of(.connecting, stopped: false, gotThrough: false) == .connecting)
        #expect(SessionStatus.of(.askingHostKey("?"), stopped: false, gotThrough: false) == .needsAnswer)
        #expect(SessionStatus.of(.connected, stopped: false, gotThrough: true) == .connected)
    }

    @Test("ssh's own failure before anything ran is a connection that never opened")
    func couldNotConnect() {
        #expect(status(255, Self.refused) == .couldNotConnect)
        #expect(status(255, Self.unresolved) == .couldNotConnect)
        #expect(status(255, "") == .couldNotConnect)
    }

    /// An answered question or a password prompt on screen reads as through,
    /// so through is no proof of having logged in: a key turned down after
    /// the question was answered is still a connection that never opened.
    @Test("a failure ssh says came before logging in is one, through or not")
    func beforeLoginWins() {
        #expect(status(255, Self.declined, through: true) == .couldNotConnect)
        #expect(status(255, "deploy@192.0.2.21: Permission denied (publickey).", through: true)
            == .couldNotConnect)
    }

    @Test("ssh failing once through is a connection lost")
    func lost() {
        #expect(status(255, Self.dropped, through: true) == .lost)
        #expect(status(255, Self.closed, through: true) == .lost)
        #expect(status(255, "something ssh has not said before", through: true) == .lost)
        // ssh says it dropped, so it dropped, whatever the screen showed.
        #expect(status(255, Self.dropped, through: false) == .lost)
    }

    /// The far end's own status, `exit 3` included, is the far end's: it
    /// got that far, and it is no failure of the connection's.
    @Test("any other status is the session ending")
    func ended() {
        #expect(status(0, through: true) == .ended)
        #expect(status(3, through: true) == .ended)
        #expect(status(nil, through: true) == .ended)
        #expect(status(nil, through: false) == .couldNotConnect)
    }

    @Test("stopped while connecting is stopped, whatever ssh then said")
    func stopped() {
        #expect(status(255, Self.refused, stopped: true) == .stopped)
        #expect(status(nil, stopped: true) == .stopped)
    }

    // MARK: what it says

    /// The subtitle said "status 255" for a refusal, which is a number; and
    /// "waiting for an answer" for a question nobody could see from the tab
    /// in front.
    @Test("the subtitle is the destination, with the state unless it is through")
    func subtitle() {
        #expect(SessionStatus.connected.subtitle(destination: "deploy@web") == "deploy@web")
        #expect(SessionStatus.connecting.subtitle(destination: "deploy@web") == "deploy@web · connecting")
        #expect(SessionStatus.couldNotConnect.subtitle(destination: "deploy@web")
            == "deploy@web · couldn't connect")
        #expect(SessionStatus.needsAnswer.spoken == "needs you to answer a host-key question")
    }

    @Test("each state that is not through has a symbol other than the dot")
    func symbols() {
        let others: [SessionStatus] = [.needsAnswer, .stopped, .couldNotConnect, .lost, .ended]
        #expect(others.allSatisfy { $0.symbol != SessionStatus.connected.symbol })
        #expect(Set([SessionStatus.needsAnswer, .stopped, .couldNotConnect, .ended].map(\.symbol)).count == 4)
    }

    @Test("the pane names the machine, and a local shell as one")
    func headlines() {
        #expect(SessionStatus.couldNotConnect.headline(for: "staging-web") == "Couldn't connect to staging-web")
        #expect(SessionStatus.connecting.headline(for: "db-01") == "Connecting to db-01")
        #expect(SessionStatus.ended.headline(for: nil) == "The local shell ended")
    }

    @Test("connecting says where, which way, and how long so far")
    func connectingLine() {
        #expect(SessionStatus.connectingLine(
            destination: "deploy@192.0.2.21:2222", through: "through bastion", seconds: 4)
            == "deploy@192.0.2.21:2222, through bastion · 4 s")
        #expect(SessionStatus.connectingLine(destination: "deploy@web", through: "", seconds: 75)
            == "deploy@web · 1 min 15 s")
        #expect(SessionStatus.connectingLine(destination: "", through: "", seconds: 0) == "0 s")
    }

    @Test("a far end's own status is said, ssh's 255 and success are not")
    func exitNote() {
        #expect(SessionStatus.exitNote(3) == "It exited with status 3.")
        #expect(SessionStatus.exitNote(0) == nil)
        #expect(SessionStatus.exitNote(255) == nil)
        #expect(SessionStatus.exitNote(nil) == nil)
    }

    // MARK: what ssh's words mean

    @Test("a refusal names the port nothing is listening on")
    func refusal() {
        #expect(SessionEnding.reason(Self.refused) == "The machine answered, but nothing is listening on port 1.")
    }

    @Test("ssh's commonest failures are each said plainly")
    func reasons() {
        #expect(SessionEnding.reason(Self.unresolved)?.hasPrefix("This Mac can't look that name up") == true)
        #expect(SessionEnding.reason("ssh: connect to host 192.0.2.1 port 22: Operation timed out")?
            .hasPrefix("Nothing answered in time") == true)
        #expect(SessionEnding.reason("ssh: connect to host 10.0.0.5 port 22: No route to host")?
            .hasPrefix("This Mac has no way through") == true)
        #expect(SessionEnding.reason("deploy@192.0.2.21: Permission denied (publickey).")?
            .hasPrefix("The machine turned down") == true)
        #expect(SessionEnding.reason(Self.declined) == "Its key wasn't trusted, so ssh stopped before logging in.")
        #expect(SessionEnding.reason(
            "Received disconnect from 192.0.2.5 port 22:2: Too many authentication failures")?
            .hasPrefix("ssh offered more keys") == true)
        #expect(SessionEnding.reason(
            "Unable to negotiate with 192.0.2.5 port 22: no matching host key type found. Their offer: ssh-rsa")?
            .hasPrefix("This Mac's ssh and the machine") == true)
        #expect(SessionEnding.reason(
            "kex_exchange_identification: Connection closed by remote host\nConnection closed by 192.0.2.10 port 22")
            == "The machine hung up before anything was said.")
        #expect(SessionEnding.reason(Self.dropped) == "The connection dropped while the session was open.")
    }

    /// A changed key fails with "Host key verification failed." too, and the
    /// two mean opposite things: one you chose, one you have to look into.
    @Test("a changed key is told from one you turned down")
    func changedKey() {
        let changed = """
            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
            @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
            Host key verification failed.
            """
        #expect(SessionEnding.reason(changed)?.hasPrefix("The machine's key isn't the one") == true)
        #expect(SessionEnding.isBeforeLogin(changed))
    }

    /// Reached through a jump host, the far end's refusal comes back as the
    /// jump host's: a refusal, but not by the machine it seems to name.
    @Test("a jump host that cannot reach the machine behind it says so")
    func throughAJump() {
        let refused = "channel 0: open failed: connect failed: Connection refused\nstdio forwarding failed"
        #expect(SessionEnding.reason(refused)
            == "The jump host reached the machine behind it, but nothing is listening there.")
        #expect(SessionEnding.reason("channel 0: open failed: connect failed: Name or service not known\nstdio forwarding failed")
            == "The jump host couldn't reach the machine behind it.")
    }

    @Test("a line it does not know means nothing is added to it")
    func unknown() {
        #expect(SessionEnding.reason("") == nil)
        #expect(SessionEnding.reason("Connection to 192.0.2.21 closed.") == nil)
        #expect(!SessionEnding.isDrop("Connection to 192.0.2.21 closed."))
    }

    /// Before logging in, the far end hanging up says "Connection closed by";
    /// after, "Connection to … closed by remote host". The second is a drop.
    @Test("the far end hanging up is told before logging in from after")
    func hangingUp() {
        #expect(SessionEnding.isBeforeLogin("Connection closed by 192.0.2.10 port 22"))
        #expect(!SessionEnding.isDrop("Connection closed by 192.0.2.10 port 22"))
        #expect(SessionEnding.isDrop(Self.closed))
    }
}
