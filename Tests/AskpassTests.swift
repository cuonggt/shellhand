import Foundation
import Testing
@testable import Shellhand

/// The askpass helper's own decisions, which are the half of password
/// authentication this suite can hold.
///
/// **The other half cannot be held here at all.** Password auth validates
/// against the real system, and `LocalSSHD` runs as whoever runs the suite
/// with no test account to give a password to — so whether ssh actually logs
/// in this way is proven by hand, and `scripts/askpass-probe.sh` is what
/// proves where ssh puts each prompt. What is checkable is everything either
/// side of that: which prompt is a question, what a connection carries, and
/// which options an unattended child is given.
@Suite("The askpass helper")
nonisolated struct AskpassTests {
    private let switches = Identity(
        id: "i-switches", name: "switches", kind: .password, user: "root")
    private let deploy = Identity(
        id: "i-deploy", name: "deploy", user: "deploy", keyPath: "~/.ssh/id_ed25519")

    private func resolved(_ identity: Identity?) -> Resolved {
        let host = Shellhand.Host(
            id: "h", name: "sw-1", addr: "10.0.9.2", identityId: identity?.id ?? "")
        return Resolver(
            groups: [], hosts: [host], identities: identity.map { [$0] } ?? []
        ).resolve(host)
    }

    // MARK: which prompt is a question

    /// **The trap this exists to stop.** ssh puts every prompt of a
    /// connection through the helper, the host-key question included —
    /// answered with the password like everything else, ssh asks again until
    /// it hears yes, no or the fingerprint, so a password host whose key was
    /// not yet known was asked several hundred times a second, each time
    /// another keychain read, and the connection never ended.
    @Test("ssh's question about a new host key is told from a password prompt")
    func questions() {
        // OpenSSH's own wording, as `scripts/askpass-probe.sh` captured it.
        #expect(Askpass.isQuestion(
            "Are you sure you want to continue connecting (yes/no/[fingerprint])? "))
        #expect(Askpass.isQuestion("Please type 'yes', 'no' or the fingerprint: "))
        #expect(!Askpass.isQuestion("root@10.0.9.2's password: "))
        // A server's own prompt can be in any language, and anything not
        // recognised as a question is taken to be asking for the password —
        // a helper that answered only what it knew would lock out a host
        // that logged in fine yesterday.
        #expect(!Askpass.isQuestion("Passwort: "))
        #expect(!Askpass.isQuestion("Password for root: "))
    }

    /// Nobody can read a fingerprint in a window with no terminal in it, so
    /// an unattended connection says no and the way out is the tab.
    @Test("an unattended connection declines a host key it has never seen")
    func declinesAHostKey() {
        #expect(Askpass.answerToQuestion() == "no")
    }

    // MARK: what a connection carries

    @Test("a password identity carries the helper and its id, and no password")
    func environmentForAPassword() {
        let out = Askpass.environment(for: resolved(switches))
        #expect(out["SSH_ASKPASS"] != nil)
        #expect(Askpass.stops(from: out[Askpass.stopsVariable] ?? "").map(\.password) == ["i-switches"])
        // **Never the password.** An argument list is readable by every
        // process on the machine and an environment variable by every child
        // of one; the password goes keychain to stdout and nowhere else.
        #expect(!out.values.contains { $0.lowercased().contains("password") })
        // **And REQUIRE, which the first version of this left out.** ssh
        // wants `DISPLAY` set before it will use a helper, a GUI app has
        // none, and without this the helper was never run: the connection
        // died at preauth with "Permission denied", which reads exactly like
        // a wrong password. Safe here and nowhere else — this child has no
        // pty, so there is no terminal for the host-key question to be taken
        // away from.
        #expect(out["SSH_ASKPASS_REQUIRE"] == "force")
    }

    @Test("every other kind of identity changes nothing about the connection")
    func environmentForEverythingElse() {
        #expect(Askpass.environment(for: resolved(deploy)).isEmpty)
        #expect(Askpass.environment(for: resolved(nil)).isEmpty)
        #expect(Askpass.childEnvironment(for: resolved(deploy)) == nil)
    }

    @Test("a password identity with no id carries nothing — a typed machine has none")
    func noID() {
        var unsaved = switches
        unsaved.id = ""
        // It cannot be pointed at from anywhere, but the guard is worth
        // having: an empty id is the one a machine typed into ⌘K shares, and
        // a keychain lookup under "" would be somebody else's password.
        let host = Shellhand.Host(id: "", name: "typed", addr: "10.0.9.2")
        let out = Askpass.environment(
            for: Resolver(groups: [], hosts: [host], identities: [unsaved]).resolve(host))
        #expect(out.isEmpty)
    }

    /// `Process.environment` replaces what a child would inherit rather than
    /// adding to it, so a child handed only the two variables would lose
    /// `PATH` and everything else.
    @Test("the child's environment is the inherited one with ours folded in")
    func childEnvironmentMerges() throws {
        let out = try #require(Askpass.childEnvironment(for: resolved(switches)))
        #expect(Askpass.stops(from: out[Askpass.stopsVariable] ?? "").map(\.password) == ["i-switches"])
        for (key, value) in ProcessInfo.processInfo.environment
        where key != Askpass.stopsVariable && key != "SSH_ASKPASS" {
            #expect(out[key] == value, "the child lost \(key)")
        }
    }

    // MARK: what an unattended child is told

    @Test("a password identity drops BatchMode, which would turn off the prompt it answers")
    func unattendedWithAnAnswer() {
        let options = SSHArgs.unattended(resolved(switches))
        #expect(options == SSHArgs.answering(resolved(switches)))
        #expect(!options.contains("BatchMode=yes"))
        // Keys first would let ssh in as somebody else before it ever
        // reached the password; three tries would be three keychain reads
        // answering the same wrong thing.
        #expect(options.contains("PreferredAuthentications=keyboard-interactive,password"))
        #expect(options.contains("NumberOfPasswordPrompts=1"))
    }

    @Test("every other identity keeps BatchMode, since nothing can answer a prompt")
    func unattendedWithout() {
        #expect(SSHArgs.unattended(resolved(deploy)) == SSHArgs.unattended)
        #expect(SSHArgs.unattended(resolved(nil)) == ["-o", "BatchMode=yes"])
    }

    @Test("the sftp child's own argv carries it, ahead of anything a config says")
    func sftpArguments() {
        let args = SFTPClient.arguments(resolved(switches))
        #expect(args.contains("PreferredAuthentications=keyboard-interactive,password"))
        #expect(!args.contains("BatchMode=yes"))
        // ssh keeps the **first** value it is given for a setting, so what
        // nothing may override has to lead. `-s` marks where the subsystem
        // flags begin, and everything fixed stands before it.
        let fixedEnds = try! #require(args.firstIndex(of: "-s"))
        let preferred = try! #require(
            args.firstIndex(of: "PreferredAuthentications=keyboard-interactive,password"))
        #expect(preferred < fixedEnds)

        let withKey = SFTPClient.arguments(resolved(deploy))
        #expect(withKey.contains("BatchMode=yes"))
        #expect(!withKey.contains("PreferredAuthentications=keyboard-interactive,password"))
    }
}
