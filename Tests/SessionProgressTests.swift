import Testing
@testable import Shellhand

/// What the watchdog makes of a screen, without the watchdog.
///
/// Every one of these needed a pty, an unknown host and a window before the
/// rule was lifted out of the loop.
@Suite("Session progress")
nonisolated struct SessionProgressTests {
    /// What ssh writes, near enough.
    private static let asking = """
        The authenticity of host 'web (198.51.100.11)' can't be established.
        ED25519 key fingerprint is SHA256:abcdefghijklmnop.
        Are you sure you want to continue connecting (yes/no/[fingerprint])?
        """

    // MARK: the host key question

    @Test("a question at the end of the screen asks the app")
    func asksTheQuestion() throws {
        let next = SessionProgress.next(from: .connecting, screen: Self.asking)
        guard case let .askingHostKey(question) = next else {
            Issue.record("expected a question, got \(String(describing: next))")
            return
        }
        #expect(question.contains("SHA256:abcdefghijklmnop"))
        #expect(question.hasSuffix("continue connecting (yes/no/[fingerprint])?"))
    }

    /// The watchdog looks five times a second. Re-posing the question would
    /// rebuild it under the person reading it, over and over.
    @Test("the question is not posed again while it is being answered")
    func doesNotPoseItTwice() {
        #expect(SessionProgress.next(from: .askingHostKey("asked"), screen: Self.asking) == nil)
    }

    /// The question's own text stays on screen after it is answered, so this
    /// is the path out of `.askingHostKey` and it has to work.
    @Test("a question that has been answered moves on to connected")
    func answeredMovesOn() {
        let answered = Self.asking + """

            Warning: Permanently added 'web' to the list of known hosts.
            deploy@web:~$
            """
        #expect(SessionProgress.next(from: .askingHostKey("asked"), screen: answered) == .connected)
    }

    /// The instant after an answer: the state is back to connecting, but the
    /// pty has not echoed the answer, so the screen still shows the question
    /// exactly as it was asked. Asked again there, the dialog came back for a
    /// tick — and an Accept in that tick typed `yes` into the shell.
    @Test("the question just answered is not asked again before its echo arrives")
    func answeredIsNotAskedAgain() {
        let asked = HostKey.question(in: Self.asking)
        #expect(SessionProgress.next(from: .connecting, screen: Self.asking, answered: asked) == nil)
    }

    /// What is held back is that question, not questions: a jump chain asks
    /// one per hop, and the second has to be asked even straight after the
    /// first was answered.
    @Test("a different question after an answer is still asked")
    func aDifferentQuestionIsAsked() {
        let first = HostKey.question(in: Self.asking)
        let second = Self.asking
            .replacingOccurrences(of: "web (198.51.100.11)", with: "db (198.51.100.12)")
            .replacingOccurrences(of: "abcdefghijklmnop", with: "qrstuvwxyz012345")
        #expect(
            SessionProgress.next(from: .connecting, screen: second, answered: first)
                == .askingHostKey(HostKey.question(in: second)))
    }

    // MARK: getting through

    @Test("anything from the far side means the connection is through")
    func outputConnects() {
        #expect(SessionProgress.next(from: .connecting, screen: "deploy@web:~$ ") == .connected)
    }

    @Test("a session already connected is left alone")
    func connectedStaysPut() {
        #expect(SessionProgress.next(from: .connected, screen: "deploy@web:~$ ls") == nil)
    }

    /// Nil, not `.connected`: ssh may simply not have spoken yet, and an
    /// empty screen is no evidence of a connection.
    @Test("an empty screen moves nothing")
    func emptyMovesNothing() {
        #expect(SessionProgress.next(from: .connecting, screen: "") == nil)
    }

    /// The bug this rule was written with. A real terminal that has heard
    /// nothing hands back its own blank rows rather than an empty string, and
    /// counting those as output took every session to `.connected` 200ms after
    /// it opened. `TerminalSessionTests` pins the buffer's side of it.
    @Test("a screen of nothing but blank rows moves nothing either")
    func blankMovesNothing() {
        #expect(SessionProgress.next(from: .connecting, screen: "\n\n\n") == nil)
        #expect(SessionProgress.next(from: .connecting, screen: "   \n   \n") == nil)
        #expect(SessionProgress.next(from: .connecting, screen: String(repeating: " ", count: 80)) == nil)
    }

    // MARK: a session that has ended

    @Test("an ended session is not moved by what is still on its screen")
    func endedStaysEnded() {
        let ended = TerminalSession.State.ended(code: 255, diagnostic: "")
        #expect(SessionProgress.next(from: ended, screen: "deploy@web:~$ ") == nil)
        #expect(SessionProgress.next(from: ended, screen: Self.asking) == nil)
    }
}
