import Foundation

/// How a password reaches ssh.
///
/// ssh asks a helper program instead of the terminal, and the helper is this
/// same app run in a mode of its own. What travels in the environment is the
/// **identity's id** and the path to the app — never the password, because an
/// argument list is readable by every process on the machine and an
/// environment variable by every child of one. The password goes from the
/// keychain to the helper's standard output, which belongs to those two
/// processes and nothing else.
///
/// **This is for a connection with nobody in front of it** — the `sftp` child
/// behind the file window — and that is why it needs no
/// `SSH_ASKPASS_REQUIRE`. Measured, under a pty, against macOS's own `sshd`:
/// unforced, with a tty, ssh never calls the helper at all and asks on the
/// terminal; without a tty it uses the helper as it stands. A child whose
/// stdin carries the protocol has no tty, so setting the variable is enough.
/// **Don't force it here, and don't force it on a session** until the
/// host-key question has somewhere a person can see it:
/// → docs/notes/terminal.md#where-a-forced-askpass-puts-the-host-key-question
nonisolated enum Askpass {
    /// Names the identity whose password ssh is asking for. Its presence is
    /// also what tells the app it was run as a helper rather than by a
    /// person: ssh invokes the program with the prompt as its only argument,
    /// so there is no subcommand there to recognise.
    static let identityVariable = "SHELLHAND_ASKPASS_IDENTITY"

    // MARK: what a connection carries

    /// What an unattended connection needs added to its environment, and
    /// nothing at all for every other kind of identity — so no other
    /// connection changes shape because this exists.
    ///
    /// Empty where there is no password to answer with, where the app has no
    /// executable path to point ssh at, and — deliberately — where the
    /// identity has no id, which is what a machine typed into ⌘K carries.
    static func environment(for resolved: Resolved) -> [String: String] {
        guard resolved.identityKind == .password, !resolved.identityId.isEmpty,
              let app = Bundle.main.executablePath
        else { return [:] }
        var out = [
            "SSH_ASKPASS": app,
            identityVariable: resolved.identityId,
        ]
        // Where the password is filed, when it is not the usual place: the
        // helper is a process of its own and would otherwise look in the one
        // a test run was keeping out of.
        let named = ProcessInfo.processInfo.environment[Keychain.serviceVariable] ?? ""
        if !named.isEmpty { out[Keychain.serviceVariable] = named }
        return out
    }

    /// The same, folded into the environment a child would otherwise inherit.
    /// `Process.environment` replaces rather than adds, so a child handed
    /// only the two variables above would lose `PATH` and everything else.
    static func childEnvironment(for resolved: Resolved) -> [String: String]? {
        let ours = environment(for: resolved)
        guard !ours.isEmpty else { return nil }
        return ProcessInfo.processInfo.environment.merging(ours) { _, mine in mine }
    }

    // MARK: being the helper

    /// The identity ssh is asking about, when this process is a helper.
    static var identityBeingAsked: String? {
        let id = ProcessInfo.processInfo.environment[identityVariable] ?? ""
        return id.isEmpty ? nil : id
    }

    /// Answers one prompt and stops.
    ///
    /// A failure here is silent as far as ssh is concerned — it takes
    /// whatever it gets on standard output — so the reason goes to standard
    /// error, which for a file session is the stderr the window reports.
    /// Exiting non-zero tells ssh no answer is coming, which becomes an
    /// ordinary refusal rather than a prompt that hangs.
    static func answer(identity id: String, prompt: String) -> Never {
        if isQuestion(prompt) {
            // **No**, always, and that is not a shrug. Nobody can read a
            // fingerprint in a window with no terminal in it, and a yes here
            // would write the key down on their behalf. The way out is the
            // one the file window already offers for a host it cannot reach:
            // open it in a tab, where the question is put to somebody.
            print(answerToQuestion())
            exit(0)
        }
        do {
            guard let password = try Keychain.password(for: id) else {
                complain("no password stored for this identity — open it in "
                    + "Shellhand's Identities and type one")
            }
            print(password)
            exit(0)
        } catch {
            complain(error.localizedDescription)
        }
    }

    private static func complain(_ said: String) -> Never {
        FileHandle.standardError.write(Data("shellhand askpass: \(said)\n".utf8))
        exit(1)
    }

    /// Whether ssh is asking something rather than asking for the password.
    ///
    /// **ssh puts every prompt of the connection through this helper**, not
    /// only the password, and the one that matters is whether to trust a host
    /// key it has not seen before. Answered with the password like everything
    /// else, ssh asks again until it hears yes, no or the fingerprint — so a
    /// password host whose key was not yet known was asked several hundred
    /// times a second, each time another keychain read, and the connection
    /// never ended. That is the shape of the bug this exists to stop, and it
    /// was recorded before the cut rather than found twice.
    ///
    /// Anything else is still taken to be asking for the password. A server's
    /// own prompt can say so in any language — "Passwort:" — and a helper
    /// that answered only what it recognised would lock out a host that
    /// logged in fine yesterday.
    static func isQuestion(_ prompt: String) -> Bool {
        prompt.contains("(yes/no") || prompt.contains("'yes'")
    }

    /// What an unattended connection says to a host key it has never seen.
    /// Its own function so the one place it is decided can be read, and so a
    /// session's answer — which will not be this — has somewhere to differ.
    static func answerToQuestion() -> String { "no" }
}
