import Foundation

/// The one moment a terminal must not fork in: between a descriptor being made
/// and its being marked close-on-exec.
///
/// SwiftTerm starts a terminal's child with `forkpty` and goes straight to
/// `execve` without closing anything, so whatever is open and unmarked at that
/// instant goes into the terminal's `ssh` for as long as it runs — a leak at
/// best, and at worst a read waiting on an end of file that never comes because
/// a terminal is holding the other end. Upstream knows (#716), declined the fix
/// in the child, and treats the rest as the host's job (#719), so it is ours.
///
/// **Marking alone cannot finish the job on this platform.** macOS has no
/// `pipe2`, so a pipe is born unmarked and there is always a moment, two system
/// calls wide, when a fork elsewhere would take it. Measured with SwiftTerm
/// forking alongside: marking took 115 servers in 200 down to 1, not to none.
/// This lock closes that moment. `startProcess` forks synchronously, before it
/// returns, so holding the lock around every terminal's start and around every
/// pipe's making-and-marking leaves no instant for one to land inside the other.
///
/// What no lock of ours reaches is a descriptor some framework opens on its
/// own; those are on their author, as #719 says these are on us.
nonisolated enum Forking {
    private static let lock = NSLock()

    /// Runs `body` with no terminal able to fork meanwhile. Start every terminal
    /// inside one of these; make pipes with `Pipe.marked()`, which does.
    static func exclusively<T>(_ body: () throws -> T) rethrows -> T {
        try lock.withLock(body)
    }
}

nonisolated extension Pipe {
    /// A pipe with both ends close-on-exec, made where no terminal can fork
    /// between its making and its marking — **the only way this project makes a
    /// pipe.** A bare `Pipe()` is handed to every terminal opened while it lives.
    ///
    /// Marking the ends `Process` hands to its child is safe: it puts them on 0,
    /// 1 and 2 with `dup2`, whose copies are not marked, so the child still gets
    /// its standard streams. `Process` itself does not leak — it spawns with
    /// close-on-exec as the default, and four hundred servers started together
    /// held none of each other's pipes — so it needs no lock of its own.
    static func marked() -> Pipe {
        Forking.exclusively {
            let pipe = Pipe()
            for end in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
                _ = fcntl(end.fileDescriptor, F_SETFD, FD_CLOEXEC)
            }
            return pipe
        }
    }
}
