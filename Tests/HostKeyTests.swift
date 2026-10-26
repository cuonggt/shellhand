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

    @Test("one line of output after it is still within reach, two is not")
    func howFarBack() {
        // The tail is the last two lines that carry anything, so a single
        // line of output still leaves the question inside it.
        #expect(HostKey.isBeingAsked(Self.asking + "\nsomething"))
        #expect(!HostKey.isBeingAsked(Self.asking + "\nsomething\nand more"))
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
}
