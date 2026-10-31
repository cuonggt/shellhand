import Foundation
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

    /// OpenSSH's own words for a key file that is not there. It prints this
    /// before it starts writing to its log, so `-E` does not keep it off the
    /// terminal — measured, beside a connection refused that went to the log.
    private static let missingKey =
        "Warning: Identity file /Users/someone/.ssh/id_ed25519 not accessible: No such file or directory."

    /// The walk after 0.1.4 found a session still trying to reach its host
    /// shown connected, because ssh had warned about a key file it could not
    /// find — twice, the hop's ssh warning too.
    @Test("ssh's own warnings are not the far side answering")
    func warningsDoNotConnect() {
        #expect(SessionProgress.next(from: .connecting, screen: Self.missingKey) == nil)
        #expect(SessionProgress.next(
            from: .connecting, screen: Self.missingKey + "\n" + Self.missingKey + "\n\n") == nil)
        let added = "Warning: Permanently added 'bastion' (ED25519) to the list of known hosts."
        #expect(SessionProgress.next(from: .connecting, screen: added) == nil)
    }

    /// However narrow the terminal: the warning arrives as rows with its
    /// words cut between them, as it did in the walk, and each row trimmed.
    @Test("a warning cut across rows is still ssh's own")
    func cutWarningsDoNotConnect() {
        let warning = Array(Self.missingKey)
        for width in [17, 40, 70] {
            let rows = stride(from: 0, to: warning.count, by: width).map {
                String(warning[$0..<min($0 + width, warning.count)])
                    .trimmingCharacters(in: .whitespaces)
            }
            #expect(SessionProgress.next(from: .connecting, screen: rows.joined(separator: "\n")) == nil,
                    "at \(width) columns")
        }
    }

    @Test("the far side after a warning is through")
    func farSideAfterAWarningConnects() {
        #expect(SessionProgress.next(
            from: .connecting, screen: Self.missingKey + "\ndeploy@web:~$ ") == .connected)
        #expect(SessionProgress.next(
            from: .connecting, screen: Self.missingKey + "\ndeploy@web's password: ") == .connected)
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

    // MARK: whether the screen is read at all

    /// Connecting and a question up are the whole reason the watchdog
    /// exists, however long ago anything happened.
    @Test("connecting and asking are always read")
    func readWhileConnecting() {
        let longAgo = Date(timeIntervalSinceNow: -3600)
        #expect(SessionProgress.watches(.connecting, connectedAt: longAgo))
        #expect(SessionProgress.watches(.askingHostKey(Self.asking), connectedAt: longAgo))
    }

    /// Two minutes, so a jump chain's next hop is still asked: the answered
    /// question on screen reads as being through before that hop asks.
    @Test("a session through is read while it settles, and not after")
    func readWhileSettling() {
        let now = Date()
        let settling = SessionProgress.settling
        #expect(SessionProgress.watches(.connected, connectedAt: now, now: now))
        #expect(SessionProgress.watches(.connected, connectedAt: now - (settling - 1), now: now))
        #expect(!SessionProgress.watches(.connected, connectedAt: now - settling, now: now))
        #expect(!SessionProgress.watches(.connected, connectedAt: now - 3600, now: now))
    }

    @Test("an ended session is never read")
    func endedIsNotRead() {
        #expect(!SessionProgress.watches(.ended(code: 0, diagnostic: ""), connectedAt: nil))
    }

    @Test("a session through with no time on it is read, as before there was a rule")
    func untimedIsRead() {
        #expect(SessionProgress.watches(.connected, connectedAt: nil))
    }
}
