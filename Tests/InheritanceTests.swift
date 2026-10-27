import Foundation
import SwiftTerm
import Testing

@testable import Shellhand

/// What a terminal's child inherits from this process.
///
/// SwiftTerm starts a terminal's child with `forkpty` and goes straight to
/// `execve` without closing a descriptor, so anything not marked close-on-exec
/// when a terminal opens goes into that terminal's `ssh` for as long as it
/// runs. These fork exactly the way a terminal does and ask the child itself,
/// through `/dev/fd`, which is the one answer that cannot be wrong — the same
/// choice the local-shell test made when it asked the shell where it started.
@Suite("What a terminal's child inherits", .timeLimit(.minutes(1)))
nonisolated struct InheritanceTests {
    @Test("a pipe the app marks is not handed to a terminal's child")
    func markedPipe() {
        let pipe = Pipe()
        SFTPClient.closeOnExec(pipe)
        #expect(!Self.inheritedByATerminal(pipe.fileHandleForReading.fileDescriptor))
        #expect(!Self.inheritedByATerminal(pipe.fileHandleForWriting.fileDescriptor))
    }

    /// The control, and not optional: a probe that could never see an
    /// inherited descriptor would pass the test above with the fix taken out.
    @Test("a pipe nobody marks is handed to a terminal's child")
    func unmarkedPipe() {
        let pipe = Pipe()
        #expect(Self.inheritedByATerminal(pipe.fileHandleForReading.fileDescriptor))
    }

    /// Forks the way a terminal does and asks the child whether `descriptor`
    /// is open in it: `[ -e /dev/fd/N ]` is a builtin, so the shell answers
    /// about itself rather than about a child of its own.
    static func inheritedByATerminal(_ descriptor: Int32) -> Bool {
        var size = winsize()
        guard
            let child = PseudoTerminalHelpers.fork(
                andExec: "/bin/sh", args: ["/bin/sh", "-c", "[ -e /dev/fd/\(descriptor) ]"],
                env: ["PATH=/usr/bin:/bin"], desiredWindowSize: &size)
        else {
            Issue.record("could not fork the way a terminal does")
            return false
        }
        // Kept open until the child has answered: closing a pty's master
        // hangs up on whatever is on the other side of it.
        defer { Darwin.close(child.masterFd) }
        var status: Int32 = 0
        waitpid(child.pid, &status, 0)
        // WIFEXITED and WEXITSTATUS, which Swift does not import as macros.
        return status & 0x7f == 0 && (status >> 8) & 0xff == 0
    }
}
