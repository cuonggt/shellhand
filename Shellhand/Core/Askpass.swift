import Foundation

/// How a password reaches ssh.
///
/// ssh asks a helper program instead of the terminal, and the helper is this
/// same app run in a mode of its own. What travels in the environment is the
/// **keychain account** the password is filed under — an identity's id, or a
/// host's or a group's own (`Keychain.account`) — and the path to the app,
/// never the password, because an argument list is readable by every process
/// on the machine and an environment variable by every child of one. The
/// password goes from the keychain to the helper's standard output, which
/// belongs to those two processes and nothing else.
///
/// **This is for a connection with nobody in front of it** — the `sftp` child
/// behind the file window.
///
/// `SSH_ASKPASS_REQUIRE=force` is **required**, and the first version of this
/// left it out on a wrong reading of the probe. Measured three ways against
/// macOS's own `sshd`: with no tty and no `DISPLAY`, ssh does **not** call the
/// helper; with no tty and `DISPLAY` set it does; and `force` lifts the
/// `DISPLAY` condition. A GUI app on macOS has no `DISPLAY`, so without this
/// the helper was never run at all and the connection died at `preauth` with
/// "Permission denied" — which reads exactly like a wrong password.
///
/// Forcing it **here** is safe for the reason the rest of it is: this child
/// has no pty, so there is no terminal for the host-key question to be taken
/// away from. **Don't force it on a session**, which has one, until that
/// question has somewhere a person can see it:
/// → docs/notes/terminal.md#where-a-forced-askpass-puts-the-host-key-question
nonisolated enum Askpass {
    /// The machines on the way, one a line — who logs in, the name ssh is
    /// handed, the address, and where its password is kept, tab-separated
    /// (`stops(_:)`) — so the helper answers each prompt for the machine it
    /// names, a jump host's with the jump host's. Ids and names, never a
    /// password. Its presence is also what tells the app it was run as a
    /// helper rather than by a person: ssh invokes the program with the
    /// prompt as its only argument, so there is no subcommand there to
    /// recognise.
    static let stopsVariable = "SHELLHAND_ASKPASS_STOPS"

    // MARK: what a connection carries

    /// What an unattended connection needs added to its environment, and
    /// nothing at all where no password reaches the host or a jump host on
    /// the way — so no other connection changes shape because this exists.
    ///
    /// Empty where there is no password to answer with, and where the app has
    /// no executable path to point ssh at. A machine typed into ⌘K has no id
    /// to have filed one under, so nothing reaches it of its own. Every ssh
    /// in a jump chain inherits it, and each is answered for its own machine
    /// (`account(for:among:)`).
    static func environment(for resolved: Resolved) -> [String: String] {
        let stops = resolved.route.stops
        guard stops.contains(where: { !$0.password.isEmpty }),
              let app = Bundle.main.executablePath
        else { return [:] }
        var out = [
            "SSH_ASKPASS": app,
            // Without this the helper is never run: ssh wants `DISPLAY` set
            // before it will use one, and a GUI app has none. See above.
            "SSH_ASKPASS_REQUIRE": "force",
            stopsVariable: Self.stops(stops),
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

    /// The machines on the way, as `stopsVariable` carries them.
    static func stops(_ stops: [Route.Stop]) -> String {
        stops.map { [$0.user, $0.dest, $0.addr, $0.password].joined(separator: "\t") }
            .joined(separator: "\n")
    }

    /// The same, read back; a line that is not four fields is passed over.
    static func stops(from text: String) -> [Route.Stop] {
        text.split(separator: "\n").compactMap { line in
            let field = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard field.count == 4 else { return nil }
            return Route.Stop(name: field[1], dest: field[1], addr: field[2], port: 22,
                              user: field[0], password: field[3])
        }
    }

    /// Where the password for `prompt` is kept, among the machines on the
    /// way: the one the prompt names, by user and machine in either of ssh's
    /// shapes (`PasswordPrompt.stop(namedIn:)`), or nil where that one keeps
    /// none — a jump host is never handed the host's password. A prompt
    /// naming none of them is the host's own only where the host is all there
    /// is: ssh wording it some way the route did not foresee is no reason to
    /// fail a direct connection, and every reason not to guess between two
    /// machines.
    static func account(
        for prompt: String, among stops: [Route.Stop], localUser: String = NSUserName()
    ) -> String? {
        let account: String
        if let named = PasswordPrompt.stop(
            namedIn: prompt, route: Route(stops: stops), localUser: localUser)
        {
            account = stops[named].password
        } else if stops.count == 1 {
            account = stops[0].password
        } else {
            return nil
        }
        return account.isEmpty ? nil : account
    }

    // MARK: being the helper

    /// The machines on the way, when this process is a helper.
    static var stopsBeingAsked: [Route.Stop]? {
        let text = ProcessInfo.processInfo.environment[stopsVariable] ?? ""
        return text.isEmpty ? nil : stops(from: text)
    }

    /// Answers one prompt and stops.
    ///
    /// A failure here is silent as far as ssh is concerned — it takes
    /// whatever it gets on standard output — so the reason goes to standard
    /// error, which for a file session is the stderr the window reports.
    /// Exiting non-zero tells ssh no answer is coming, which becomes an
    /// ordinary refusal rather than a prompt that hangs.
    static func answer(stops: [Route.Stop], prompt: String) -> Never {
        if isQuestion(prompt) {
            // **No**, always, and that is not a shrug. Nobody can read a
            // fingerprint in a window with no terminal in it, and a yes here
            // would write the key down on their behalf. The way out is the
            // one the file window already offers for a host it cannot reach:
            // open it in a tab, where the question is put to somebody.
            print(answerToQuestion())
            exit(0)
        }
        guard let account = account(for: prompt, among: stops) else {
            complain("no password kept for the machine asking — type one in Shellhand, in "
                + "its editor, its group's or its identity's")
        }
        do {
            guard let password = try Keychain.password(for: account) else {
                complain("no password stored for it — type one in Shellhand, in the "
                    + "host's editor, its group's or its identity's")
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
