# The suite: how its rules were found

Moved here word for word from `CLAUDE.md`, which keeps each rule in a line or
three and links to the story it came from. They stand in the order they stood
there, so "above" and "below" mean in this file, unless a story names a rule
that stayed in `CLAUDE.md`.

## The suite's harnesses

That matters because of what it replaces. Three shell harnesses once covered
this — the terminal on a real pty, the window from store to sidebar, SFTP
against a loopback server — and went with the loopback servers and the flags
the app published for them. They are in the pre-reset bundle, 532 lines across
six files, and restoring one costs three things the code size does not show: a
**Go toolchain** as a prerequisite (`spike/go.mod` wants Go 1.26 with
`creack/pty`, `gliderlabs/ssh` and `pkg/sftp`); flags that are gone
(`--seed`, `--selftest`, `--uicheck`, `--scratch`, `--hold`, `--ssh-key`,
`--ssh-port` — though `--db` and `--config` are **still** accepted); and, for
the window one, features that no longer exist, since it logs in with a
password, exercises copy-id and drives snippets. Worst of all, `--uicheck` was
not external driving at all: the app checked **itself** and wrote a JSON
report, so restoring it means test-only code back inside the shipping binary.
Driving from outside costs the app nothing, which is why this is the shape to
extend rather than the bundle.

A **local shell on a real pty** is covered too: it opens one and asks the
shell itself where it started. **SFTP against a real server is covered now**,
and without the Go server this paragraph used to call the honest answer:
`/usr/libexec/sftp-server` is the binary `sshd` execs at the far end of every
`ssh -s sftp`, it speaks the protocol on stdin and stdout, and
`SFTPClient.speaking(to:from:)` was already the seam for exactly that — no
toolchain, no network, no keys, no `sshd`. **And `ssh` itself is covered
now**, in `Tests/SSHTransportTests.swift`, without the bundle's Go server:
macOS's own `/usr/sbin/sshd` runs as you, not root, on `127.0.0.1` and a free
port, with keys made for each test in `TestScratch`. Each test gets a server of
its own, read-only, for as long as it runs. It drives the real
`SFTPClient.connect` — the argv `SSHArgs` builds, `ssh -s sftp`, `begin` — and
covers what that path does for real: a session that lists and downloads
600 KB byte for byte; a key the server will not take, which comes back as
ssh's own *"Permission denied"* through the stderr branch that once had to let
the client go first; an unknown host key refused with *"Host key verification
failed"* and nothing written; and a jump host gone **through**, proven by two
logins in `sshd`'s own log where a bypass would show one. It needs nothing
switched on — Remote Login stays off, since this is a server of its own, and
the firewall cannot prompt for Apple's signed `sshd`. One line in its log looks
alarming and is not: *"BSM audit: setaudit_addr failed"* is a non-root process
refused an audit session, and the login goes through regardless.
**Every connection is kept off its user's own `~/.ssh`, and that is most of
the care the suite takes.** `connect(_:fixed:)` takes extra settings nothing
may override; the app passes none, and the suite passes
`LocalSSHD.isolation`: `-F /dev/null`, so `~/.ssh/config` and every `Host *`
in it — a `ProxyCommand`, a `ControlMaster`, a `Match exec` that runs a program
— is never read; `UserKnownHostsFile` in scratch with `GlobalKnownHostsFile`
off; `StrictHostKeyChecking=yes` and `UpdateHostKeys=no`, so a broken isolation
fails at the door instead of writing a key anywhere; `IdentityAgent=none` and
`IdentitiesOnly`; and control sockets off. Because `fixed` leads every hop,
the jump's own `ssh` gets all of it too — and the jump test passing **proves
it did**, since the hop could only have verified the server against the
scratch known_hosts: the real one has never heard of that port or that key.
**Two settings are left out on purpose.** `fixed` leads, so `ProxyCommand=none`
would beat the very `ProxyCommand` that `SSHArgs` spells a jump with, and
`ClearAllForwardings` could take the hop's `-W` with it; `-F /dev/null`
already keeps out every forward a config holds.
**Checked from outside the suite, not only from inside it:** `~/.ssh/known_hosts`
had the same size and modification time before and after a full run with
`SSHArgsTests` changing the global options alongside, and `~/.ssh` gained and
lost nothing — the last test checks the same, every run. And checked the way
round that matters **without touching `~/.ssh`**: stripping the isolation to
show it matters would have made `ssh` read your files, which is the one thing
this suite promises not to do, so the check made `SSHArgs` skip the hop
instead — and the jump test failed with *"sshd let somebody in 1 times"*.
**One gap this turned up, closed since:** the test host sent the *store* to a
scratch path under XCTest but still read the **real** Shellhand config,
`~/Library/Application Support/Shellhand/config.yaml`, whose ssh options become
every connection's global options. There was no such file, so it was harmless
that day; a config with a `ProxyCommand` in it would have reached every
non-jump connection this suite makes, since `isolation` cannot set that keyword
without breaking jumps. `LaunchOptions` sends the config to scratch now, the
way it sends the store — see the note on the test bundle being hosted.
**And the terminal over real `ssh` is covered too**, in
`Tests/TerminalOverSSHTests.swift`, against the same server running a forced
command — it says it is ready, once, and waits — so nothing of yours runs
interactively, and logging in quietly, with no last-login line and no message
of the day, so the screen holds exactly what the test chose. A real login
reaches connected; a refused one **never reads as connected, even for a
tick** — 0.0.5's blank-screen promise held against the thing it was for, ssh
sending its own complaints to `-E` so the screen stays blank; OpenSSH's own
host-key question is seen with its fingerprint; and answering it both ways is
checked, the key landing in scratch on a yes and nowhere on a no. **Its first
run found a real bug**, recorded beside the wrapped-question one.

## Scratch paths

**Every scratch path in the suite goes through `Tests/TestScratch.swift`**,
which keeps **one root per run** and removes it with `atexit`. Before that
each test made its own directory in the temporary one and left it there for
ever: a day of runs left **4,843 directories and 185MB**, which is harmless
right up until somebody goes looking for where the disk went. There were
**nine** such sites across **eight** files, every one with its own
hand-rolled `NSTemporaryDirectory() + "prefix-\(UUID())"`.
The shape was picked for the size of the diff. A `defer` per test meant
editing dozens of call sites; class suites with `isolated deinit` — which is
the idiomatic swift-testing teardown, and available, since `TerminalSession`
already uses one — meant turning eight structs into classes. Routing the
helpers instead changed **one line each and no call site at all**. `atexit`
is known to fire in this test host, not assumed: a temporary probe printed
from one earlier. A crash skips it, so the worst case is one directory per
run rather than one per test — and this suite does crash sometimes, so that
matters. **No test makes a scratch path of its own any more; they all go
through `TestScratch`.** The symbol itself appears once more, in
`LaunchOptionsTests`, which asserts that a path *is* under the temporary
directory rather than making one there — checked, because a convention
stated more broadly than it holds is one nobody can follow.
Two things to know before sweeping that directory by hand. The prefix
`shellhand-ssh-` is **both** kinds: `SSHConfigFileTests` left *directories*
and a running app writes `shellhand-ssh-<uuid>.log` *files* for live
sessions, so sweep by `-type d` or you delete the log a session is still
writing to. And `shellhand-under-test` is **not** litter — it is the store
`LaunchOptions` sends an XCTest run to, one directory reused, which is the
only reason a run does not open the real list.

## The hosted test bundle

The test bundle is **hosted by the app**, so running the suite launches it.
With no `--db` that opened and migrated the real host list. `LaunchOptions`
sends a run under XCTest to a store in the temporary directory; keep it that
way, and check the real store's timestamp if you ever touch that code. It
is the only reason `LaunchOptions` reads the environment at all.
**The config goes to scratch the same way**, and for a reason as large: its
ssh options become every connection's, so a run reading the real one would
take whatever is written there — a `ProxyCommand` included — into every
connection the suite makes to its own `sshd`. Nothing writes the scratch
config, and a missing one reads as empty, so a run's ssh options are none.
`--db` and `--config` still win when named; `window-check.sh` relies on the
first. Touching this code was checked as the note above asks: the real store
kept its size and modification time across a full run, and the real config,
absent before, was still absent after. `LaunchOptionsTests` pins the
decision rather than the files, so neither real file is touched to check it —
and its config test compares the path *actually read*, because the empty
path that means "the default" would have let the obvious comparison pass
with the redirect taken out. It did, the first time.

## A copy in the way

`xcodebuild test` launches the app, so **a second copy of the same bundle
stops the suite before it starts**: it fails with "Failed to send resume to
target process", `** TEST FAILED **`, and `Executed 0 tests` — which reads
like a broken test run rather than a launch that never happened. Build the
copy you want to look at to a derived data path of its own and quit it before
testing.
**The rule is narrower than "a copy is running", and 0.0.6 showed how
much.** `brew install --cask shellhand` leaves a copy at
`/Applications/Shellhand.app` for good, and the suite has passed with it
merely sitting there — but it has now also passed **twice with that copy
running**, 421 tests each time, having just updated itself underneath. So
what stops a run is not any live Shellhand: it is one launched from the same
build products the test host wants, which is the copy you have been looking
at in `-derivedDataPath`. Quit that one; the installed copy can stay, open
or shut.

## A copy beside the run

**A copy running from the build products did *not* stop a suite run**, which
is narrower than this file has been claiming. The note above says what stops
`xcodebuild test` is "one launched from the same build products the test
host wants — the copy you have been looking at in `-derivedDataPath`".
Today a copy from exactly that path was running, with a live `ssh` under it,
and the run came back **539 passed**. So that is not the condition, or not
the whole of it. What *is* still true is that **`window-check.sh` cannot
run beside another copy** — System Events addresses a process by name and
two make every lookup ambiguous — and that refusal is the thing to work
around, by addressing the copy by its **`unix id`** rather than by name.

## HostStore

**`HostStore` is testable because every call carries its own `db:`.**
`Core.shared` is a singleton actor, but nothing about it is pinned to one
database — `snapshot(db:)`, `save(db:…)` and the rest take the path per
call, so a `HostStore(dbPath: <temporary file>)` reaches nothing of the
user's and needs no fake. `Tests/HostStoreTests.swift` uses that, and the
rule it most wants covered is `move(group:toParent:)` refusing a group into
its own descendant: that is the write that would create the very loop the
guards in `Tree` exist to survive.
Check the real store's timestamp after touching any of this. It is one
`stat` and it is the only thing that proves a run stayed in the temporary
directory — the suite opened and migrated the real host list once already.

## Host and Foundation

`import Foundation` in a test file makes **`Host` ambiguous** with
`Foundation.Host`, so `Tests/ValidationTests.swift` deliberately does not
import it. If something there needs `UUID`, give it a literal id instead.
The other way out, where the import is genuinely needed — `TerminalSessionTests`
writes an ssh log to disk — is to spell the app's own type `Shellhand.Host`,
exactly as `SwiftUI.Group` is spelled out elsewhere. Leave the comment on the
import saying why, or the next person deletes it and the file stops building.
