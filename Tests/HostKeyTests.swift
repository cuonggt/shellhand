import Testing
@testable import Shellhand

/// Spotting ssh waiting to be told about a host key, and pulling the question
/// out of the screen around it.
@Suite("Host key question")
nonisolated struct HostKeyTests {
    /// What ssh writes, near enough.
    private static let asking = """
        The authenticity of host 'web (198.51.100.11)' can't be established.
        ED25519 key fingerprint is SHA256:abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG.
        This key is not known by any other names.
        Are you sure you want to continue connecting (yes/no/[fingerprint])?
        """

    // MARK: whether it is being asked

    @Test("the question at the end of the screen is a question")
    func atTheEnd() {
        #expect(HostKey.isBeingAsked(Self.asking))
    }

    /// The bug this rule exists for. ssh writes the question last and then
    /// waits, so anything after it means it has already been answered —
    /// matching the whole buffer left the session stuck on a prompt that was
    /// gone, with the shell's output scrolling past underneath.
    ///
    /// The "Warning: Permanently added" line below is not what the app sees:
    /// it runs `ssh -E`, which sends that to the log. The screen after an
    /// answer is quieter than this, which is what `answeredQuietly` is for.
    @Test("the same question with the session running on after it is not")
    func alreadyAnswered() {
        let answered = Self.asking + """

            Warning: Permanently added 'web' to the list of known hosts.
            deploy@web:~$ ls
            Documents  notes.txt
            deploy@web:~$
            """
        #expect(!HostKey.isBeingAsked(answered))
    }

    @Test("blank lines after it do not count as having moved on")
    func trailingBlanks() {
        #expect(HostKey.isBeingAsked(Self.asking + "\n\n   \n"))
    }

    /// Anything at all after the question means ssh has moved on: it writes
    /// the question last and waits, so nothing else reaches the screen until
    /// the question has been answered. This used to pin the opposite — one
    /// line after the question was "still within reach", an artefact of the
    /// two-row tail rather than a rule — and a real prompt showed what that
    /// cost; see `answeredQuietly`.
    @Test("one line of output after the question means it was answered, as two do")
    func howFarBack() {
        #expect(!HostKey.isBeingAsked(Self.asking + "\nsomething"))
        #expect(!HostKey.isBeingAsked(Self.asking + "\nsomething\nand more"))
    }

    /// What OpenSSH 10.3 really writes, taken from a real `ssh` on a real pty
    /// — `fingerprint is:`, with a colon the fixture above predates — ending on
    /// the closing `?` with nothing after it, as it does while it waits.
    private static let askedForReal = """
        The authenticity of host '[127.0.0.1]:58359 ([127.0.0.1]:58359)' can't be established.
        ED25519 key fingerprint is: SHA256:C5SjKQsmTqrrkBXY2d/2NgFWAzj05pE4qijO5S09/00
        This key is not known by any other names.
        Are you sure you want to continue connecting (yes/no/[fingerprint])?
        """

    /// The bug a real prompt found. A pty echoes the answer onto the question's
    /// **own row**, not below it, and `ssh -E` sends "Permanently added" to its
    /// log rather than the screen — so on a server that logs in quietly, the
    /// answered row and one line of the server's are the whole tail. The
    /// question was asked again, and a second Accept typed `yes` into the live
    /// shell.
    @Test("an answer echoed onto the question's own row means it was answered")
    func answeredQuietly() {
        #expect(HostKey.isBeingAsked(Self.askedForReal))
        #expect(HostKey.question(in: Self.askedForReal).contains("SHA256:C5SjKQsm"))
        #expect(!HostKey.isBeingAsked(Self.askedForReal + " yes"))
        #expect(!HostKey.isBeingAsked(Self.askedForReal + " yes\nshellhand-session-ready"))
        #expect(!HostKey.isBeingAsked(Self.askedForReal + " no"))
    }

    @Test("an empty screen is not a question")
    func empty() {
        #expect(!HostKey.isBeingAsked(""))
        #expect(!HostKey.isBeingAsked("\n\n  \n"))
    }

    @Test("ordinary output is not a question")
    func ordinary() {
        #expect(!HostKey.isBeingAsked("deploy@web:~$ ls\nDocuments  notes.txt"))
    }

    // MARK: what the question says

    /// The fingerprint is the whole point: it is what the person is being
    /// asked to vouch for.
    @Test("the question carries the fingerprint and the warning above it")
    func carriesTheFingerprint() {
        let out = HostKey.question(in: Self.asking)
        #expect(out.contains("authenticity of host 'web (198.51.100.11)'"))
        #expect(out.contains("SHA256:abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG"))
        #expect(out.hasSuffix("continue connecting (yes/no/[fingerprint])?"))
    }

    @Test("whatever came before the warning is left out")
    func leavesTheRestBehind() {
        let noisy = "some earlier output\nand more of it\n" + Self.asking
        let out = HostKey.question(in: noisy)
        #expect(!out.contains("some earlier output"))
        #expect(out.hasPrefix("The authenticity of host"))
    }

    /// Without the opening line there is nothing to anchor to, so it takes a
    /// few lines back — enough to carry a fingerprint.
    @Test("with no warning line it still takes the lines around the question")
    func noOpeningLine() {
        let terse = """
            something
            ED25519 key fingerprint is SHA256:zzzz.
            Are you sure you want to continue connecting (yes/no)?
            """
        let out = HostKey.question(in: terse)
        #expect(out.contains("SHA256:zzzz"))
        #expect(out.hasSuffix("continue connecting (yes/no)?"))
    }

    /// Showing everything is a worse answer than showing the question, and a
    /// much better one than showing nothing.
    @Test("a screen with no question in it comes back whole")
    func noQuestion() {
        let screen = "deploy@web:~$ ls\nDocuments"
        #expect(HostKey.question(in: screen) == screen)
    }

    @Test("the last question wins, where a screen somehow holds two")
    func theLastOne() {
        let twice = Self.asking + "\n" + Self.asking
        let out = HostKey.question(in: twice)
        // One question's worth, not both.
        #expect(out.components(separatedBy: "continue connecting").count == 2)
    }

    // MARK: a question the terminal wrapped

    /// `getBufferAsData` walks the buffer **row by row**, appending a newline
    /// after each, so a question too long for the terminal's width arrives as
    /// two lines with the phrase split between them — and a rule that looks
    /// line by line then finds it in neither. A person with large text in a
    /// narrow window is asked nothing while ssh waits on the pty.
    @Test("a question split mid-phrase across two rows is still a question")
    func wrappedMidPhrase() {
        let wrapped =
            "The authenticity of host 'web' can't be established.\n"
            + "ED25519 key fingerprint is SHA256:abcdefghijklmnop.\n"
            + "Are you sure you want to conti\n"
            + "nue connecting (yes/no/[fingerprint])?"
        #expect(HostKey.isBeingAsked(wrapped))
    }

    /// The buffer right-trims every row, so a wrap that falls on a space
    /// loses that space altogether: rejoining the rows gives
    /// "continueconnecting" and no amount of looking for the phrase as
    /// written will find it.
    @Test("a question wrapped at a space is still a question")
    func wrappedAtASpace() {
        let wrapped =
            "The authenticity of host 'web' can't be established.\n"
            + "ED25519 key fingerprint is SHA256:abcdefghijklmnop.\n"
            + "Are you sure you want to continue\n"
            + "connecting (yes/no/[fingerprint])?"
        #expect(HostKey.isBeingAsked(wrapped))
    }

    /// Worth having separately: the fingerprint is what the person is being
    /// asked to vouch for, and a wrapped question that comes back as the
    /// whole screen has buried it.
    @Test("a wrapped question still carries its fingerprint")
    func wrappedCarriesFingerprint() {
        let wrapped =
            "some earlier output\n"
            + "The authenticity of host 'web' can't be established.\n"
            + "ED25519 key fingerprint is SHA256:abcdefghijklmnop.\n"
            + "Are you sure you want to conti\n"
            + "nue connecting (yes/no/[fingerprint])?"
        let out = HostKey.question(in: wrapped)
        #expect(out.contains("SHA256:abcdefghijklmnop"))
        #expect(!out.contains("some earlier output"))
    }

    /// The guard that must survive all of the above: a wrapped question with
    /// the shell running on after it has still been answered.
    @Test("a wrapped question with output after it is not being asked")
    func wrappedButAnswered() {
        let answered =
            "Are you sure you want to conti\n"
            + "nue connecting (yes/no/[fingerprint])?\n"
            + "Warning: Permanently added 'web'.\n"
            + "deploy@web:~$ ls\n"
            + "Documents  notes.txt"
        #expect(!HostKey.isBeingAsked(answered))
    }

    // MARK: a question wrapped across more than two rows

    /// A screen as a terminal `columns` wide hands it back: each line cut into
    /// rows of that width, each row right-trimmed as `getBufferAsData` trims
    /// it — so a wrap that falls on a space loses the space, as it does for
    /// real. Generated rather than typed, because typed fixtures are how this
    /// rule was tested against a screen no terminal ever produces.
    static func wrapped(_ text: String, at columns: Int) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).flatMap { line -> [String] in
            let characters = Array(line)
            guard !characters.isEmpty else { return [""] }
            return stride(from: 0, to: characters.count, by: columns).map { at in
                var row = String(characters[at..<min(at + columns, characters.count)])
                while row.last?.isWhitespace == true { row.removeLast() }
                return row
            }
        }.joined(separator: "\n")
    }

    /// OpenSSH's real question at widths that wrap its prompt across three,
    /// four, five and six rows. Two rows was all the rule used to look at, so
    /// each of these was a question ssh sat waiting on while the app asked
    /// nobody anything — large text in a narrow window was enough.
    @Test("a question wrapped across three rows or more is a question",
          arguments: [33, 16, 13, 8])
    func wrappedFurther(columns: Int) {
        #expect(HostKey.isBeingAsked(Self.wrapped(Self.askedForReal, at: columns)))
    }

    /// The tail only had to reach further back. It must not let an answered
    /// question count again, at any of those widths, which is what the
    /// closing-`?` rule is for.
    @Test("wrapped that far and then answered, it is not",
          arguments: [33, 16, 13, 8])
    func wrappedFurtherAnswered(columns: Int) {
        for answered in [
            Self.askedForReal + " yes",
            Self.askedForReal + " yes\nshellhand-session-ready",
            Self.askedForReal + " no",
        ] {
            #expect(!HostKey.isBeingAsked(Self.wrapped(answered, at: columns)), "at \(columns) columns")
        }
    }

    /// At widths that narrow the warning and the fingerprint wrap too, so the
    /// question shown has to be put back together from rows rather than found
    /// in one — or the fingerprint is cut, at the one moment somebody has to
    /// read it. Compared with whitespace out, since the rows break it anywhere.
    @Test("wrapped that far, it still shows the whole fingerprint",
          arguments: [33, 16, 13, 8])
    func wrappedFurtherShowsFingerprint(columns: Int) {
        let screen = Self.wrapped("some earlier output\n" + Self.askedForReal, at: columns)
        let shown = HostKey.question(in: screen).filter { !$0.isWhitespace }
        #expect(shown.contains("SHA256:C5SjKQsmTqrrkBXY2d/2NgFWAzj05pE4qijO5S09/00"))
        #expect(shown.hasPrefix("Theauthenticityofhost"))
        #expect(shown.hasSuffix("(yes/no/[fingerprint])?"))
        #expect(!shown.contains("someearlieroutput"))
    }
}
