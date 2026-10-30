# The engine: how its rules were found

Moved here word for word from `CLAUDE.md`, which keeps each rule in a line or
three and links to the story it came from. They stand in the order they stood
there, so "above" and "below" mean in this file, unless a story names a rule
that stayed in `CLAUDE.md`.

## Async that does not move

**An `async` wrapper over a `nonisolated` engine function does not move the
work anywhere.** `HostStore.sshConfigHosts` was `async` and awaited
`Core.sshConfigHosts`, which is `nonisolated` — so the file read ran on the
main actor exactly as if it had been called directly, while four call sites
wrote `await` and looked like they were yielding. The compiler says so
(*"no 'async' operations occur within 'await' expression"*), and that
warning is worth reading rather than silencing: it is the difference
between work that is off the main thread and work that merely looks it.
Dropping the keyword changed no behaviour. Moving that read off the main
thread would be a change to `Core`'s isolation, not a keyword in `Model/`.
The same warning on `await self.settle(...)` inside `Task { [self] in }` is
a different thing and equally harmless to fix: a `Task` made inside an actor
inherits its isolation, so members need no await there. **But check which
closure you are in** — the nested `Task { await self.progress(...) }` sits
inside a `@Sendable` closure, which has left that isolation, and its await
is real. The compiler flagged one and not the other, correctly.

## What SwiftTerm leaks

**SwiftTerm leaks every descriptor not marked close-on-exec into every
terminal's child**, and it made the new suite hang for a minute. Its
`PseudoTerminalHelpers.fork(andExec:)` calls `forkpty` and goes straight to
`execve` without closing anything, and `Pipe()` descriptors are not
close-on-exec, so a shell forked anywhere in the process — the local-shell
test, mid run — holds a copy of whatever pipes happen to be open. A real
server whose input it inherited never sees that input end, and
`waitUntilExit()` cannot be interrupted, so the run learned only *"Time limit
was exceeded"* on whichever test was tearing down. Measured with SwiftTerm
forking alongside: **115 servers of 200 still running a second after their
input closed when inheriting, 1 with the pipes marked close-on-exec** — and
the inheriting arm saw nine times the forks, because its stuck stops each
waited the full second, so scaled for exposure about 13 would be expected
where there was 1.
**The 1 was not noise**: macOS has no `pipe2`, so a fork landing between
`Pipe()` and the `fcntl` still inherited. Marking narrows that race and only
`Forking`'s lock, further down, closes it. `RealSFTPServer.stop` stays
bounded anyway — it ends the server itself after five seconds — because a
teardown should never be able to hang a run, whatever opened the descriptor.
`Process` itself does not leak this way: 400 servers started together held
none of each other's pipes.
**The same leak was in the app, and is fixed now.** Every terminal's `ssh`
inherited whatever the app had open when it forked: an SFTP session's pipes,
and — for the app's whole life — `HostStore`'s watch descriptor on the host
list. Closing a session could not hang on it, since `SFTPClient.close()`
terminates its child rather than waiting for input to end; the exposed path
was `connect`'s handshake-failure branch, which reads `ssh`'s stderr to its
end, and a terminal forked in the wrong window would have held that read
open for as long as the terminal lived.

## Close-on-exec

**Every descriptor this project opens is close-on-exec, and which calls
already are was measured rather than assumed:**

    Pipe()                          inherited — make it with Pipe.marked()
    open(_, O_EVTONLY)              inherited — add O_CLOEXEC
    dup()                           inherited — use fcntl(_, F_DUPFD_CLOEXEC, 0)
    FileHandle(forReadingAtPath:)   already close-on-exec
    FileHandle(forWritingAtPath:)   already close-on-exec

**`Pipe.marked()` is the only way this project makes a pipe** — the one bare
`Pipe()` left is inside it, and the other is `InheritanceTests`' control,
on purpose — and every pipe in the app and the suite goes through it, the
harnesses' as well, because a
test pipe inherited by the local-shell test's forked shell misbehaves in a
way that is easy to misread: `SFTPFarEndTests`' broken-pipe case would still
have *passed*, since a pipe with a reader somewhere gives no `EPIPE` and the
request deadline then throws an `SFTPError` of its own thirty seconds later.
**The `dup` from the stall fix was the first thing to need correcting**: a
plain `dup` is never marked, so the copy made to stop one descriptor
outliving its owner was handing every terminal a fresh copy of what had just
been marked. Write `F_DUPFD_CLOEXEC`, which is what SwiftTerm itself uses.
`Tests/InheritanceTests.swift` forks exactly the way a terminal does and asks
the child, through `/dev/fd`, whether a descriptor reached it. It has a
**control** — an unmarked pipe must be seen to arrive — because a probe that
could never see inheritance would pass with the fix taken out. Checked that
way round: with `closeOnExec` marking nothing, both ends of the marked pipe
are reported inherited and the control still passes.
**Upstream knows, and is not going to fix it soon.** SwiftTerm #716, open
since 2026-09-26, describes this exact hang — *"a shell inherited another
test's pipe writer, and that test waited for EOF until the run was killed"*
— and fixes it in the child with `POSIX_SPAWN_CLOEXEC_DEFAULT`, which is also
why children `Process` starts do not leak. The maintainer declined it:
posix_spawn *"breaks all sorts of other things"*, from Swift Subprocess,
where it had to be reverted. #719, merged and inside the 1.99.0 this builds
against, marks SwiftTerm's *own* private descriptor and treats the rest as
the host's job — which is what this project now does. `main`'s `Pty.swift`
is byte-identical to 1.99.0's, so no version bump helps. Checked
2026-10-27; look again before treating the window as permanent.
**So the window is closed here, by a lock: `Forking`, in
`Core/Descriptors.swift`.** `startProcess` forks synchronously, before it
returns, so holding one lock around both of `TerminalSession`'s starts and
around every pipe's making-and-marking leaves no moment for a fork to land
in between. That is why `Pipe.marked()` makes the pipe as well as marking it:
a helper that only marked could be called with the lock not held.
**Closed by construction, and the measurements agree rather than prove
it.** At matched exposure — 1,500 servers and 480 forks in each arm — a
fork outside the lock still caught 3 servers' input, and under it, none.
Those counts are too small to carry the claim by themselves; the
construction carries it.
What *is* proven is the wiring, which is the part that could silently rot.
A start that skipped the lock would look exactly like one that took it —
the shell comes up either way — so `TerminalSessionTests` holds the lock
from another thread and checks that each start **waited**, the local shell
and `ssh` (to `127.0.0.1` port 1) both, since they are two separate calls.
Checked the way round that matters: with both starts taken out of the lock,
both tests fail at once.
The cost was weighed and taken: `Terminal/` now depends on a lock in
`Core/` to close a race two system calls wide. And no lock of ours reaches
a descriptor a framework opens on its own — that stays on its author, as
#719 put ours on us.

## Writing to a descriptor

**`FileHandle.write(contentsOf:)` raises an ObjC exception, and `send`'s
`catch` cannot catch it.** `SFTPClient.send` wraps its write in a `do`/`catch`
meant to turn a dead far end into *"the file session stopped listening"*, and
that block is **dead code**: writing to a closed or broken handle raises
`NSFileHandleOperationException`, which is not a Swift error, so it sails past
that `catch`, past the `try?` in `list`'s
`defer { Task { try? await self.closeHandle(handle) } }`, and terminates the
process. It killed a whole run this way. `list` leaves that close unawaited, a
test's `defer { server.stop() }` closes the client's own `toServer` underneath
it — `stop()` closes `clientToPeer.fileHandleForWriting`, which *is* that
handle — and the orphaned close then writes to a closed descriptor **after
every test has already passed**. So swift-testing reported 158 tests passed
and the run still came out failed, the crash in the tail with no test named
and no `✘` anywhere: read only the test counts and it looks like a pass.
The shipped consequence is the same shape, and worse: an `sftp` child that
dies mid-transfer leaves a broken pipe, which is precisely what that `catch`
was written for and precisely what it cannot do. **Fixed, in both halves —
and the halves are the lesson.** `send` writes with `Darwin.write` on a
descriptor taken once in `init`, which only returns: `EBADF` for a closed
one, `EPIPE` for a far end that has gone, so that `catch` runs for the first
time. But `Darwin.write` **alone made it worse**. A write to a pipe nothing
is reading raises **SIGPIPE**, whose default disposition ends the process, so
a crash that at least printed a reason became one that printed **nothing** —
and that is the worst death to read here, because xcodebuild says only
*"Restarting after unexpected exit, crash, or test timeout"*, relaunches, and
totals both launches, so a run can come out **green with a crash inside it**.
`fcntl(fd, F_SETNOSIGPIPE, 1)` settles it, per descriptor rather than
`signal(SIGPIPE, SIG_IGN)`, which would be a decision about the whole app
taken inside one file session. Measured both ways: with the flag a
reader-less pipe gives `write == -1` and `errno == EPIPE`; without it the
process is gone and its buffered `stdout` with it, which is why the first
probe printed nothing at all and briefly read as a failed build — measure a
process that dies by signal on **stderr**.
**`ScriptedSFTP` had the identical bug**, and it only showed once `send` was
clean, because `send` was crashing first: its reader thread answered through
`try? outgoing.write(contentsOf:)` — the mirror side of the same race, since
`stop()` closes that end underneath the thread — so the suite went on dying
about one run in six with the engine already correct. Both write through a
descriptor now, and **nought exceptions in ten runs** says so. The moral is
cheap: when a mechanism like this is understood, `grep` for every
`write(contentsOf:` at once rather than fixing the one the stack named.
**There are none left.** The third, `SFTPTransfer`'s download writing
arriving bytes into the local file, went the same way — a full disk raises
exactly as a dead pipe does, so it would have crashed where it meant to
report a failed download. The loop itself now lives **once**, as
`SFTPClient.writeAll(_:to:failing:)`, with both the packets going out to
`ssh` and the bytes coming down into a file calling it: two copies of a
three-condition loop, one of whose conditions exists only to stop it
spinning, is how the harness's copy survived the first fix. Note the
download takes `out.fileDescriptor` **once**, while the handle is certainly
open, because asking a closed `FileHandle` for its descriptor raises the
very same exception as writing through one — capture it late and the bug is
back somewhere new.
`Tests/SFTPFarEndTests.swift` pins both ends, and they fail differently
enough that one does not cover the other: a closed handle returns `EBADF` and
raises no signal, so pinning only that case would have shipped a fix that
looked verified while the path that matters — a dying `sftp` child — still
took the app down.
Whether any of this was also the sixteen-minute hang above: **no.** The hang
still reproduces with the crash fixed and no exception anywhere, so they are
two bugs, not one.

## The tree

**Every walk over the group tree lives in `Model/Tree.swift`**, built once
per snapshot: the lookups and indexes `HostStore` used to hold, the descent
in `hostsBeneath`, and the two climbs — `path`, for the "Production / EU"
breadcrumb, and `ancestry`, for the groups that must be open before a row
can be reached. `HostStore` keeps the current one and delegates; the sidebar
reads `store.tree` rather than walking anything itself.
**The reason they are together is the cycle guard.** Each of those three
walks carried its own, against a group that became its own ancestor — a
thing only a bad edit or a corrupt store produces, which is exactly why
nobody would ever have noticed the guards rotting. They hang the app rather
than draw a wrong row, so the suite now turns a loop through all three.
Note which end each climb starts from: a **host** needs its own group open
and everything above it, while a **group** needs its parents and not
itself, because a group's own fold is its business.

## YAML that is not YAML

**A YAML file that is not YAML used to read as an empty one, in every
release up to 0.1.0.** `Yams.load_all` throws only when a parser cannot
be made at all; a scan error while reading — an unclosed quote, a tab
where an indent belongs — is caught by the sequence it returns, kept in
its `error`, and the sequence simply ends. `Config.parse` and
`Portable.parse` both read with `try load_all(…).compactMap { $0 }`, so a
broken `config.yaml` came back as a config that set nothing and a broken
import as a document with nothing in it, said nowhere — the outcome both
functions' own comments call the one worth ruling out. A second document
that broke was dropped the same way, behind the very guard that refuses a
second document. Both read through `Core/YAMLDocuments.swift` now, which
drains the sequence by hand and throws what it kept, so they say "this is
not valid YAML" with Yams's own line and column. **Found by a control,
not a report**: the issue form's test, broken on purpose, came back "not
a mapping" rather than a YAML error, and the expression behind that was
the one both readers used. Checked the way round: with the line that asks
the sequence for its error taken out, the four not-YAML tests fail and
the empty-file and two-document ones still pass.

## The settings file

**A settings file that could not be used was ignored without a word, in
every release up to 0.1.0** — and not only a broken one: an unknown key
and an option ssh would refuse too, the very refusals `Config.parse` is
written to make loudly. The app read it once, at launch, with
`try? Core.configure(…)`, so the error went nowhere and the app ran
without the file's ssh options and palettes. The fix above made
`Config.parse` throw for broken YAML and changed nothing anybody could
see; tracing where that error lands, while writing 0.1.1's notes, is what
found this. `LaunchConfig.read` keeps the problem now, and the window says
it through its one alert — in state of its own, because a refresh that
works clears `store.lastError` and the first one lands just after the
window opens. **The sweep of every `try?` passed over this one**: a `try?`
whose fallback is a plausible value — here, the path it was asked for —
reads as handling a failure rather than dropping it.
The tests read only files that fail, since one that works would set the
ssh options of every connection the rest of the suite makes beside them;
with the old `try?` put back, only the two problem tests fail. **Driven on
screen on 2026-10-30**: a scratch copy opened with `open -g` and an
unclosed quote in its settings put up the alert, Yams's line and column
and all, and AXPress on its one button took it down — SwiftUI's buttons
publish no name to System Events, so it was pressed for being the only
one. The file is still read only at launch, which the alert and the
Settings caption both say.

## Stderr

**Reading ssh's stderr waits for the child to die, so let the client go
first.** `connect`'s catch read `errors.fileHandleForReading.readToEnd()`
*before* closing, and that read ends only at an end of file, which comes only
once ssh has gone. It worked for the failure it was written for — a child
that had already exited saying "Permission denied" — and was a **hang** for
the two that leave ssh alive: a far end answering with a version this cannot
speak, and now a handshake given up on. The close comes first. The proven
path is untouched for a reason worth keeping rather than tidying: `close()`
returns early once `ended` is set, and that is precisely the case where the
child is gone and its own sentence is the one worth reporting.

## Nonisolated

**A rule type lifted into `Views/` is MainActor unless you say otherwise,
and so is the enum it works on.** This catches **test helpers too**:
`Tests/` is compiled into the app target, so a class there picks the default
up exactly as one in `Views/` does, and `ScriptedSFTP` needed `nonisolated`
for the same reason `PaneTab` did. Three separate times in one day, with it
already written down — so if you are writing a type a test will touch,
start it `nonisolated`. The app target defaults to MainActor, so
`Panes`, `QuickConnect` **and `PaneTab` itself** all picked it up, which
made even `PaneTab`'s `Equatable` conformance actor-isolated and unusable
from a `nonisolated` test. Nothing in the app ever notices, because every
caller is already on the main actor; the first test that looks from outside
fails to compile. Mark them `nonisolated`, the enum included — it took
three compiles to walk that chain down.
