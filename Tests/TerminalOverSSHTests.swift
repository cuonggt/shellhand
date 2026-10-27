import Foundation
import Testing

@testable import Shellhand

/// A terminal session over real `ssh`, against the local `sshd`: the watchdog's
/// states and the host-key question, met for real rather than fed to a terminal
/// by hand.
///
/// Both of 0.0.5's terminal bugs lived here — a blank screen read as connected,
/// and a wrapped host-key question never seen — and both were found with text
/// written into a terminal. This is OpenSSH's own prompt, from its own `ssh`, on
/// a real pty, so a change in its wording shows up here first.
///
/// Kept off your own `~/.ssh` as `SSHTransportTests` is: `LocalSSHD.isolation`
/// leads the argv that `SSHArgs` builds, exactly as it builds one for a session.
/// The server runs a forced command instead of your login shell, so nothing of
/// yours runs interactively: it says it is ready, once, and waits.
@MainActor
@Suite("A terminal over real ssh", .timeLimit(.minutes(1)))
struct TerminalOverSSHTests {
    static let ready = "shellhand-session-ready"

    private func server() throws -> LocalSSHD {
        try LocalSSHD(session: "echo \(Self.ready); exec sleep 60")
    }

    private func start(_ argv: [String]) -> TerminalSession {
        let session = TerminalSession(title: "local-sshd", host: nil)
        session.start(argv: argv)
        return session
    }

    /// Waits for `done`, looking often enough to catch every state the watchdog
    /// passes through on the way, and hands back each one seen in order.
    private func states(
        of session: TerminalSession, until done: (TerminalSession.State) -> Bool
    ) async -> [TerminalSession.State] {
        var seen = [session.state]
        for _ in 0..<500 where !done(session.state) {
            try? await Task.sleep(for: .milliseconds(20))
            if session.state != seen.last { seen.append(session.state) }
        }
        return seen
    }

    private static func asking(_ state: TerminalSession.State) -> Bool {
        if case .askingHostKey = state { true } else { false }
    }

    private static func ended(_ state: TerminalSession.State) -> Bool {
        if case .ended = state { true } else { false }
    }

    @Test("a real login takes the session from connecting to connected")
    func connects() async throws {
        let server = try server()
        defer { server.stop() }
        let session = start(SSHArgs.build(server.resolved(), fixed: server.isolation()))
        defer { session.close() }

        let seen = await states(of: session) { $0 == .connected }
        #expect(seen.first == .connecting)
        #expect(seen.last == .connected, "went through \(seen)")
        #expect(session.screen.contains(Self.ready), "the far side never said it was ready")
    }

    /// The watchdog's whole promise, against what it was for: a server that
    /// will not let you in must never read as connected. ssh's own words go to
    /// its log rather than the screen, which is what leaves the screen blank.
    @Test("a login the server refuses never reads as connected")
    func refusedNeverConnected() async throws {
        let server = try server()
        defer { server.stop() }
        let stranger = try LocalSSHD.key(in: TestScratch.directory("stranger"))
        let session = start(
            SSHArgs.build(server.resolved(identity: stranger), fixed: server.isolation()))
        defer { session.close() }

        let seen = await states(of: session, until: Self.ended)
        #expect(!seen.contains(.connected), "a refused login read as connected: \(seen)")
        guard case .ended(_, let diagnostic) = session.state else {
            Issue.record("the session never ended: \(seen)")
            return
        }
        #expect(diagnostic.contains("Permission denied"), "ssh's log said: \(diagnostic)")
    }

    /// The question as OpenSSH really asks it, seen; then answered yes. The
    /// key is written down, and only in scratch.
    @Test("ssh's real host-key question is seen, and yes goes through")
    func hostKeyAccepted() async throws {
        let server = try server()
        defer { server.stop() }
        let known = TestScratch.directory("ask-yes") + "/known_hosts"
        FileManager.default.createFile(atPath: known, contents: Data())
        let mine = NSHomeDirectory() + "/.ssh/known_hosts"
        let before = SSHTransportTests.fingerprint(mine)
        let session = start(
            SSHArgs.build(
                server.resolved(),
                fixed: server.isolation(knownHosts: known, askingAboutHostKeys: true)))
        defer { session.close() }

        _ = await states(of: session, until: Self.asking)
        guard case .askingHostKey(let question) = session.state else {
            Issue.record("ssh's question was never seen. On screen: \(session.screen)")
            return
        }
        #expect(question.contains("SHA256:"), "the fingerprint is the point: \(question)")

        session.answerHostKey(accept: true)
        let seen = await states(of: session) { $0 == .connected }
        #expect(seen.last == .connected, "after yes, went through \(seen)")
        #expect(session.screen.contains(Self.ready))
        let recorded = (try? String(contentsOfFile: known, encoding: .utf8)) ?? ""
        #expect(recorded.contains("[127.0.0.1]:\(server.port)"), "scratch known_hosts: \(recorded)")
        #expect(SSHTransportTests.fingerprint(mine) == before)
    }

    @Test("answering no ends the session, and nothing is written")
    func hostKeyRefused() async throws {
        let server = try server()
        defer { server.stop() }
        let known = TestScratch.directory("ask-no") + "/known_hosts"
        FileManager.default.createFile(atPath: known, contents: Data())
        let session = start(
            SSHArgs.build(
                server.resolved(),
                fixed: server.isolation(knownHosts: known, askingAboutHostKeys: true)))
        defer { session.close() }

        _ = await states(of: session, until: Self.asking)
        guard case .askingHostKey = session.state else {
            Issue.record("ssh's question was never seen. On screen: \(session.screen)")
            return
        }
        session.answerHostKey(accept: false)
        let seen = await states(of: session, until: Self.ended)
        #expect(!seen.contains(.connected), "after no, went through \(seen)")
        guard case .ended(_, let diagnostic) = session.state else {
            Issue.record("the session never ended: \(seen)")
            return
        }
        #expect(diagnostic.contains("Host key verification failed"), "ssh's log said: \(diagnostic)")
        #expect(FileManager.default.contents(atPath: known) == Data())
    }
}
