# CLAUDE.md

Shellhand is a native macOS SSH client: the host list, tabs on real `ssh`,
and files over SFTP, in a window. It is Swift all the way down, and it
keeps its own list.

`docs/architecture.md` has the shape of it and the traps worth knowing before
touching anything.

This repository is public, under GPL-3.0-or-later: `LICENSE` holds the licence
and `README.md` is what a visitor reads. `docs/name-and-pricing.md` has the
name and what is still to decide about selling it.

## How it fits together

`Shellhand/Core/` is the engine: the store, the inheritance resolver, the argv
builder, the config, YAML and `ssh_config`, and SFTP. Everything above it —
`Model/`, `Terminal/`, `Views/` — goes through `Core`, an actor holding the
store connection and the sessions, runs and transfers that outlive the call
that started them.

The list lives in SQLite at `~/Library/Application Support/Shellhand/`,
through GRDB. A YAML export is how a list moves between machines: plain text
meant for a dotfiles repository, naming things rather than carrying ids.

## Build & test

```bash
xcodegen generate               # after adding or removing a file, or editing project.yml
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project Shellhand.xcodeproj -scheme Shellhand -configuration Debug \
  -destination "platform=macOS" -derivedDataPath build -skipPackagePluginValidation
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Shellhand.xcodeproj -scheme Shellhand -configuration Debug \
  -destination "platform=macOS" -derivedDataPath build -skipPackagePluginValidation
```

`Tests/` is the whole suite. It covers `Core/`, and the rules lifted out of
the layers above it: `Model/Tree.swift` (what is under what, what is above it,
and the fold the sidebar opens on), `Model/Places.swift` (what a file pane
calls itself, what it shows and how it names a child),
`Views/Panes.swift` (which tab is in front,
what is beside it, what ⌘D and closing a tab do), `Views/QuickConnect.swift`
(what ⌘K offers for what was typed, and where an arrow moves the highlight),
`Views/SidebarRows.swift` (the sidebar flattened into one list, and what the
search field narrows it to),
`Sessions.shortTitle`, `Terminal/HostKey.swift` (whether ssh is waiting to be
told about a host key, and which part of the screen is the question),
`Terminal/SessionProgress.swift` (what a session's state becomes given what is
on its screen) — driven both as a rule and against a terminal fed by hand, with
the real watchdog running over it — `Model/Files.swift`'s own orchestration
(the guard that keeps a pane from re-opening, and the replace question with a
copy genuinely parked on its continuation), the SFTP
conversation — against a server written in Swift in this process, **and against
OpenSSH's own `sftp-server`**, which ships with macOS — the `ssh` layer itself
against macOS's own `sshd`, kept off your own `~/.ssh`, and
`HostStore` itself — its writes, moves, tag
rewrites and imports, driven against a scratch database through the same code
path the app runs.

**One thing checks the app end to end: `scripts/window-check.sh`.** It seeds a
store of its own, launches a real window against it with `--db`, and drives the
sidebar through System Events the way somebody on the keyboard does — the tree
folded as it comes up, then opened with the arrow keys, then a row picked and
the **Host** menu read back to prove the selection reached the app rather than
only the outline. It asks the app for nothing it does not already publish:
`--db` is the whole of it.

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

The app icon has tooling of its own, because an Icon Composer bundle cannot be
judged by reading its SVG — the squircle, the gradient, the shadow and the
specular are added by macOS when it is composited:

```bash
python3 tools/icon.py Shellhand/Resources/Shellhand.icon   # rewrite the bundle
./tools/icon-preview.sh /tmp/shellhand-icon                # render it small
```

`docs/app-icon.md` says why the format and the mark are what they are.

A release is `scripts/release.sh`, which builds, signs, notarizes, packages and
rewrites the appcast and the cask — and **publishes nothing**, printing the two
commands that would. `--skip-notarize` runs everything that needs no
credentials, which is most of it.

## Layout

- `Shellhand/` — the app. `App/` (entry, menus, settings), `Core/` (the
  engine), `Model/` (the cached store, the file browser), `Terminal/` (a
  session: `ssh` on a pty through SwiftTerm), `Views/`.
- `Tests/` — the suite. Hosted by the app target, so
  `@testable import Shellhand` reaches the engine.
- `tools/` — `icon.py`, which writes the icon bundle, and `icon-preview.sh`
  with `RenderIcon.swift`, which render it at the sizes that decide it. Not
  checks: `icon.py` is where the mark's geometry lives, so it is the only way
  to change the icon at all.
- `scripts/release.sh` — the whole of a release, from `xcodebuild` to the cask.
- `Casks/shellhand.rb` — the Homebrew cask, copied into the tap on release.
- `appcast.xml` — the update feed, served from `main`. Generated, never
  hand-edited.
- `docs/` — the architecture, the Phase 0 measurements, the engine comparison,
  the app icon, and the name.

## Conventions

- The sources are in `Shellhand/`, not `shellhand/`: the disk is
  case-insensitive.
- `-skipPackagePluginValidation` is needed because SwiftTerm 1.99 carries a
  build plugin Xcode otherwise asks a human to trust.
- **Port forwarding is gone, and tmux with it.** It was built, and in weeks of
  real use the host list held **zero** rules — while it was the only reason
  this app needed tmux installed at all. Cutting it removed an install
  prerequisite, a "needs tmux, which is not installed" warning, a socket-path
  length problem, and `SHELLHAND_TMUX_SOCKET` from every harness. The store's
  `forwards` table is dropped by migration **v6** rather than by editing v1:
  migrations are append-only, and every store in existence has already run v1,
  so rewriting history would leave those stores with a table the migrator
  thinks it never made. **Don't bring it back without a reason from someone
  other than us.**
- **No Docker and no external hosts.** This held when there were harnesses —
  anything needing a server ran `gliderlabs/ssh` in-process on loopback — and
  it still binds anything added later. A check that reaches someone else's
  machine is not a check.
- **Keys, credentials and snippets are gone, cut back to an MVP.** With them
  went the three managers and the Library tab, the Credential record and
  `credentialId`, `startup` on a host and a group, generating a key, putting
  one on a host (`CopyID`, `Runner`), and the askpass helper and keychain —
  so **this app no longer answers a password prompt**. A host that takes only
  a password still connects in a **session**, because ssh asks on the pty
  where it can be typed, exactly as in Terminal.app; but `SSHArgs.unattended`
  fixes `BatchMode=yes`, so **Files cannot reach such a host** at all. That is
  the one capability the cut costs. What stayed is `identity` on a host and a
  group: that is a plain `-i`, inherited like `user` and the jump host, not
  the Keys manager. If any of it comes back, the pre-reset bundle has it;
  don't bring it back without a reason from someone other than us.
- **The cut left two engines behind with nothing calling them, and they are
  gone now too.** `Core/Command.swift` ran a program and collected what it
  said, for the script `Runner`; `Model/Shell.swift` did a smaller version of
  the same, for listing a key's fingerprint. Both outlived their callers by
  weeks — 192 lines referenced by nothing, not their functions, not their
  nested types, not a test. They are in this repository's own history, in the
  root commit, so recovering them needs no bundle. That makes two leftovers
  the cut produced, counting `LibraryView`: it took the features and their
  windows out and left a couple of their engines standing.
  **Three things in `Command` are worth more than the code was**, for whenever
  something has to run a program again. Read the output **as it arrives**, not
  after the program ends: a pipe holds about 64 KiB, and a command that fills
  it blocks for ever waiting to be read while the reader waits for it to exit
  — a deadlock that only shows up on the one command that is chatty enough.
  A `readabilityHandler` runs on **a queue of the pipe's choosing**, so the
  lock around whatever it appends to is not optional. And a child stopped from
  here ends with a status that is **not a verdict** on what it was running, so
  cancelling has to be recorded separately from failing.
- **A sweep for declarations nothing calls found four more, and `checkPort`
  made five.** `Portable.hostPort`, `Portable.splitAddr`, and the `checkPort`
  that only `splitAddr` could reach, were the whole of *"what a document has
  to hold"* — 42 lines of IPv6-bracket address parsing whose own comment said
  *"as a forward writes them"*, left behind by the port-forwarding cut.
  `Sessions.closeAll()` and `Core.transferStatuses()` went with them: 51 lines
  in all, no callers, not even a test. That is a third round of leftovers
  after `Command`/`Shell` and `LibraryView`, so what is worth keeping is the
  habit rather than the finding: every method declared under `Shellhand/`,
  counted against every mention of its name anywhere in the app or the suite.
  379 functions, 11 with no other mention — and **seven of those eleven are
  framework conformances**, SwiftTerm's delegates, `QLPreviewPanelDataSource`,
  `Layout`, `FileDocument`, so the sweep needs a list of what the system calls
  or it reads as a massacre.
  **Swept again after 0.0.9: 392 functions, 15 unmentioned, and all 15 are
  framework.** `LocalProcessTerminalViewDelegate` takes three
  (`sizeChanged`, `hostCurrentDirectoryUpdate`, `processFailedToStart`),
  `NSViewRepresentable` six across three types, `NSWindowDelegate` two
  `windowWillClose`, and `QLPreviewPanelDataSource`, `Layout` and
  `FileDocument` the rest. So the cut-era leftovers really were all cleared
  and nothing has re-accumulated, today's thirteen new functions included —
  which is the first time this sweep has come back with nothing to delete.
  Check the **conformance**, not the name: that is what turns fifteen
  alarming-looking declarations into zero findings, and it is the whole
  difference between this sweep and a massacre.
  **`closeAll()` is the one worth a sentence, because deleting it is the
  non-obvious call.** It looked exactly like `FilesModel.close()` — a
  close-everything method nothing called — and `TerminalSession.deinit` only
  removes the notification observer, so closing the host window looked like it
  would orphan every `ssh` the same way. It does not, for two reasons that
  both had to be read rather than assumed: the watchdog captures `[weak self]`
  and returns once that is nil, so no task holds the session alive, and
  SwiftTerm's own `LocalProcess.deinit` escalates SIGTERM to SIGKILL on the
  child. A released session really does take its `ssh` with it. **Don't add a
  call to it on the strength of the Files bug** — the two look alike and are
  not the same.
- ssh options are ordered by how specific they are, because ssh keeps the
  **first** value it is given for a setting: what a caller must not have
  overridden leads, then the host's own, then each
  group going up, then the config's, which apply to everything. A setting
  written against one machine beats the default written for all of them.
  Within one call, options passed as `extra` still come after the config's.
- Swift 6 language mode, the app target MainActor by default. The engine is
  `nonisolated` throughout — mark extensions of its types `nonisolated` too, or
  their members pick the default back up.
- **An `async` wrapper over a `nonisolated` engine function does not move the
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
- `deinit` is **nonisolated**, so a MainActor class cannot touch its own
  stored properties there — write `isolated deinit` rather than reaching for
  `nonisolated(unsafe)`. A block-based notification observer needs one: the
  centre holds the block until the token is handed back, and `weak self` only
  stops the object being pinned, not the block from piling up per tab.
- The test bundle is signed with the project's own Developer ID. A plug-in
  loaded into a hardened-runtime app must share its team, and an ad-hoc signed
  one is refused at `dlopen`.
- Rules about the data — what stops a record being saved, what deleting takes
  with it, which groups could hold another — live in `Core/Validation.swift`,
  not in the sheet that shows them. A rule in a view can only be tested by
  driving the view, and this app's dialogs do not answer to `click at`.
- **The same rule now applies upward, not just to data.** `Views/Panes.swift`
  and `Views/QuickConnect.swift` hold decisions that used to be `private`
  inside `ContentView` and `QuickConnectSheet`: which tab is in front and what
  is beside it, and how ⌘K ranks what you typed. They keep no state — the
  views still own that and simply obey — so the whole of each behaviour is
  reachable from a test with a couple of values and a list. Quick Connect
  especially: driving the real palette is how a session to a live machine got
  opened during a check, which is a high price for testing a sort.
  **`Views/Browsing.swift` is the third, and the one that reads as redundant
  until you meet its bug** — the same shape as the trade in `Panes.picking`.
  It answers one question: where the host pane is **looking**, which is not
  what is selected.
- **The host pane shows the list, always; the inspector says what a host is.**
  The pane used to swap itself for the selected host's details, so selecting a
  host made the list vanish — you could never click down it, and the thing
  you had just picked was the only thing you could no longer see in context.
  The details went to the inspector, which now opens by default
  (`@AppStorage("hostInspector")`): with nowhere else for them to be, a window
  that came up shut would answer a click on a host with nothing anywhere.
  **`HostDetailView` lost its `compact` flag with that**, and the flag's whole
  reason went with it: there were two shapes so the same view would not be
  drawn twice, and there is only one place a host is described now. The ssh
  line stayed despite the measured note that it wraps at 300pt — the column
  goes to 420, `Copy` sits in its header where length cannot push it below the
  fold, and the alternative to a wrapped line is not having it anywhere.
  **Rows became `List(selection:)` content rather than buttons**, because
  "selectable" has to mean more than clickable: a button could be clicked and
  nothing else, so the keyboard reached nothing and a row drew the same
  whether or not it was the one selected. Grid mode keeps its buttons — a
  `LazyVGrid` has no selection — and draws the highlight by hand, with a ring
  as well as a wash, since a tint alone reads as a hover across a page of
  cards.
  **Scope and selection had to come apart, and that is `Browsing`.** They were
  one `Selection`, which is an either/or: the pane took `selectedGroup`, nil
  whenever a host is selected. Harmless while picking a host replaced the
  pane; with the list staying up it would have widened to every host and
  moved the row out from under the click that picked it. A group is a
  **place**, so picking one goes there; a host is a **thing**, so picking one
  moves nothing. **One exception, which the sidebar forces:** its tree holds
  hosts as well as groups, so it can select a host the pane is not showing —
  which would be a selection with nothing highlighted anywhere while the
  inspector described it, reading as a click that failed. The pane follows to
  where that host is, and nothing moves when it is already on screen, which is
  every click inside the pane itself.
  **Do not collapse `browsing` back into `Selection`.** It reads like a
  redundant second value and it is the only thing keeping the list still.
- **The SFTP conversation is checked against a server written in Swift, in
  this process** — `Tests/ScriptedSFTP.swift`, on a pair of pipes, reached
  through the one seam `SFTPClient.speaking(to:from:)`. The spikes once ran a
  real loopback server and it is still in the pre-reset bundle, but it is
  **Go**, with a module of its own, so restoring it would make a Go toolchain
  a prerequisite for `xcodebuild test` in a project that is otherwise Swift
  all the way down — and it came tangled with a spike UI inside the app, 798
  lines of it in `ContentView` alone.
  The better reason is that a real server is **well behaved**, and what had
  never been exercised is the handling of one that is not: a server answering
  a read with fewer bytes than its own `stat` promised, or sending a reply to
  a request nobody made. Neither can be asked of a real server; both are a
  line here. What it gives up is real — it answers from this project's idea
  of SFTP, so a misunderstanding shared by both ends goes unnoticed, and
  `SFTPWireTests` pinning the encoding separately is what makes that bearable.
  Do **not** call `close()` on a client made through that seam: its `Process`
  was never started, and terminating one that never ran raises.
  **A directory ends when the far end says EOF, never because a batch came
  back empty.** `list` filters `.` and `..` *after* reading each batch, so a
  directory holding nothing else yields no entries while still having more to
  come — inferring the end from an empty result would stop early and look
  right in every ordinary case. The scripted server can send exactly that
  batch, and does.
- **Both suites that reach that server carry a one-minute time limit, and an
  observed hang is why.** A run wedged for sixteen minutes on *"a directory
  that arrives in pieces is joined, in order"* and had to be killed by hand,
  having reported nothing at all. A stack sample taken while it was still
  stuck showed both pipe reader threads idle in `read`, **no cooperative-pool
  threads at all**, and so a continuation in `SFTPClient.waiting` that nothing
  was ever going to resume. Nothing was merely queued, either: with the pool
  idle an enqueued `deliver` would have run, so the reply either never came or
  arrived and was dropped.
  It went **unexplained for weeks**, and it is **episodic rather than
  steady**, which took far too long to see. **It is explained now, and the
  cause was this harness rather than the engine** — the resolution is a few
  bullets down; what follows here is the history, which is still worth
  reading for how long it took and why. Three sightings in all: one on its own, then two
  inside a single batch of ten, and then **49 runs with none** across four
  batches — two with a probe compiled in, two without. So "about two in ten"
  was the wrong model: the stalls cluster in time and nothing in the build
  predicts them.
  **The trap that follows is worth more than the bug.** A clustered failure
  read as a steady rate makes any clean batch look like proof of something.
  Two probes were called heisenbugs on exactly that reasoning — 0 stalls in 31
  instrumented runs, p ≈ 0.001 *if* the rate were really 0.2 — and then 8
  **uninstrumented** runs came back clean too, which killed the story. The
  arithmetic was fine; the model under it was invented. **Conclude nothing
  about this hang from a clean batch, however long.**
  And it **roams**: three sightings, three different tests — *"a
  directory that arrives in pieces is joined, in order"*, then *"an empty file
  goes up as an empty file"* over in the transfer suite, then *"a directory
  that arrives in one go"*. That last is the **minimal** conversation, one
  opendir and one readdir and EOF, so every theory about batching, about the
  EOF rule, about a long exchange is dead: whatever this is lives in what all
  of them share — `client()`, `speaking(to:from:)`, `startReading`, and the
  first packets over a fresh pair of pipes. Shared mutable state, the
  register-before-write order in `send` (which is correct: `waiting[id]` is
  set synchronously on the actor before the write) and a collision with the
  handshake's id 0 (`nextRequest` starts at 1) are each ruled out. Note what a
  sample
  cannot tell you here: the handshake and the readdir loop look identical from
  outside, both just a blocked reader thread, so the log line naming a test
  proves only which test **started**.
  Ruled out since, each with real work behind it: the reassembly loop both
  ends run is **correct** under one-byte reads and awkward splits, slices with
  a non-zero `startIndex` included, so mis-framing is not it; **no other test
  stalls** — 382 started and 381 finished in every log, stalled and clean
  alike, the only gap being XCTest's own `run` — so the process is healthy and
  exactly one conversation is orphaned while the suite carries on around it;
  and `strays` is **always** exactly 1, by design, since `SFTPTransferTests`
  builds a server with an `intruder` and asserts that very number, so it is no
  sign of anything.
  One tooling note, because it cost an afternoon: `sed`'s `\|` alternation is
  a GNU extension and does **nothing** in BSD `sed`, silently. It turned a test
  that had plainly passed into a phantom *"never finished"*, which read as hard
  evidence that the whole process was stalling. Parse these logs with something
  that fails loudly instead.
  **And which `sed` you get now depends on where you type it.** The shell
  profile aliases `sed` to `gsed` (GNU 4.9), where `\|` works — but an alias
  exists only where the profile is read, so in a script `sed` is still
  `/usr/bin/sed`, BSD, where it matches nothing. A line tried at the prompt and
  then pasted into a script changes meaning without a word: measured
  2026-10-27, the same pipe matched two lines typed and none under `bash -c`.
  The reverse bites too, since GNU's `-i` takes no separate suffix, so the BSD
  spelling `sed -i ''` fails at the prompt by reading `''` as the script.
  `release.sh` is safe because it names `/usr/bin/sed` outright; anything new
  that edits files should do the same, or not use `sed` at all.
  **`paste` is aliased too, to `pbpaste`, and that one leaks.** A check
  piped through `paste -sd' ' -` to join two lines printed a fragment of the
  **clipboard** instead — a wrong answer, and someone's clipboard landing in
  a log, found during 0.0.7's dry run. Same cure: `/usr/bin/paste` by path.
  The general rule both aliases teach is to run `type <name>` before
  trusting any short command in a shell that reads the profile; this one has
  quietly replaced two.
  So the limit is not a fix, it is what makes the next one cheap: a named
  failure instead of an unbounded wait. **It really does interrupt this, and
  that was worth checking rather than assuming**: a time limit works by
  cancelling the test's task, `withCheckedThrowingContinuation` is **not**
  cancellation-aware, and cancelling a task parked on one does not resume it —
  so the trait could have compiled, read perfectly and still wedged on the one
  case it was added for. It does not. Checked with a client on pipes nobody
  serves, the exact shape of the real failure: swift-testing recorded *"Time
  limit was exceeded: 60.000 seconds"*, failed that test by name, and let the
  run **finish**. `.timeLimit` takes only
  `.minutes`, so one minute is the floor, and `SFTPWireTests` has none because
  it only encodes and has nothing to wait for.
- **An SFTP request has a deadline now, and the app needed one more than the
  suite did.** The stall above was bounded only in `Tests/`: `send` parks on a
  continuation that the reply or `finish` resumes, and `finish` fires only when
  the pipes break or the child dies — neither of which is true of a far end
  that has simply stopped answering. So the shipped shape of that hang was a
  file pane stuck on "Connecting…" **that could not even be retried**, because
  the guard on `FilePlace.opening` is cleared in a `defer` a parked request
  never reaches. `SFTPClient.Deadline` is 30 seconds for an ordinary reply and
  **120** for the handshake, and the gap is deliberate: the handshake waits for
  ssh to resolve a name, reach the host, cross a jump chain, authenticate and
  start a subsystem, and nothing here sets `ConnectTimeout` — so ssh's own
  patience is the system's TCP timeout and can run past a minute, and a host
  that is merely slow must still fail with ssh's sentence rather than this one.
  Only the one request fails: a missing reply has not cost the conversation its
  place, since packets are length-prefixed, and `ended` is deliberately left
  unset because `close()` does nothing once it is set, which would leave the
  `ssh` child running with nothing left to end it. The message **names the
  request**, which is the whole point — 49 clean runs could not say which one
  stalls, and the next sighting will say so in a line, at 30 seconds rather
  than the suite's limit at 60.
  Pinned three ways in `Tests/SFTPDeadlineTests.swift`, and checked the way
  round that matters: with the watchdog taken back out, the unanswered test and
  the stray test both come back *"Time limit was exceeded: 60.000 seconds"*,
  while **"a far end that answers is not given up on" still passes** — which is
  exactly what that third one is for. A deadline that fired unconditionally
  would satisfy the other two and break every transfer this app makes.
  **And it paid for itself on the first full run after it landed.** The stall
  came back — *"a directory that arrives in one go"*, the same test as the
  third sighting — and this time it said what it was: *"the far end did not
  answer readdir within 30.0 seconds"*. That is the first thing anyone has
  known about which request stalls. It looked at the time as though it ruled
  out the first packet over a fresh pair of pipes — `speaking(to:from:)` does
  no handshake, so that conversation is `opendir` then `readdir`, and `readdir`
  is only sent once `opendir` has been answered. **That inference was wrong**,
  and the reproducer below is what showed it: `opendir` stalls at least as
  readily. One sighting named one request, and concluding anything about the
  shape of the bug from it was the very mistake this file already warns about
  twice. The immediate re-run was clean at 420, so it is still episodic and
  that number still proves nothing.
  **The thing to ask is `lateReplies`**, which exists for this and nothing
  else. A reply nobody is waiting for used to be a stray whatever it was;
  `deliver` now asks whether its id is one `giveUp` recorded, so after a
  timeout `lateReplies == 1` says the answer was merely slow and `0` says it
  never came — which separates "the far end never answered" from "the answer
  was lost between the reader thread and `deliver`", and nothing has ever been
  able to tell those two apart. It also stops the ordinary case of a slow
  server raising an alarm about framing, since `strayReplies` is now only ever
  an answer to a request nobody made, which really does mean the conversation
  has lost its place. `SFTPTransferTests` asserting exactly 1 stray is
  unaffected: its `intruder` was never given up on.
  **But it is not automatic capture, so do not expect it to be.** The counters
  are read after the fact and a failing test is gone by then; what they buy is
  that re-running the stalled test with a longer deadline and watching
  `lateReplies` is now a question with an answer. Which test to re-run is
  whichever one last named a request — and that has now been the same one
  twice.
  **Two of five full runs on 2026-10-27 stalled, both in *"a directory that
  arrives in one go"*, both naming `readdir`.** Before the deadline it had
  been seen in three different tests and looked as though it roamed; it may
  simply be that nothing could say where it was. **Read no rate into that** —
  this file already records a batch of ten with two stalls and then 49 runs
  with none, and the lesson was that the clustering is real while the
  arithmetic built on it was invented. What the two sightings do say is that
  the minimal conversation is where to look — which is what the reproducer
  below was built out of.
- **The stall has a reproducer now: about one conversation in 2,500.**
  `Tests/SFTPStallHunt.swift`, **disabled**, runs the minimal conversation
  20,000 times with 16 in flight and a five-second deadline on each: roughly
  six stalls in seven seconds, where a suite run bought one sighting every few
  runs. Enable it when there is a theory to test; it fails by design, which is
  why it is not a check.
  What it establishes, each measured rather than reasoned:
  - **The reply never arrives.** `lateReplies` and `strayReplies` are both 0
    after half a second's grace, every time. So it is neither a slow answer nor
    one delivered against an id nobody holds.
  - **Concurrency is not what provokes it.** 40 stalls in 100,000 sequential
    conversations, 8 in 20,000 concurrent: the same rate either way.
  - **It hits `opendir` — the first request — at least as often as `readdir`**,
    which is what refuted the inference above.
  - **Bytes go missing in both directions**, and this is the sharpest clue.
    Two shapes turn up: `saw=[] sent=0`, where the server never received the
    request at all, and `saw=[11] sent=1`, where it received it and wrote the
    answer with no error and the client never saw it. A fault in either side's
    own logic would not do both.
  - **The server's reader thread is always still blocked in `read`**, never
    broken out, so an interrupted read mistaken for an end of stream is ruled
    out there. Worth saying because the loop does look wrong: neither reader
    handles `EINTR` while both writers do.
  **The cause is still not established.** The obvious candidate is a reader
  thread holding a raw descriptor *number* while the `FileHandle` that owns it
  can be deallocated and that number handed out again — the same family as the
  `write(contentsOf:)` bug, a descriptor outliving its owner. **It is
  untested.** The experiment that would have tested it, retaining every pipe so
  no number is recycled, ran the process out of descriptors instead and
  recorded 18,734 `EBADF` writes: that tests `Pipe()` failing and nothing else,
  so it is evidence for neither side.
  And note what none of this reaches. This is `ScriptedSFTP` on a pair of
  pipes, churned far harder than the app ever churns a session. If the fault is
  the harness's own, it would explain every sighting so far and leave the
  shipped engine innocent — but that is a possibility, not a finding.
- **The descriptor-reuse theory was tested and the test was flawed. Read this
  before designing the next one.** The theory: a reader thread holds a raw
  `Int32` while the `FileHandle` owning it can be deallocated and that number
  handed out again, so an orphan goes on reading a pipe that now belongs to
  somebody else. The design was to record, per conversation, whether either
  read descriptor had belonged to a conversation whose reader thread had not
  yet ended, and to report that against whether the conversation stalled —
  with the conversations that did not stall as the control, since in a
  churning run *every* conversation reuses numbers and a bare reuse count
  proves nothing.
  **Two traps sank it, and both are properties of the question rather than of
  this attempt.** Knowing that a thread has ended means waiting for it to end,
  and waiting is itself the intervention — the arm that can measure the clash
  is the arm that has removed the chance of one, so the clash column came back
  0 everywhere, including where it mattered. And deriving liveness from the
  old object instead means **holding** that object, which keeps its pipes open
  and so prevents the very reuse being measured. Observation and intervention
  are entangled here; a design that separates them needs the thread to publish
  its own exit through something that does not keep the pipes alive.
  What the counts said, for whoever picks it up: **0 stalls in 40,000
  conversations with a wait for the server thread, and 7 in 40,000 without** —
  across two runs each. Suggestive, and **not** a conclusion: the no-wait arm
  gave 6 in one run and 1 in the next, a sixfold swing, which is the same
  clustering that has already turned small clean batches into a story twice in
  this file. Many alternating runs, or none.
  **What was worth doing regardless** turned out to be the whole of it, on
  one side. Both reader threads — `SFTPClient`'s and `ScriptedSFTP`'s — held a
  bare descriptor number whose lifetime belonged to somebody else, the same
  hazard class as the `write(contentsOf:)` bug a `FileHandle` could not
  report. Giving each thread a `dup` of its own, closed by the thread when it
  leaves, was done as hygiene and turned out to settle the stall as well —
  though only the harness's half did. See below.
- **The stall is explained: it was this harness, not the engine.**
  `ScriptedSFTP`'s reader thread borrowed the pipe's read descriptor by
  **number**, which is all a thread can hold. Churn thousands of conversations
  and the `FileHandle` owning that number is deallocated while the thread is
  still parked in `read`; the number is handed to the next pipe, and an
  orphaned thread reads somebody else's conversation. That is the one thing no
  single-sided fault could account for — bytes going missing in **both**
  directions — because either reader can be the orphan.
  Measured as a 2x2, every arm in one sitting on one machine, which is what
  makes this believable where the earlier arithmetic was not:

      harness   engine    stalls per 20,000   a run took
      borrows   borrows   6, 1                ~7s
      borrows   dup       2, 2                ~7s
      dup       borrows   0, 0                ~2.1s
      dup       dup       0, 0, 0             ~1.9s

  **11 stalls in 80,000 conversations whenever the harness borrows, 0 in
  100,000 whenever it holds a `dup`** — and the engine's own descriptor makes
  no difference to either row. The wall clock agrees independently and for
  nothing: a run drops from about seven seconds to about two, because the
  five-second waits are gone.
  **So the shipped engine was innocent all along**, which is worth saying
  plainly after weeks of suspecting it. Every sighting was the suite's own
  server losing bytes; no user was ever going to meet this, and nothing about
  it needed a release.
  `SFTPClient.startReading` holds a `dup` anyway. That is **hygiene and not
  the fix** — the table says so — kept because a thread holding a number whose
  lifetime belongs to somebody else is a trap the next change around it should
  not have to rediscover.
  `Tests/SFTPChurnTests.swift` is the guard, and a real check now rather than a
  hunt: 20,000 conversations in about two seconds, which fails at 11 in 80,000
  with the harness's `dup` taken back out.
  **The lesson that survives** is not about descriptors. What made every
  earlier clean batch worthless was the absence of a baseline measured in the
  same sitting — 49 clean runs said nothing because nobody knew that week's
  rate. Two arms an hour apart on one machine said everything. When something
  is episodic, spend the effort on a reproducer before spending any on a
  theory.
- **The SFTP conversation is held against OpenSSH's own server too**, in
  `Tests/SFTPRealServerTests.swift`, and the reason it exists is the paragraph
  above: `ScriptedSFTP` answers from this project's idea of the protocol, and
  it was itself wrong for weeks. A reference implementation cannot share a
  misunderstanding. It is **proven to catch one**: with `opendir` planted as
  99 instead of 11, every scripted listing test still passed — the harness
  decodes with the same enum the client encodes with — while the real server
  refused it. It refused **silently**, too, sending no status at all, and the
  request deadline is what turned that into *"did not answer opendir"* rather
  than a hang.
  Two things that cost nothing to get wrong and a lot to get wrong later:
  **`-d` names where the server starts and is not a jail** — it runs as you,
  with all of your access, so every path is absolute and under `TestScratch`,
  and every test that only reads passes `-R` as well. And OpenSSH sends **at
  most 100 names per `readdir`** (250 files arrive as 100, 100, 52), so the
  several-batches test is the end-of-directory rule against batching the client
  did not choose.
  The suite meets the server through `SFTPClient.begin()`, the half of
  `connect` that runs once there is a far end — the handshake and finding home
  — so it gets the same opening the app makes rather than a test's idea of one.
  `setHome` went with that change, having no other caller.
- **SwiftTerm leaks every descriptor not marked close-on-exec into every
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
- **Every descriptor this project opens is close-on-exec, and which calls
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
- **Reading ssh's stderr waits for the child to die, so let the client go
  first.** `connect`'s catch read `errors.fileHandleForReading.readToEnd()`
  *before* closing, and that read ends only at an end of file, which comes only
  once ssh has gone. It worked for the failure it was written for — a child
  that had already exited saying "Permission denied" — and was a **hang** for
  the two that leave ssh alive: a far end answering with a version this cannot
  speak, and now a handshake given up on. The close comes first. The proven
  path is untouched for a reason worth keeping rather than tidying: `close()`
  returns early once `ended` is set, and that is precisely the case where the
  child is gone and its own sentence is the one worth reporting.
- **`FileHandle.write(contentsOf:)` raises an ObjC exception, and `send`'s
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
- **An empty file could not be carried, in every release up to 0.0.3.**
  `download` read "`stat` said zero" and "`stat` would not say" as the same
  number — `attributes?.size ?? 0` flattens **two** optionals, since the size
  is absent whenever the protocol's flags omit it — and then `done == 0` had
  to treat both as failure. A zero-byte file came back `0 of 0 bytes arrived`,
  so lock files, `.keep` and a freshly rotated log were all uncarryable. The
  size is an optional now, and a size the server did give must match exactly,
  zero included. Found by the first test that could reach it.
  **The two directions are not symmetric, and that is deliberate.** `upload`
  has no closing check at all: every write is acknowledged by the far end, so
  a partial upload would need a server that ACKs bytes it did not keep, and
  nothing arriving is simply an empty file — which is why the bug could only
  ever have been on the download side. Both halves are pinned now, so they
  cannot quietly drift into agreeing.
- **An empty folder could not be carried down either, in every release up to
  0.0.7** — the empty file's sibling, found the first time anything tested
  folders at all. `downloadDirectory` and `uploadDirectory` run whenever a
  folder is dragged between the panes, and **nothing called either** until
  `Tests/SFTPFolderTests.swift` held them against OpenSSH's own server.
  Every *file* came through byte for byte both ways — nested two deep, a
  dotfile, a file of no bytes, 600 KB across several pipelined windows — so
  the transfers were sound. Folders were not: `walk` collected files only, and
  a folder was made only as the parent of a file about to land in it, so any
  folder with no file beneath it at any depth was never made. Every empty
  folder in a tree was left out, and **an empty folder downloaded as nothing
  while the transfer reported success** — `downloadDirectory` returned
  without throwing, so `Core` settled the job as done. Uploads made each
  folder they met, so the directions disagreed and a round trip lost them.
  Now `walk` records folders too, and the destination and every folder are
  made before any file is written. **The fix has two halves and each fails
  its own test taken out:** without the destination made first, only the
  empty top-level folder is lost — nested folders make it anyway, as a side
  effect of `withIntermediateDirectories` — while without nested folders
  recorded, the whole-tree and round-trip tests fail and the empty one passes.
  **And the same silent shape was left on the upload side, chased since.**
  `uploadDirectory` made each folder with `try?`, half of it on purpose —
  carrying a folder onto one already there merges rather than fails, so an
  upload cannot insist on making every folder — and it swallowed a real
  refusal with it. A folder with files under it surfaces that through the
  files' own failures; an **empty** folder whose `mkdir` was refused vanished
  with the job reporting done, which is the download bug wearing the other
  direction's clothes. `makeFolder` now tolerates a folder already there and
  throws everything else.
  **The status cannot tell those apart, and that was measured rather than
  assumed.** SFTP 3 has no "already exists" — it arrived in version 4 — so
  OpenSSH answers a name already taken with plain `SSH_FX_FAILURE`, exactly
  what it gives a read-only disk: with the tolerance removed the control came
  back `SFTPError(message: "Failure", status: .failure)`. So the far end is
  **asked** instead, the way `remove` asks what a path is before choosing its
  request, and the original error is what gets thrown, not the `stat`'s, since
  it carries the far end's own sentence.
  **Three tests, each failing its own arm taken out**, and the refusals are
  real rather than scripted — `-R` is OpenSSH's own read-only mode. With the
  destination's `mkdir` swallowed again, only the read-only case fails; with
  each folder's swallowed, only the case where a **file** stands in the
  folder's place fails; and with `makeFolder` tolerating nothing, only the
  control fails — a folder carried twice onto itself. That control is the
  point: a fix that merely stopped swallowing passes both refusal tests and
  breaks every upload this app makes.
- **A symlink is carried as a symlink now; the two directions used to disagree
  three different ways.** Found by reading the transfer path straight after
  the folder fixes, and measured with a probe rather than reasoned:
  `downloadDirectory` **skipped** links outright, while `uploadDirectory`
  turned a link to a file into a **copy of its target's bytes**, a link to a
  folder into an **empty folder** on the far end, and a **dangling** link into
  nothing at all. None of it was reported and none of it was tested, so a
  round trip could not give back the tree it took.
  **The cause was one call.** `fileExists(atPath:isDirectory:)` **follows** a
  symlink, so a link to a file looked like a file and a link to a folder like
  a folder — while `FileManager`'s enumerator does **not** descend through
  one, which is why that folder stayed empty; and a dangling link looked like
  nothing there at all. `attributesOfItem(atPath:)` is `lstat` and answers the
  question actually being asked, reporting `.typeSymbolicLink` for all three.
  Worth remembering as a pair: one follows, the other does not.
  **The policy is to carry the link and not what it points at**, both ways —
  the target string copied verbatim, relative or absolute, resolved or
  dangling, nothing followed. That is also what spares both sides a loop
  guard, which following would have forced: a link pointing at its own
  ancestor is a name to copy, not a branch to descend. It is what `rsync`
  does without `-L`, and it is what makes a round trip exact. It does mean a
  link whose target is not carried too arrives dangling, which is faithful
  rather than wrong.
  **It needed two opcodes this did not speak** — `readlink` (19) and
  `symlink` (20) — and one carries a trap only a real server could settle:
  **OpenSSH reads `SSH_FXP_SYMLINK`'s two paths in the opposite order to
  draft 02**, target first. The test reads the link back off the server's own
  disk rather than through the protocol that wrote it, because a reversed pair
  looks consistent to `readlink` and is wrong to everything else. Checked the
  way round that matters: with the draft's order the server answers plain
  `SSH_FX_FAILURE`.
  **The test's own oracle had the same bug**, which is this file's recurring
  lesson in a new place: `snapshot` used that same following `fileExists`, so
  a carried link and a carried copy were identical to it and no assertion
  could have told them apart. It asks `lstat` now. Each half fails its own arm
  taken out — download skipping links fails the download and round-trip tests
  while upload still passes; upload following them fails the upload test on
  **all three** counts at once, links, files and folders, which is the whole
  of the old bug in one line.
  **And both directions check for cancellation while making folders and
  links**, not only while moving bytes: a deep tree used to be unstoppable
  until the first file started.
- **A rule type lifted into `Views/` is MainActor unless you say otherwise,
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
- **A local shell starts at home, and it took a user to notice.** A forked
  shell inherits the app's working directory, and an app launched the ordinary
  way — LaunchServices, from the Dock or Finder — has `/`: confirmed on a
  running copy, `lsof -d cwd` said `/`. So New Local Shell opened at the root
  of the disk for every release up to 0.0.5. `startProcess` takes
  `currentDirectory:` and always did; nothing was passing it.
  **The test for it asks the shell**, which is the only answer that cannot be
  wrong: it sends `pwd > <file>` and reads the file. The oracle is deliberately
  the filesystem and not the screen — reading the terminal back would depend on
  what SwiftTerm's accessibility exposes and on the user's own prompt, neither
  of which is the test's business. It is also the first real pty in the suite,
  which is a thing the three removed harnesses were supposed to be for, and it
  needs no server: 0.47s, no Go, no network, no external host.
  Checked the way round that matters: with the fix removed the test says *"the
  shell started in /, not /Users/cuonggt"*. A test for a bug that passes
  without the fix is worth nothing.
- **`Sessions.shortTitle` has a pure overload** taking the host's name and the
  title, with the `TerminalSession` one calling it. A session builds a 900×560
  terminal view and registers a notification observer, which is a lot of
  machinery to stand up in order to check where a string gets cut.
- **`HostStore` is testable because every call carries its own `db:`.**
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
- **A file pane's derived values live in `Model/Places.swift`**, because a
  `FilePlace` only reaches its states by connecting to something: asking "what
  does a pane pointed nowhere call itself" would otherwise mean opening an
  SFTP session to find out. `FilePlace` and `ReplaceQuestion` delegate.
  `isLocal` is the one worth knowing about. It reads like a label and is not:
  `FilesModel` hands it to `Replacing.clashes` as `caseInsensitive`, because
  this disk is and a server's usually is not. And an **unpointed** pane is not
  local — the same `chosen` flag that stops it calling itself "This Mac" —
  so the three states are pinned rather than the two that are obvious.
- **`Model/Files.swift`'s orchestration is testable because a local pane needs
  no session.** `Core.list` reads this disk when the session id is empty, so
  both sides can be pointed at directories of ours and local-to-local copying
  — a real thing this window does, not a contrivance — drives the whole path
  through the same code the app runs: no server, no fakes, no fixture.
  That reaches the two pieces worth holding still. The **open guard** is
  pinned by pointing a pane where it already is and finding it still there:
  without the guard every re-entry walks to the home directory again, and what
  that cost was worse than a wasted walk — two opens went through together and
  a download landed in the wrong folder *with the job reporting success*. The
  **replace question** is driven by starting the copy in a `Task` and not
  awaiting it, waiting for `asking` to appear, checking the destination still
  holds its old bytes, then answering. Cancel is the one that matters: the test
  asserts the copy **returns at all**, because a copy waiting on a question no
  longer on screen does not overwrite anything, it waits for ever.
  **Do not walk `parent()` up out of a temporary directory.** The first version
  of that test went up into the system temporary directory and spent **nine
  seconds** listing every other process's leavings — slow, and at the mercy of
  what happens to be in there. Make a parent of your own with one child in it:
  0.013s, and `path == parent` with one named entry is a stronger claim than
  "some ancestor" was.
- **`FilePlace.opens` exists so that one open can be told from two.** The
  guard on `opening` is all that stops two calls in flight at once becoming
  two connections, and it has no other outward sign — once both have finished
  the state looks identical either way, which is exactly how the bug went
  unnoticed. `ticks` on a terminal session is there for the same reason.
  **Do not try to catch the window by polling.** The first attempt started one
  open in a `Task`, waited for `connecting` to appear, then called `use` again
  — and a refused connection on loopback is quicker than any poll, so the
  first had *finished* before it could be seen and the second was a sequential
  retry measuring nothing. The diagnostic said so in one line: `opens=1
  chosen=true host=nil failure=…Connection refused`. What works needs no
  timing at all: make **both tasks before either runs**, and actor
  serialisation does the rest, since whichever goes first cannot be
  interrupted before its `await` and so arrives there with `opening` set. It
  holds whichever order they run in, so it leans on no scheduling guarantee.
  The failed attempt was worth something anyway — it showed that a **retry**
  after a failure is allowed and must stay allowed, because the failure resets
  `host` to nil, which is how somebody fixes a mistyped port and tries again.
  That has a test of its own now.
- **Every scratch path in the suite goes through `Tests/TestScratch.swift`**,
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
  matters. **Nothing under `Tests/` calls `NSTemporaryDirectory` any more
  except `TestScratch` itself**; a convention with one exception is one nobody
  follows.
  Two things to know before sweeping that directory by hand. The prefix
  `shellhand-ssh-` is **both** kinds: `SSHConfigFileTests` left *directories*
  and a running app writes `shellhand-ssh-<uuid>.log` *files* for live
  sessions, so sweep by `-type d` or you delete the log a session is still
  writing to. And `shellhand-under-test` is **not** litter — it is the store
  `LaunchOptions` sends an XCTest run to, one directory reused, which is the
  only reason a run does not open the real list.
- **Every walk over the group tree lives in `Model/Tree.swift`**, built once
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
- Menus live in `Shellhand/App/Commands.swift` and reach the front window
  through `AppActions`, a focused scene value. Keyboard shortcuts belong there
  rather than on a button.
- **A menu is named for what its items act on**, and that is also what gates
  them: **Host** needs one selected, **Terminal** needs a session in front.
  The app menu's own two, Hosts and SFTP, need nothing. One menu called "Host" had grown to nineteen
  items — connecting, editing, deleting, copying, four unrelated dialogs and
  two snippet submenus — which is not a menu about hosts, it is everything
  that did not fit in File. A whole menu greying out together says more than
  items greying out one by one inside a menu about something else.
  **There is no Library menu.** It held Keys, Credentials, Snippets and
  Files; the first three were cut, and rather than leave a one-item menu
  called Library the last one moved to the **app menu** as SFTP, beside a
  Hosts item, above Settings. That is the user's shape, asked for directly.
  Worth knowing if it is ever revisited: macOS keeps the app menu for About,
  Settings, Hide and Quit, and "bring a window forward" normally lives in the
  Window menu, which lists it already.
  **And nothing is called Library any more either.** `LibraryView` outlived
  the concept by weeks — it is the pane beside the sidebar showing the host
  list, whole or filed under a group, so it is `HostsPane` now, with
  `HostsLayout`, matching `TerminalPane` and `FilesPane`. The sweep that found
  it also cleared the other cut-era words, and they are all deliberate:
  `credential` and `snippet` in `Portable` keep old exports importable,
  `forwards` in `Store` is the append-only v1 migration, and `forwardAgent` is
  a live setting. **The one exception is `@AppStorage("libraryLayout")`**,
  which keeps its old name for the same reason
  `setFrameAutosaveName("FilesWindow")` does: it is where the existing
  preference lives, and renaming it resets everybody's choice silently. This
  machine's was set to `grid`, so that was not hypothetical.
- Text size sits in **Terminal**, not View: "Bigger Text" in a View menu does
  not say bigger than what, and these size the terminal and nothing else.
- **The toolbar is placed by the same rule as the menus** — by what each item
  acts on. Quick Connect, New Host and **Files** start something that is not
  about whatever the pane is showing, so all three sit over the sidebar; the
  inspector toggle acts on the pane, so it sits alone at its **trailing
  edge**, where macOS keeps a window's actions and where it mirrors the
  sidebar toggle opposite. All five used to sit over the sidebar together.
  Files spent a while at the trailing edge beside the inspector toggle, on the
  reasoning that it "acts on the host selected". **It does not** — it is
  ungated, and opened with nothing selected the far pane asks which host (the
  same reason it is not in the Host menu). So by this rule's own test it
  belongs with the things that start something, and the pane toolbar is the
  one item that is really about the pane. Keep `paneToolbar` even at one
  item: each column needs its own `.toolbar` or the detail's items land
  against the divider, whatever placement they are given.
- **It is called SFTP, everywhere**: the app menu, the toolbar, a row's menu,
  the window's title and the Settings pane. It was "Files" and was renamed at
  the user's word. The argument for "Files" is on the record and lost: the
  window is two panes and the left one is *this Mac*, so local-to-local
  copying is part of what it does and is not SFTP at all. **Don't re-argue
  it.** If anything is still called Files, that is a spot the rename missed —
  except `setFrameAutosaveName("FilesWindow")`, which must **not** change, or
  every saved window frame is lost.
  Its icon is `arrow.left.arrow.right` rather than a folder, because the
  toolbar draws icons only: a folder reads as "a folder on this Mac", while
  two arrows say *between*, which is the window's whole shape.
- **Connect is not in the toolbar.** It was the one item that appeared and
  disappeared with the selection, so every button to its right slid sideways
  as you clicked down the list — what a width that jumps between sheets does
  under the pointer. It was also the third copy of it — and the three are
  now the **inspector**, under the host's own name; the Host menu's ⌘↩; and
  **⏎ or a double-click in the list**, which is where the hand already is
  once you have arrowed to a row. The toolbar is still not one of them, and
  the reason has not changed.
- **Each column carries its own `.toolbar`**, and that is the whole trick.
  `listToolbar` hangs off the sidebar view and `paneToolbar` off the detail
  view, inside the `NavigationSplitView`'s two closures — not one `.toolbar`
  on the split view itself. Hung off the split view the detail's items land
  hard against the divider **whatever** you do: `placement: .navigation` puts
  them on the detail side but at its leading edge, `.primaryAction` is *not*
  the trailing edge and measured at x=316 back beside the sidebar toggle, a
  `ToolbarSpacer(.flexible)` does not expand, and nor does a plain `Spacer`
  inside the group. Give the detail view its own toolbar with
  `.primaryAction` and the items measure at 1636 and 1679 in a 1728pt window,
  which is the right edge.
- **Measure the toolbar, do not trust the placement names.** Its buttons
  publish `AXHelp`, so walking the window's `AXToolbar` and printing each
  button's x against the window's width says where they really are — and it
  needs no clicking, so unlike most of this app's UI it is checkable from a
  script.
- **Shellhand ▸ SFTP opens the window**, and carries ⌘B.
- **Hosts is the one menu item that cannot go through `AppActions`.** That is
  a focused scene value, nil whenever the host window is not in front — which
  is exactly when "bring the host list forward" has a job, so the item would
  grey out at the only moment it is wanted. `HostsWindow.front()` asks AppKit
  instead, finding the window by an identifier that `TagsHostsWindow` sets
  from behind `ContentView`. It is the one window this app does not make
  itself, so there is no controller holding it.
  **SFTP has the same problem and half the same answer.** *Opening* a browser
  needs the store the host window holds, so that still goes through
  `AppActions` — but *fronting* one that already exists does not, and
  `FilesWindowController.front()` does it without a store. The menu item tries
  that first, which is what makes ⌘B work from inside the SFTP window, where
  `AppActions` is nil and the shortcut used to do nothing at all. What is left
  inert is narrow: ⌘B with **no** browser open *and* the host window not in
  front — from Settings, say. Bring the host list forward and it works.
- Two `.disabled` on one menu item **compose**, so both have to be true for it
  to be usable. "Delete Group…" carried one on `hasGroup` and a second on
  `hasHost`, which meant deleting a group needed a host selected as well.
- **New Group… lives in File**, beside New Host… and Import… — it makes
  something rather than acting on what is selected, so it is not in Host.
  It does read the selection, though: a group selected means the new one goes
  inside it. So the item **says where it will land** — "New Group Inside
  Production…" — rather than leaving you to open the editor and read its
  parent picker. An item that quietly does two things has earned a longer
  label. The sidebar's own version can say just "Inside" because the row it
  came from names the group; the menu bar has no row, so it names it.
- **A menu on a row acts on that row**, and a group's menu is handed the
  group rather than reading it back out of the selection. "New Host…" there
  called the same plain action the File menu does, so the one item in a
  group's menu that made something made it at the top of the list instead,
  while "New Group Inside…" directly below it nested. `newHostIn` takes the
  group, which also means ⌘N in the File menu still makes an unfiled host —
  two items that look alike must not quietly become one action.
- A file session is opened **once** per pane, guarded by a flag set before the
  first await. Checking only whether the session exists let two opens through
  together: the second one's walk to the home directory landed after the first
  had navigated away, so a download went to the wrong folder with the job
  reporting success. The `.task` that used to re-run on every tab switch is a
  window's now and runs once, but the guard stays — it is cheap, and what it
  protects against is a race rather than a particular way of re-entering.
- **The sessions open are a strip of tabs across the top of the terminal**,
  and the sidebar is the host list and nothing else. Standing them on end at
  the bottom of the sidebar was built instead and taken out again at the
  user's word: it is their window and they run the sessions in it.
  What the column was answering is answered in the label instead: a tab is as
  wide as what it says, so it does not say what the shell sent. It shows
  `Sessions.shortTitle` — the machine and the tail of the path — capped at
  180pt and **truncated in the middle**, because the two ends are the two
  things that say which session this is (`prod-api-cha…/current/public`); cut
  either end off and two tabs on one machine look alike. The whole title is
  on the tab's tooltip and in its accessibility label, so nothing is lost.
  If the strip ever fills anyway, shorten it further — don't move the
  sessions back to the sidebar.
- The strip is **not there at all when nothing is open**, so a fresh install
  sees the window it has always seen.
- **`Sessions` does not say what is on screen, and must not be asked.** It
  had a `current` meaning "the session whose id is selected", which was the
  same thing as "the session in front" right up until the hosts could be in
  front too. Then it quietly became wrong in four places at once: the host in
  the inspector, the name in the title bar, the subtitle, and every item in
  the **Terminal** menu — where it left ⌘W closing a session off screen.
  `current` is gone so it cannot be asked again; `ContentView.frontSession`
  reads `pane`, and anything about what is on screen goes through that.
  `Sessions.selected` survives and still means which terminal is current,
  which is a different and narrower claim.
- **The strip's selection is what the pane shows** — `PaneTab`: `.hosts` or
  `.session(id)`. `ContentView` holds two of them: `pane` for what is in
  front and `beside` for the split's other side. It carried a `.files(id)`
  too while SFTP was a tab, and the split took either kind; that went back to
  a window, so the split is two terminals again — but the shape is still the
  general one, and a third kind would drop straight back in.
  The split used to live in `Sessions`
  as a `secondary: UUID?` guarded against `selected`, which stopped working
  the moment "in front" could mean the hosts — a session can be the current
  one while something else is on screen. Both halves of the split belong
  where "what is in front" is decided.
  Picking the tab already shown beside this one **trades the two places**
  rather than drawing the same thing twice: a terminal is one view and can
  only be in one place, so the second pane drew nothing.
- **Changing the inspector in the same update that swaps the pane crashes
  the app.** The inspector was hidden while SFTP held the pane, and every way
  of writing that crashed: deriving `isPresented` from the tab, and setting
  it from a plain `.onChange(of: pane)`. Both make SwiftUI change two things
  about the same split in one transaction. Deferring the change a turn of the
  loop (`DispatchQueue.main.async`) fixed it. None of that code is here any
  more — SFTP is a window, so nothing hides the inspector — but **the trap
  is**: don't drive the inspector off a pane change without that hop. It is
  intermittent, two round trips can pass before it dies, so prove a change
  here with a dozen, and build the previous commit as the control.
  ⌘D is offered only when there are two sessions and the hosts are not in
  front — the sidebar is already the list, so the hosts are not one of the
  two sides.
  The hosts lead the strip and cannot be closed;
  anything picked in the sidebar selects that tab, and every way of opening or
  surfacing a session selects its own. There is no guessing between the list
  and a terminal any more: the tabs say which is up and either is one click.
- That replaced a `Bool` called `browsing`, and **the reason it had to go is
  the rule worth keeping**. A mode nobody can point at has to be set as a side
  effect of something else, and twice the side effect silently did not happen.
  Clearing it hung off `.onChange(of: sessions.selected)`, so **clicking the
  tab you were already on** wrote an unchanged value, nothing fired, and with
  one session open — the common case — the strip never worked at all. The
  sidebar had it mirrored: **clicking the row you were already on** writes
  nothing through `List(selection:)`, so it could not ask for the list back.
  Both were the same bug. **An `onChange` sees a value, never the act — so
  before driving any state off one, ask what happens when the value is set to
  what it already holds.** An `onChange` is still right for keeping derived
  state in step, which is what the one on `sessions.selected` now does: a
  closed tab really does move it, and the strip follows.
- The strip is **drawn whenever there is a list at all**, so the hosts tab is
  always there to come back to. The **welcome is the exception**: a fresh
  install has no list to browse, so it meets the window it has always met
  rather than one tab leading nowhere. With SFTP gone back to a window the
  strip can hold a single tab you are already on, which is worth revisiting
  if it reads as clutter.
- The **welcome comes first** in that chain, ahead of the tabs. On a fresh
  install there is no list to look at, and "All hosts, 0 hosts" is not what to
  meet.
- The **Window menu lists the sessions too**, with ⌘1 to ⌘9 for the first
  nine. That came in with the column and stays without it: a keyboard way to
  the fourth session is worth having whatever the switcher looks like, and
  one menu is cheaper than a second switcher.
- **Making each session its own `NSWindow`,
  so that macOS draws them as a real tab bar with the host list as the first
  tab, was built and thrown away** — it worked, tab overview and `⌘⇧[` and
  dragging a session out included, and it was still not wanted. **Don't offer
  it again.** What it cost, for the record: a window per session puts the host
  list's store and sheets a scene away, so every menu item needing either has
  to be posted back to it, and the split has to go, because macOS already does
  side-by-side by dragging a tab out.
- **This Mac is always the left side** of the browser; the right is the host
  it was opened on. Opened from no host in particular — ⌘B, the toolbar
  button with nothing selected — the right side **asks which host** rather
  than showing this Mac a second time, which told you nothing and made you
  choose anyway. Either side can be re-pointed from its own menu, so
  host-to-host copying is intact; it is just not what opening SFTP means.
- **SFTP is a window, and one at a time.** A window because it can sit beside
  a terminal and a tab cannot, so a transfer can be watched while something
  else is typed. One because asking again brings the window you have forward
  and **re-points** it — `FilesModel.show(host)` moves the far side, where
  `start(on:)` only fills a side never chosen — rather than stacking another
  over it. Two hosts' files at once is the two panes inside, not two windows.
  It is let go on closing, so the next opening is a fresh browser rather than
  one still holding the last one's connections.
  **This has flipped four times: tab, window, tab, window**, each turn asked
  for directly. The case for a tab is that the split can then hold one, which
  was built and worked; the case for a window is that it can sit anywhere,
  including beside a terminal, without the split existing at all. Don't flip
  it a fifth time on reasoning alone — only on a reason from someone who has
  used it.
- **The SFTP window closes its sessions now, and for weeks it did not.**
  `FilesModel.close()` ends both panes' sessions, and **nothing called it**:
  `windowWillClose` set `Self.shared = nil` and no more. `Core` holds each
  `SFTPClient` in `sessions`, so letting the controller go released the window
  and the model and *not* the `ssh` children — one per connected pane stayed
  alive, per opening, until the app quit. What makes this worth writing down is
  that the comment on that method claimed the opposite in as many words,
  *"Nothing is left talking to a host with no window to show it"*: a
  documented method with no callers reads as working code, and a comment
  beside it is evidence of what somebody intended, never of what the code
  does. It was found by sweeping for every unbounded wait in the app once
  `send` had its deadline — the same habit that found the third
  `write(contentsOf:`, and the sweep is cheap because there are only two
  continuations in the whole app.
  `close()` also answers a replace question still on screen, which is the one
  dismissal the dialog's own binding cannot cover: it answers Cancel when
  `isPresented` goes false, and a closing window leaves no view to set it, so
  the copy parked on that continuation waited for ever somewhere nobody could
  see it. The question goes first and the sessions after, because closing them
  underneath a parked copy would resume it into a session that has gone and
  report a failed transfer in a window on its way out.
  Only the question half can be checked without a server, and it is: with the
  answer taken back out, *"closing the window answers what was being asked"*
  dies on the suite's limit rather than passing.
- A `FilePlace` that has not been pointed anywhere is **not this Mac** — it is
  a question (`chosen` is false) and says "Choose a host". Without that state
  an unpointed pane reads as "This Mac" with an empty listing, which looks
  like an empty home directory. `chosen` is set **before** the connecting
  starts, so a host that refuses leaves the pane showing what went wrong
  rather than falling back to the question.
- There are **no secondary `Window` scenes left**, and only one window this
  app makes itself: Settings, an `NSWindowController`. SFTP was a second one
  and is a tab again. If a scene is ever added back, two things bit last time:
  `openWindow` does nothing unless a live view asks for it (not a `Commands`
  body, not an `AppActions` closure — no error, no window), and the **first
  scene in `body` is the one macOS opens at launch**, so a secondary one needs
  `.defaultLaunchBehavior(.suppressed)` or it comes up instead of the host
  list.
- The sidebar's `List` holds **one `ForEach` over one flat array of rows**,
  tree and search results alike. Two shapes in one list left the rows of the
  shape it had just dropped drawn over the new ones.
  The array is built in `Views/SidebarRows.swift`, not in the view: the row
  type, the walk down the tree and the search filter are all there, so the
  ordering — groups before hosts at every level, a folded group keeping its
  own row and losing what is under it, the search results **replacing** the
  tree rather than joining it — is checked without a window. `SidebarView`
  keeps `private typealias Row = SidebarRow` so the other six hundred lines
  read as they did. Matching nothing is a list of nothing, and that is a
  test: the tree coming back would be the old bug wearing a new shape.
- Anything automated waits for **its own copy** of the app. `pgrep Shellhand`
  matches every copy, including one the user has open.
- **Driving Quick Connect against a real host list connects to a real
  machine.** Return activates the highlighted match, and synthetic keystrokes
  here are not reliable — they get dropped (three arrows moved the highlight
  one row at one-second spacing, all three at two seconds) and they arrive
  late, so a Return meant for one step can land in another. That is how a
  session to a live host opened during a check nobody asked to connect.
  Escape is **not** the culprit: it dismisses and never activates, measured
  six times. Give the scratch store a host pointing at `127.0.0.1:1` and
  drive that instead — it fails instantly with status 255 and reaches
  nothing.
- `Group`, `Host` and `Color` are ambiguous: SwiftUI has a `Group` and a
  `Color`, SwiftTerm has a `Color`. Write `SwiftUI.Group` and `SwiftUI.Color`
  in files that hit them.
- **The sidebar is one list, and a second tab was built and cut.** It had a
  Hosts/Library switch above the search field, with Library a menu of three —
  Keys, Credentials, Snippets — and the records drawn as cards in the pane.
  All three records are gone now, so the switch went with them. Before that,
  a sidebar of three **lists** was built and taken out too, because it made
  the host list, which is what the window is for, one tab among three. If a
  second tab is ever wanted again: one switch over a menu, not a third list.
- **A write to the store while a list is drawing is a crash**, not a slow
  frame: every save rereads the store and resolves every host's inheritance,
  which mutates the array the list view is reading — AppKit calls it a
  "reentrant operation in its NSTableView delegate". Nothing saves as it is
  typed any more, the editor that did having gone with snippets; if one is
  ever written again it has to debounce, replacing the write still waiting,
  and flush on disappear so the last characters are not lost.
- **`.searchable` goes where it likes, not where you put it.** Inside a plain
  sheet it detaches, drawing a second search box floating at the top right
  while the list draws its own; and with `placement: .sidebar` it is hoisted
  to the very **top of the column**, outside the list it belongs to. A plain
  `TextField` is what works in both places; the host sidebar draws its own in
  a `safeAreaInset(edge: .top)` on the list, which also avoids re-indenting
  the whole modifier chain.
- In a list beside its detail, the **detail side needs `maxWidth: .infinity`**.
  With neither side greedy, `HSplitView` shares the spare width between them —
  and a `maxWidth` on the list constrains **the list, not its pane**, so the
  pane grows past the cap and the list sits centred inside it with a band of
  nothing either side. It shows up on **deselecting**, because that is when
  the detail collapses to a `ContentUnavailableView` and slack appears.
  Collapsing the list's two `.frame`s into one does **not** fix it; that was
  the first guess and it changed nothing.
- An `HSplitView` in a sheet **sizes itself to its content** unless told to
  fill: without `.frame(maxWidth: .infinity, maxHeight: .infinity)` it sits in
  a band across the middle with empty space above and below it.
- A `TextField` in a `.formStyle(.grouped)` row draws **right-aligned against
  its label**, which reads as a value already decided rather than something to
  type in. A label beside a `.roundedBorder` field is what looks editable.
- In a stack of bands, the one that should take the slack is the **long list**,
  not the text editor: give the editor a fixed height and the list
  `maxHeight: .infinity`, or the editor grows to fill and the list is clipped
  mid-row.
- A dialog that holds a long list and an editor gives each its **own
  scrolling band** rather than putting both in one Form, or the editor scrolls
  off the top behind two hundred rows.
- Transfers **queue**. `Core/TransferQueue.swift` holds the rule — which of
  the waiting ones start, given what is moving and how wide the queue is — so
  it can be tested without carrying a byte; the actor only obeys it. Width
  defaults to 2: one file's turn ends with a close and the next begins with an
  open and a stat, and a second transfer keeps the link busy across that gap,
  while many at once are back to competing for the one connection.
- **Carrying a file onto one already there asks first.** It used to destroy
  it silently, three ways: a download's `FileManager.createFile` truncates, a
  copy between two local panes removed the destination outright, and an
  upload's open-for-write truncates on the server. A fourth went the other
  way — a drop from Finder onto an existing name did nothing at all, because
  `copyItem` throws there and the `try?` swallowed it. None of the four said
  anything, and none could be undone.
- `Core/Replacing.swift` holds which names clash, worked out from the
  listings **both panes already hold**, so it costs no round trip and is
  tested without carrying a byte — the shape `TransferQueue` has. One question
  for the whole batch, not one per file: forty answered forty times is a
  dialog nobody reads by the fourth.
- **Case matters and the two ends disagree.** This Mac's disk is
  case-insensitive by default and an SFTP server's usually is not, so `README`
  arriving beside `readme` replaces it here and sits next to it there.
  `clashes` takes `caseInsensitive` and `FilesModel` passes `target.isLocal`.
  Asked the wrong way round it either invents a clash — a file silently not
  carried is as bad as one silently overwritten — or misses the real one.
- The question carries the **continuation the copy is parked on**, and the
  dialog's dismissal answers Cancel as well as its buttons do. A copy waiting
  on a question no longer on screen is worse than one that overwrites.
- A queued transfer is **not finished**. `Transfer.finished` used to mean
  "not running", which read a transfer that had not started as one that had
  already ended — that single line is what made a queue impossible to add
  until it was fixed.
- Everything a drag asks for is handed to the queue **at once** and then
  waited on, rather than asked for one at a time. It runs the same either
  way; the difference is that the strip can say "1 moving, 39 waiting"
  instead of showing one file and looking hung.
- **Nothing here shells out to `ssh-copy-id`, and nothing should.** It is a
  script that builds its own ssh command line, which would be a second way of
  deciding a host's port, its jump chain, its `-o` settings and how it logs
  in — the thing `SSHArgs` exists to prevent. Putting a key on a host was
  built, as a short script sent over the connection the app already knows how
  to make, and it went with the cut; the pre-reset bundle has
  `Core/CopyID.swift` if it is ever wanted back.
- Adding a field to `Host` or `Group` takes **three** edits, not two: the
  model, a migration in `Core/Store.swift`, and the hand-written GRDB row
  mapping at the bottom of that file (`init(row:)` and `encode(to:)`). Miss the
  third and the field reads and writes as its default for ever, with no error
  anywhere — the import test that caught it is the only reason it was noticed.
- **`@AppStorage` is keyed by the bundle id, not by `--db`.** A run against a
  scratch store still reads and writes the user's real preferences, so anything
  automated that touches one has to read it first and put it back.
  **And putting it back is not symmetrical.** `defaults export` saves the
  domain, and a single key is still easy to restore wrongly:
  `SUAutomaticallyUpdate` was boolean `true` and a restore with `-int 1`
  leaves an integer. **`-bool true` will not change it back**, because
  `defaults write` keeps an existing key's type and coerces the value into
  it — the rewrite comes back as an integer however many times it is tried.
  `defaults delete` the key first and then write it, which does give a
  boolean. Measured, with a scratch key proving `-bool` worked in that domain
  all along; and **quitting the app has nothing to do with it**, which was the
  first guess here and cost a pointless restart of somebody's app.
  Harmless in itself, since `bool(forKey:)` reads an integer 1 and a boolean
  true the same way and Sparkle is no exception — but restore a key with the
  **type** it had, and check it with `defaults read-type`, since
  `defaults read` prints `1` for both and cannot tell you.
- The test bundle is **hosted by the app**, so running the suite launches it.
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
- A palette is inherited like every other group setting: the host's own, then
  each group going up, then the one in Settings. Empty means "ask above";
  **"System" is not empty** — it means SwiftTerm's own colours, which is a
  different answer from "whatever Settings says". A name nothing answers to
  falls back rather than blanking the terminal, because a palette renamed in
  the settings file should not black out every host that named it.
- Changing a group's palette repaints the tabs **already open**, through
  `Sessions.repaint(from:)` on the host list changing. The Settings picker
  already worked that way and a group's doing something different would be the
  surprise. A session keeps the host it was opened with for its title and its
  argv; `adopt` only changes what it is drawn in.
- A group says where a host **lives** and passes its settings down; a tag says
  what a host **is**, cuts across the tree and carries nothing. Both ways of
  finding a machine are meant to be used at once, which is why the tag chips
  sit under the tree rather than replacing it.
- Chosen tags **narrow together**. Two chips mean "both", not "either":
  `web` and `eu` asks for the European web servers. Widening is what the
  search field is for.
- There is **no table of tags** — a tag exists because a host carries it. So
  renaming one rewrites every host that carries it, deleting one takes it off
  them, and both live on the chip rather than in a manager window. Renaming
  onto a tag that already exists merges the two, which is how a typo that has
  been spreading gets cleaned up; renaming to exactly the same string does
  nothing, while changing only the case settles the spelling everywhere.
- A hosting controller sizes its window to **the view's minimum**, throwing
  away the rect `NSWindow` was given — so `setContentSize` has to come after
  `contentViewController`, and `setFrameAutosaveName` after that, because
  setting the autosave name applies a saved frame at once and would otherwise
  be overwritten by the default size.
- `.help()` is a tooltip, **not an accessibility name**. An icon-only button
  with one still reads as "button": `Image(systemName: "plus")` carries no
  text. Every icon-only button gets `.accessibilityLabel` — seventeen of them
  across the views did not have one.
- **Don't try to check that through System Events.** It reports every SwiftUI
  button as `description=[button]` whether or not it has been named, with
  `AXDescription` empty and only `AXHelp` carrying the tooltip — and
  `Label(…, systemImage:).labelStyle(.iconOnly)` reads back exactly the same,
  so swapping to it proves nothing either. The name lands in
  `AXAttributedDescription`, which is in the button's attribute list — but
  reading it fails with "AppleEvent handler failed" **whether or not a label
  has been set**, because System Events cannot marshal an attributed string
  back at all. That was checked by stripping the label from a button and
  getting the identical error, so the probe distinguishes nothing. AppKit's own controls in the same
  window (a scroller's "increment arrow button") do report theirs, which is
  what makes the silence look like a bug rather than a blind spot.
  Accessibility Inspector or VoiceOver is the only way to see these.
- **One shape for managing a list**, for whenever one is wanted again: the
  list beside the one selected, in an `HSplitView`, with `+` and `−` at the
  bottom left and Done at the right. Snippets, Credentials and Tunnels were
  all this before they were cut. Two of them started as a list that opened
  **a second sheet on top of itself**, which hid the list behind the thing you
  were editing and gave one dialog two footers.
- An **empty id must not match every record that names nothing**. A record not
  yet saved has no id, and the hosts that name none have none either —
  counting them would report a draft as used by the whole list. That trap bit
  twice, in what-uses-a-credential and in what-uses-a-key, and both are gone;
  it is written down because it is a property of "match by id", not of either.
- `import Foundation` in a test file makes **`Host` ambiguous** with
  `Foundation.Host`, so `Tests/ValidationTests.swift` deliberately does not
  import it. If something there needs `UUID`, give it a literal id instead.
  The other way out, where the import is genuinely needed — `TerminalSessionTests`
  writes an ssh log to disk — is to spell the app's own type `Shellhand.Host`,
  exactly as `SwiftUI.Group` is spelled out elsewhere. Leave the comment on the
  import saying why, or the next person deletes it and the file stops building.
- **A terminal that has heard nothing does not come back empty, and reading it
  as output made `.connecting` meaningless.** `getBufferAsData` hands back the
  buffer's own blank rows, so the watchdog's `!screen.isEmpty` was true from the
  moment a session opened: every session went to `.connected` on the first look,
  200ms in, whether or not anything had answered — so a host refusing to answer
  read as connected, in every release up to 0.0.4. The question is whether the
  far side has **said** anything, so the test is blank rather than empty
  (`trimmingCharacters(in: .whitespacesAndNewlines)`). `HostKey` was always
  immune, because it filters empty lines before taking its tail.
  **Only a real buffer could have found this.** The rule's own tests all passed
  against the broken version, because they were written from the same
  assumption the code made — `""` for "nothing said yet". That is the argument
  for the scripted SFTP server in a second shape: the value is not only in the
  misbehaviour you script, it is in the assumption you did not know you had.
  So both halves are pinned in different places on purpose —
  `SessionProgressTests` for the rule, `TerminalSessionTests` for the buffer
  being non-empty *and* blank — because the rule is only right while that
  second fact holds, and SwiftTerm is free to change it.
- **A host-key question that wrapped was not seen at all**, in every release
  up to 0.0.4, and the consequence is the worst shape this bug could take: ssh
  sits on the pty waiting for an answer the app never asks for, while the
  session reads as `.connected` because the screen is not blank. The buffer is
  read row by row and nothing rejoins what wrapped, so a 27-character phrase
  matched line by line is in neither row. Measured on a real 40-column
  terminal: `"...want to continue connec\nting (yes/no/[fingerprint])? "`.
  Reachable without trying — `changeFontSize` goes to 28pt, and a window
  narrower than about 900pt is then some 50 columns, where the phrase straddles
  the boundary.
  **The obvious fix is the wrong one.** Widening `tail(of:)` past two lines
  lets the shell's own reply sit in the tail beside the question it answered,
  which is the stuck-prompt bug the rule exists to prevent and which
  `howFarBack` pins deliberately. So the two rows are **rejoined** instead, and
  compared with whitespace dropped from both sides, because `trimRight: true`
  means a wrap falling on a space loses that space from the buffer and no
  search for the phrase as written gets it back.
  **Three rows or more are found now too, and showing the question is the
  half that mattered.** This was left broken on purpose while the tail's depth
  was what kept an answered question from reading as live; once the
  closing-`?` rule took that job, depth only had to reach back far enough to
  find the phrase. OpenSSH's prompt is 68 characters with the phrase starting
  25 in: three rows under 34 columns, four at 16, five at 13, six at 8 — not
  even monotonic, since at 25 the phrase happens to start a row and two will
  do. So no depth is the right one; the tail is **sixteen** rows, enough down to
  about three columns, and bounded because `getBufferAsData` hands back the
  scrollback and the watchdog asks five times a second.
  **Finding it was not enough.** At those widths the warning and the
  fingerprint wrap as well, and `question(in:)` looked for its start in a single
  row and fell back to four rows — so a widened tail alone would have raised a
  dialog asking you to trust a key **without showing the fingerprint**, at 16
  columns and below. It now puts rows back together to find where the warning
  opens, then the fingerprint's line, then four rows as a last resort, with a
  search kept linear so a long scrollback cannot make it slow.
  Pinned by fixtures **generated** rather than typed — OpenSSH 10.3's real
  question cut into rows the way a terminal of that width hands them back,
  right-trimmed — at 33, 16, 13 and 8 columns, live and answered. Checked the
  way round that matters, one half at a time: with the tail back at two rows
  the question is missed at all four widths; with the start found in one row
  again, it is found but shown without its fingerprint or its opening at 16,
  13 and 8. The ideal is still at the source — `screen` rejoining wrapped rows
  so every reader sees logical lines — and still not available, since SwiftTerm
  keeps `Buffer.lines`, `withTerminal` and `Terminal.cols` internal; if a version
  ever makes them public, rejoin there and delete this.
  `question(in:)` needed the same treatment: with no row carrying the phrase it
  fell through to "hand back the whole screen", burying the fingerprint at the
  one moment somebody has to read it.
- **Accepting a new host key could bring the question straight back**, in
  every release that had the two-row tail, and its own unit test pinned the
  bug as intended. On a server that logs in quietly the sequence was: Accept,
  the app types `yes` and resets the state to connecting; the watchdog finds
  `…(yes/no/[fingerprint])? yes` still in the last two rows and asks again; the
  dialog reappears; and a second Accept types `yes` + Return into the now-live
  shell, which runs the Unix `yes` command and floods the terminal with `y`. A
  Reject typed `no` into it instead. A chatty server mostly hid it, its second
  line pushing the question out of the tail, so it flickered rather than stuck.
  **Two facts the fixtures had wrong, and only a real prompt had right.** A pty
  echoes the answer onto the **question's own row**, not below it; and the app
  runs `ssh -E`, so *"Warning: Permanently added"* goes to the log and never
  reaches the screen the fixtures put it on. With both, the answered row plus
  one line of the server's are the whole tail. `howFarBack` asserted exactly
  that a question with one line after it is *"still within reach"* — an
  artefact of the tail's depth written down as a rule, which is the
  blank-screen bug's lesson again: tests written from the code's own
  assumption pass against the code's own mistake.
  **The rule now is the one the doc comment always claimed:** ssh writes the
  question last and waits, so it is live only while **nothing follows its
  closing `?`** — no echoed answer, no output. The two rows are still joined,
  because a wrapped question needs them; the depth just no longer does the
  guarding. That also made a **wider tail safe**, which is what let a question
  wrapped across three rows or more be found — see the bullet above.
  Pinned three ways and checked the way round that matters: with the old rule
  put back, `answeredQuietly` fails on all three answered forms (OpenSSH
  10.3's real wording, `fingerprint is:` with a colon, echoed `yes`, `yes` and
  a line, and `no`), the corrected `howFarBack` fails, and the real `ssh` test
  in `TerminalOverSSHTests` fails — five expectations across three tests,
  each able to catch it without the others.
  **The residue is closed too.** `answerHostKey` types the answer and resets
  the state at once, so a watchdog tick landing in the instant before the
  pty's echo arrived still saw a live question and re-posed it: the dialog
  back for one 200 ms tick, and an Accept inside that tick typed `yes` into the
  shell. An answer now records the question it answered, and
  `SessionProgress.next` holds back **that question** — not questions, since a
  jump chain asks one per hop and the second must still be asked — until the
  session is through, when the record is let go so a later question worded
  the same is a new one. The decision stays in `SessionProgress`, pure; the
  session only remembers.
  **The race is tested held open rather than hoped for.** It lasts about a
  millisecond in a real session, so no real-`ssh` test could aim at it. A fed
  view has no process behind it, so an answer is typed into nothing and
  nothing ever echoes: every look after the answer is the look before the
  echo, and the test lets five of them pass. Checked one piece at a time: with
  the hold-back taken out of `SessionProgress`, the pure test and the held-open
  one both fail; with `answerHostKey` no longer recording the question, the
  pure test still passes and the held-open one fails with *"the answered
  question came back"*. A different question straight after an answer is
  asked either way — that test is the control that keeps the fix from muting
  every question.
- **The watchdog's decision is `SessionProgress`; `watch()` is only the
  looking.** The loop sleeps, ticks, reads ssh's log and looks; what it makes
  of the screen is one pure function, which is why there are tests for it at
  all. `watch()` is deliberately not private, and `logPath` is readable, so a
  test can run the real loop against a view it has fed through SwiftTerm's own
  `feed(text:)` — no pty, no process, no unknown host. `ticks` is what tells
  "the watchdog ran and the state did not move" from "the watchdog never ran",
  and there is a test for each.
- **Settings is a window this app makes itself**, not a SwiftUI `Settings`
  scene: the glass chrome macOS 26 draws comes from `.fullSizeContentView` in
  the window's style mask, and a scene does not expose it — setting it
  afterwards through an `NSViewRepresentable` does not hold, because SwiftUI
  puts the window back the way it had it. So `SettingsWindowController` makes
  the `NSWindow`. A window made in code is released when it closes, which
  would leave the controller holding a freed one, so it sets
  `isReleasedWhenClosed = false`.
- What the `Settings` scene gave for free was Shellhand ▸ Settings on ⌘,.
  `CommandGroup(replacing: .appSettings)` buys it back, in the place every
  Mac app keeps it. Check it after touching the scenes: there is nothing to
  warn you that the item has gone.
- The **back and forward buttons are load-bearing**. A `ToolbarItemGroup` is
  what makes AppKit give the window an `NSToolbar` at all, and with no
  toolbar the title bar does not get the glass treatment — so taking the
  history out would quietly take the chrome with it.
- Every pane carries three modifiers and each does a job: `.formStyle(
  .grouped)` for the inset sections, **`.scrollContentBackground(.hidden)` so
  the glass shows through** instead of an opaque sheet painted over it, and
  `.contentMargins(.top, 8, for: .scrollContent)` to keep the first section
  off the toolbar.
- The detail pane's `.navigationTitle` becomes the **window** title, so the
  title bar says which pane you are on rather than "Settings". That is what
  System Settings does, and `window.title` set in the controller is
  overridden by it.
- A sidebar footer goes in a **`safeAreaInset`, not a `List` row**: a row is
  indented for a selection it will never have, and the inset left so little
  width that the build number fell off the end of "Version 0.0.1 (1)".
- Settings is a **window**, like Files, so the three dialog widths below do
  not apply to it. It opens at 700×500 and will not go below 620×420.
- **Dialogs come in three widths**, in `Views/DialogSize.swift`: 460 for one
  question, 560 for one record or a plain list, 820 for a list beside its
  detail. This app grew nine — 420, 460, 480, 500, 520, 560, 580, 620, 820 —
  each picked by hand, so opening two sheets in a row slid the window sideways
  under the pointer. **Width only**: height stays with each dialog, measured,
  because a width that jumps between sheets is jarring and a height that does
  is not — and both times a height was handed down rather than measured here,
  it clipped the last row.
- **Quick Connect is a palette, not a dialog**, and is deliberately outside
  that grid: ⌘K, type, return, the shape Spotlight has, where a footer would
  be noise. What a palette does owe you is a way out, and with no button bound
  to `.cancelAction` nothing answers Escape — `onExitCommand` is what does.
- A button on `.cancelAction` is **the Escape key**, so it must say what
  leaving means. Copy Key and Import both labelled theirs "Done" while sitting
  beside the button that actually does the thing, so Escape claimed something
  had happened when nothing had. They say "Cancel" until it has.
- **The host editor has two tabs, and the line between them is what the fields
  are for, not what ssh calls them.** General is what you call the host, how to
  reach it and where you file it; Advanced is what happens once you are on it.
  An earlier cut — Machine / Logging in / Filing — was ssh-shaped and wrong at
  the first row: a name is not a fact about the machine, so it does not belong
  beside the address.
- The destination is **one row**, `user@host:port`, because that is one thing —
  it is how ssh is typed and how the preview line along the bottom renders it.
  Three rows said the same and left you to infer they belonged together.
- Advanced carries a **mark when what is wrong is on it**, worked out by asking
  whether the problem survives clearing the ssh options. A greyed-out Save with
  nothing visible to explain it is what tabs cost if you don't do this.
- **That mark has to be a character, not an SF Symbol.** A segment of a
  `.pickerStyle(.segmented)` picker takes a label **string**, so an `Image`
  interpolated into its `Text` has nowhere to live: it collapses to U+FFFC and
  draws nothing. The trap is that accessibility reports the label as
  `"Advanced ￼"`, so a probe reads back a mark that is not on the screen —
  this was only caught by cropping the tab strip out of a screenshot and
  looking. Written as an Image, the host editor's mark had never once
  appeared.
- The problem and the preview command are **both shown**. The problem used to
  replace the command, which took it away exactly when you wanted to see what
  was wrong with it.
- **A grouped `Form` right-aligns what it is given, and that reaches inside a
  `.roundedBorder` field**: every placeholder sat against the right edge of its
  own box, which reads as a value somebody chose. `.multilineTextAlignment(
  .leading)` on each field is the fix. And a placeholder of "—" for "nothing
  inherited" reads as a value too — an example of what belongs there does not.
- A label that is only a placeholder **disappears exactly when it is needed**.
  Two bare fields side by side in a row said which was which until both were
  filled, and then nothing did. Every field gets a label beside it, in the
  same `LabeledContent` + `.roundedBorder` row the rest of the app uses.
- **The group editor has the same two tabs**, but not the same line between
  them: a group is never reached, so General is what the group *is* and who
  the hosts under it log in as, and Advanced is what happens once you are on
  one of them. Its Advanced says `•` when something over there is merely set,
  which the host editor has no need of — the one thing groups are most used
  for is a palette, and the `DisclosureGroup` this replaced decided whether to
  open itself from the ssh options and the agent alone, never looking at the
  palette. So a group that painted its hosts opened with the palette shut and
  nothing to hint at it.
- **Both editors are sized so that neither tab ever scrolls**, and sized for
  **editing** rather than for a new record: an editor opened on something has
  a Delete in its footer, which costs the form 23pt. The host editor is
  650 General / 570 Advanced, the group editor 570 / 555. The earlier
  500/490 and 600/480 were measured against **new** records and scrolled on
  every tab but one as soon as a real host or group was opened in them.
- The test for "does it fit" is the form's scroll area — the `AXScrollArea`
  that is a **direct** child of the sheet's top group, not a recursive search,
  because the ssh options text editor is itself a scroll area and reports an
  overflow that is not there. No `AXScrollBar` among its direct children means
  it fits. If there is one, its `AXValueIndicator` gives the answer in one
  pass rather than by bisecting heights: content height is the form's height
  times track ÷ thumb, so a 284pt thumb in a 333pt track over a 331pt form
  means 388pt of content and 57pt missing.
- **Arrow keys do reach a group row — focus the outline once and then
  arrow.** Re-focusing it before each press puts the selection back where it
  started, so a loop that focuses, presses Down, and checks never gets past
  the first row; that is what made group rows look unreachable and `Edit
  Group…` look permanently disabled. One `set focused of <the AXOutline> to
  true`, then as many `key code 125` as you need, and the selection walks the
  list — groups included. A synthetic `click at` genuinely does nothing here,
  which is the part that is true.
- The group editor says **where an inherited value comes from beside the
  field**, not inside the placeholder. Folding both into one grey string
  ("deploy — from Production") meant the field had to be read to learn two
  different things, and it left nothing to say when a value was inherited from
  nowhere — which is how `—` ended up sitting there looking like a value. The
  placeholder is now the inherited value or an example, and the source is a
  caption of its own, which is what the host editor already did.
- Tags are **tokens you can take off**, not a line of commas, and the value
  underneath is still the comma form so nothing below the view knows. Their
  field is drawn with a border like every other, because a row that is a field
  and does not look like one reads as decoration.
- **The whole window can be driven through System Events, sidebar included** —
  but only if you ask the right way, and asking the wrong way makes the app
  look like it publishes nothing.
  - Walk with `UI elements` and `role of`, **not** System Events' own class
    names. `outlines of x`, `groups of x` and `rows of x` return 0 at levels
    where `UI elements of x` returns children, so a per-class walk hits what
    looks like an empty branch and stops. That is what made the host list
    appear to be an accessibility dead end for three sittings; it is not.
  - Address by `repeat with x in y`, never `item 1 of y` — the latter fails
    with "Can't get window", which reads like the app has quit. Elements from
    `entire contents` cannot be dereferenced here at all.
  - The sidebar is `AXScrollArea → AXOutline` (described "Sidebar")
    `→ AXRow`, each row readable, which is six levels down from the window.
  - **`select` on a row does not select anything.** It sets `AXSelected`, and
    the row reports `selected=true`, but SwiftUI's `List(selection:)` binding
    never hears about it, so every menu gated on the selection stays grey —
    a convincing false negative. The row offers no `AXPress` either.
    What works is `set focused of <the AXOutline> to true` and then arrow
    keys, which is the same path a person on the keyboard takes. After that
    `hasHost` is true and `Edit Host…` opens on the right host.
  - **A row's context menu cannot be opened from a script.** The row
    publishes `AXShowDefaultUI` and `AXShowAlternateUI` and nothing else —
    no `AXShowMenu` — and a control-click at the middle of its own reported
    bounds opens nothing, with no new window and no menu anywhere in the
    tree. So an item that only exists in a context menu cannot be driven from
    a script at all — `--uicheck` used to reach past it by calling the action
    the item calls, and with that gone `newHostInGroup` and its like are
    checked by using them.
  So everything behind `hasHost` **is** verifiable on screen, with no source
  edit and no preference to put back.
  **`scripts/window-check.sh` is that walk written down**, and three things
  cost a run each. An AppleScript **handler is top level**, so it is outside
  any `tell application "System Events"` — and `UI elements of el` is that
  app's terminology, so a handler using it fails to compile with *"Expected
  end of line but found identifier"*, pointing at the `repeat` rather than at
  the missing context. Wrap each handler's own body in the tell.
  **Folded is correct.** The first version asserted the whole tree flat and
  failed: `Tree` decides the fold the sidebar opens on, so a group keeps its
  row and loses what is under it. Assert the folded shape, then open it — that
  tests more, and the opened order is the documented one, groups before hosts
  at every level.
  **Refuse to run beside another copy.** System Events addresses a process by
  name, so two copies of Shellhand make every lookup ambiguous; the check
  names the other one and stops rather than driving the wrong window, and
  never quits the user's. It borrows the whole preference domain with
  `defaults export` and gives it back on an EXIT trap, because `@AppStorage`
  is keyed by the bundle id and a scratch store does not protect it. Ungated routes are still the cheapest
  when they fit: `New Group…` opens the group editor with nothing selected,
  and Shellhand ▸ SFTP opens without a selection.
- A key path is **spelled however it was typed** — `~/.ssh/id_ed25519`,
  `/Users/you/.ssh/id_ed25519`, the same with `.pub` on the end — so anything
  comparing two of them has to settle both first (tilde expanded, `.pub`
  dropped). `Core/SSHKeys.swift` did that for the Keys manager and went with
  it; a host's `identity` is now only ever handed to ssh, which does its own
  expanding, so nothing compares paths any more. Write it again rather than
  comparing the strings if anything ever needs to.
- Capturing a window **without** taking focus does not work here: the modern
  way is ScreenCaptureKit (`CGWindowListCreateImage` is now unavailable, not
  merely deprecated), a plain command-line tool needs `NSApplication.shared`
  before it or CoreGraphics trips `CGS_REQUIRE_INIT`, and then
  `SCScreenshotManager` still fails with -3811 because Screen Recording is
  granted per binary and a freshly built one has not been granted it. So
  screenshots need the app frontmost — which means **not while the user is
  typing in another app**. Check who is frontmost first and skip rather than
  fight for it.
- **A locked screen looks exactly like an app that failed to launch.** With
  `loginwindow` up, System Events reports `count of windows` as 0 for every
  process, `set frontmost to true` quietly does nothing, and `front window`
  fails with "Invalid index" — so a perfectly healthy window reads as no
  window at all, and the next guess is that the last edit broke the scene.
  Ask CoreGraphics instead: `CGWindowListCopyWindowInfo` lists the window
  with `onscreen=true` whatever the lock is doing, and an on-screen-only
  listing shows `loginwindow` sitting at layer ~2004 over everything. Check
  that before suspecting the app, and do not try to screenshot past it.
  **It hides one more probe than that, found proving the update dialog:** a
  menu item's `enabled` reads **false** whether or not it is, because AppKit
  validates a menu when it is about to be displayed and nothing can display
  behind a lock. `Check for Updates…` read `enabled=false` on a **Release**
  build, which looks exactly like the Debug guard firing on the wrong build.
  Conclude nothing about a menu from behind a lock. Note also that the lock
  leaves whatever was frontmost **reporting** as frontmost, so that check does
  not give the lock away either — only the window count and
  `CGSSessionScreenIsLocked` do.
  **`window-check.sh` carried a guard against this that could not fire**, and
  it is the `FilesModel.close()` lesson again: the comment said *"Ask
  CoreGraphics, which answers through the lock"* while the code asked System
  Events for the frontmost app and failed only on an **empty** answer — which
  a lock never gives. So the run passed the guard and died further down on the
  zero windows, reading as a launch that never happened, which is the exact
  confusion the guard existed to prevent. It reads
  `CGSSessionScreenIsLocked` out of `ioreg` now, and the walk is checked
  against fixtures of all four shapes — key true, key absent, key false, no
  session dictionary — because a guard nobody can make fire is worth nothing.
- A screenshot taken with `screencapture -R` captures **the screen at that
  rectangle, not that window** — if the app loses focus between reading its
  bounds and capturing, you get whatever is on top, which may be the user's own
  work. Check the app is frontmost immediately before and after, and throw the
  capture away if it was not. `-l<windowid>` is no help: it quietly falls back
  to the whole screen.
- One rule for reading tags, in `Core/Tags.swift`: a comma, a semicolon, a bar
  or a space all separate — `Tags.separates` for one character, `Tags.clean`
  for a string. The editor's field asks the first to know when what has been
  typed is finished and the CSV importer asks the second, so neither writes the
  rule out again, because a tag typed by hand and a tag imported from a sheet
  coming out spelled differently is the kind of bug nobody reports.
- A sidebar row drags as a **`ListItem` with its own UTType**, not as a String.
  A String would accept any text dragged in from another app as a host, and
  would not say whether what arrived was a host or a group.
- Dropping a group into one of its own descendants is refused by
  `HostStore.move(group:toParent:)`, which asks `Validation.possibleParents`.
  The rule about loops is written once, where the move happens, rather than in
  each thing that can start one.
- A host list arrives three ways — OpenSSH's own config, a CSV, and this
  app's own YAML — and all three become a `Portable.Document`, so the merge,
  the dry run and the apply are one path rather than three. The preview is the
  plan the import applies, not a second implementation that predicts it.
- **Swift reads CRLF as ONE `Character`.** `"\r\n"` is a single grapheme
  cluster, so a parser that matches `"\r"` and looks ahead for the `"\n"`
  matches neither: the lookahead eats the next value and the row never ends.
  Match `"\r\n"` as itself, beside `"\n"` and `"\r"`.
- **Removing a field from the model is not enough: the importer has to keep
  accepting it.** A YAML file is refused whole when it holds a key the parser
  does not know, so taking `forwards` out of the allowed list made **every
  export written before the cut** unimportable, over a feature that no longer
  exists. The key is accepted, its rules dropped, and the host noted as having
  had them. `credentials`, `snippets`, `credential` and `startup` are accepted
  the same way for the same reason. Do this for anything else ever removed
  from the format — a file somebody exported last month is still theirs.
- A column a CSV names that nothing can be made of is **passed over and
  reported**, not refused — the opposite of the settings file's rule, and for
  the opposite reason. That file is written by hand, where a typo doing
  nothing silently is the one outcome worth ruling out; a CSV comes out of
  another program, and a Password column beside a Notes column is the normal
  case. Saying which columns went nowhere is what keeps it from being silent.
- `.sheet(isPresented:)` builds its content from **the view as it was before
  the flag flipped**, so a sheet that reads other state set in the same gesture
  gets the stale value — pressing CSV on the welcome opened the sheet on the
  ssh config every time. Carry what the sheet needs in the binding itself and
  use `.sheet(item:)`.
- A button whose label is a stack has **no accessibility name**: these read as
  "button 1, button 2, button 3". Name it with `.accessibilityLabel`, placed on
  the button before the background and border wrap it in layers of their own.
  Not `.accessibilityElement(children: .ignore)` — that names the row but
  replaces the button's own element, and then pressing it does nothing at all.
  The label lands in `AXAttributedDescription`, which AppleScript cannot read
  back, so `description of button 1` still says "button".
- Terminal colours live in `Core/Theme.swift`; a palette of one's own goes in
  the config under `themes:` rather than in a form, because eighteen colours is
  a thing to paste. SwiftTerm's `installColors` wants components in 0–65535, so
  an 8-bit channel is multiplied by **257**, not 256 — otherwise 255 lands on
  65280 and every white comes out a shade under. A palette missing a colour, or
  holding something that is not one, is refused whole: a terminal painted with
  fifteen of sixteen is worse than one left alone. "System" means SwiftTerm's
  own colours, left alone, so choosing it back repaints nothing until a new
  session.
- The app icon is an **Icon Composer bundle**, not an appiconset:
  `Shellhand/Resources/Shellhand.icon`, written by `tools/icon.py`. It is a
  directory of text — `icon.json` beside an SVG — and XcodeGen knows the
  extension, so it lands in the resources phase as one `wrapper.icon` with no
  help from `project.yml`. What does have to be set is
  `ASSETCATALOG_COMPILER_APPICON_NAME`. Without it the build still succeeds
  and the bundle yields **nothing at all** — no `Assets.car`, no `.icns`, no
  `CFBundleIconName` — with no warning anywhere, which is exactly how an app
  ends up shipping the generic icon.
- An icon is judged at **16pt**, not at 512: that is where it fails, and a
  mark that works at 512 says nothing about it. `tools/icon-preview.sh` writes
  a loupe — 16 and 32 blown up with the pixels kept square — because smoothing
  a 16pt icon makes it look better than it is. It renders by asking
  NSWorkspace for a stub app's icon rather than by rasterising the SVG, since
  the squircle, the gradient, the shadow and the specular are the system's
  half of the picture.
- `xcodebuild test` launches the app, so **a second copy of the same bundle
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
- `Executed 0 tests, with 0 failures` is the **XCTest** counter, and every test
  here is swift-testing, so that line says nothing either way — grepping for it
  reports an empty run as a pass. Ask the result bundle instead:
  `xcrun xcresulttool get test-results summary --path build/Logs/Test/*.xcresult`
  gives `passedTests` and `failedTests` as numbers.
- **That glob is a trap after the second run.** A derived data path keeps one
  bundle per run, and the shell hands `--path` whichever the glob expands to
  first — so the numbers come from an earlier run and a new test file looks
  like it never ran. It reported 391 when the answer was 401. Sort and take
  the last:
  `--path "$(ls -1d build/Logs/Test/*.xcresult | sort | tail -1)"` — the
  timestamps are in the names, so sorting by name is sorting by time.
- **Sparkle's helpers have to be signed again after the build, from the
  release script rather than a build phase.** Xcode signs
  `Sparkle.framework` as it embeds it but leaves `Autoupdate` and
  `Updater.app` inside exactly as Sparkle shipped them, and notarization
  refuses those: they need this project's Developer ID, the hardened runtime
  and a secure timestamp. It cannot be a build phase, because Xcode embeds a
  **package's** frameworks outside the build phases, so no phase can be
  ordered after that embedding — one tried, and raced it. The app is then
  signed again over the changed framework, with
  `--preserve-metadata=identifier,entitlements,requirements,flags` so that
  re-signing does not quietly drop what the build decided.
- **The app is not sandboxed, so Sparkle's XPC services go and
  `SUEnableInstallerLauncherService` is not set.** Sparkle ships both for
  sandboxed apps; shipping them unsandboxed means notarizing code nothing
  runs. Sparkle's own sample Info.plist sets that key — it is wrong for this
  app, and the release script deletes `XPCServices` to match.
- **Ordinary builds have no secure timestamp, and notarization takes nothing
  without one.** `OTHER_CODE_SIGN_FLAGS="--timestamp"` on the release build is
  what adds it. The script then checks for `Timestamp=`, the hardened runtime
  flag, a Developer ID authority and the absence of `get-task-allow` on every
  piece of code it is about to ship, because each of those is a rejection that
  otherwise arrives from Apple ten minutes later with no line number.
- **A dry run and a real run share `build/release/DerivedData`, and the build
  service outlives the build.** `SWBBuildService` keeps `build.db` open after
  its `xcodebuild` has exited, so starting the second run too soon after the
  first fails with *"unable to attach DB … database is locked. Possibly there
  are two concurrent builds running in the same filesystem location."* and
  `** BUILD FAILED **`. The failure is real and that run dies; a later run,
  once the lock is free, builds fine. Either leave a moment between runs or
  give one its own `-derivedDataPath`.
- **A wrapper around the release script can hide which run you are looking
  at.** In zsh `status` is read-only — it is an alias for `$?` — so
  `status=$?` kills the wrapper while the script it launched carries on, and
  whatever was watching the wrapper reports the release as failed when it is
  running perfectly well. Name the variable anything else. What that cost
  here was worse than the lost wrapper: a dead run's 337-byte log sat beside a
  live `release.sh` from a *later* invocation, and the live process was read as
  the dead one recovering — `BUILD FAILED` explained away as an internal
  retry, which `xcodebuild` does not do. A log is written per invocation, so a
  stale log next to a running process means **two runs, not one that is
  retrying**. Check `ps -o pid,ppid,etime,command` and compare the elapsed
  time against when you started it before concluding anything either way.
- **`SUFeedURL` is permanent for the life of a build.** An app in the wild
  asks the address it was born with, for ever, and there is no correcting it in
  the field. So the feed is `appcast.xml` on this repository's `main` branch
  and the DMGs come from GitHub releases: nothing a shipped build depends on
  needs a domain, a host or a renewal. If a domain ever arrives, new builds can
  be born with a new address while the old ones go on asking GitHub. The
  release script refuses to build if the plist's feed is not that URL.
- **The feed is served through a CDN that caches it for five minutes, so
  pushing the appcast does not change what Sparkle sees.**
  `raw.githubusercontent.com` answers with `cache-control: max-age=300`, so
  for up to five minutes afterwards the live feed goes on naming the
  **previous** version. Measured on 0.0.8: the appcast was pushed, `main`
  held it, and the feed still offered 0.0.7 at `source-age: 267`; it turned
  over about three minutes later, so the window is real but short. Checked
  straight after publishing that reads exactly like a push that did not
  land, and the next move looks like pushing again. Ask what `main` holds
  instead — the blob sha through the API, against
  `git rev-parse HEAD:appcast.xml` — which is the same question with no
  cache in front of it. A cache-busting query string would dodge it and
  prove nothing, since Sparkle asks the plain URL. Harmless in itself: an
  app checking inside that window hears on its next check.
  **Two corrections from 0.0.9, both of which had been read the wrong way.**
  The **tap's cask is behind the same cache** — served from
  `raw.githubusercontent.com` too — and on 0.0.8 it looked instant, which
  read as casks being exempt. They are not. The rule is **per path, and only
  for a path something fetched recently**: on 0.0.8 nothing had asked for the
  cask before the push, so there was nothing cached to serve; on 0.0.9 the
  previous release's own verification had warmed it, and it served 0.0.8 for
  minutes after 0.0.9 was pushed. So a verification that passes straight
  after a push may only mean that nobody had looked before — which is the
  weaker claim. Both turned over about 200 seconds after the push on 0.0.9,
  measured.
- **Back up the EdDSA private key or every shipped app is stranded.** It lives
  in the login keychain under the account `shellhand`, and
  `generate_keys --account shellhand -x <file>` is the only copy there will
  ever be. Without it, nothing can sign an update those apps will accept —
  there is no re-keying a build that is already out, and no recovery. The
  public half is in `project.yml`; the release script refuses to build an
  appcast if the keychain's key is not the one the app checks against.
- **Nothing about updates runs in a Debug build.** Sparkle would offer a
  Debug build the newest release DMG and install it over itself. `start()`
  and `check()` return early and `canCheck` is false, so Check for Updates…
  greys out while developing rather than looking live and doing nothing.
- **The appcast is written from a folder, so the folder has to hold every
  version still being offered.** `generate_appcast` does not amend an
  appcast; it rewrites it from the DMGs it is given, so a folder holding only
  the new one produces a feed that has forgotten every earlier release. The
  DMGs live in the GitHub releases, so the script fetches the past ones back
  before generating. One `--download-url-prefix` covers the whole folder while
  GitHub puts each version behind a tag of its own, which is why the enclosure
  URLs are rewritten per version straight afterwards, from the version in each
  filename.
  **It also prunes, and 0.0.4 was the first release with enough history to
  show it.** `generate_appcast` retired `Shellhand-0.0.1.dmg` into
  `build/updates/old_updates` by itself — nothing here passes
  `--maximum-versions` — so the feed carries the most recent few rather than
  every release ever made, and 0.0.4's appcast lists three items, not four.
  That is harmless: Sparkle offers the newest item, an app never needs a feed
  entry for the version it is already on, and the retired DMG is still served
  from its own GitHub release. Worth knowing before it looks like a version
  has gone missing.
- **`Updates` deliberately does not bridge `canCheckForUpdates`.** Sparkle's
  own sample publishes it through Combine, which costs an `ObservableObject`
  in a codebase that is otherwise `@Observable` and a KVO callback that has to
  hop to the main actor to be legal under Swift 6 — all to grey the menu item
  out for the second a check is already running, which is harmless to ask
  twice. The menu reads it when it is built, which is often enough.
- **There is no app delegate, so the updater starts a turn of the run loop
  late.** Sparkle wants its controller made before any window, which is
  `ShellhandApp.init()` — but that runs *during* launching, too early to start
  checking. `start()` hops through `DispatchQueue.main.async`, the same
  deferral the inspector needs, rather than adding an `AppDelegate` to reach a
  single notification.
- **notarytool words a timed-out upload more than one way, and matching one of
  them is as good as no retry at all.** The retry loop tested for the literal
  string `timed out`. 0.0.4's run printed *"The request timed out"* and
  recovered, which looked like proof the loop worked; 0.0.5's printed
  `Error: HTTPClientError.connectTimeout` from the same flapping route, which
  contains no such phrase, so it gave up after **one** attempt and threw a
  whole signed build away. It matches a transport pattern now
  (`timed out|timeout|httpclienterror|could not connect|connection
  (lost|refused|reset)`, case-insensitively) and echoes what notarytool
  actually said, so the next wording is visible rather than silent. A rejection
  from Apple is about the thing being shipped and reads nothing like these, so
  widening this does not risk retrying a real refusal. The second run then went
  through on the first attempt, which is what a flapping route looks like.
  **0.0.9 is where that widening paid for itself**, and it needed both halves
  of it: **six** failed attempts in one run, three per submission, in **two**
  wordings — `_kCFStreamErrorDomainKey=4` for the app and
  `HTTPClientError.connectTimeout` for the DMG, the second being the exact one
  that cost 0.0.5 a signed build. Matching either alone would have thrown this
  release away twice. The echo is worth as much as the retry: both wordings are
  in the log, so the pattern can be widened again from evidence rather than
  from a guess at what Apple might say next.
- **No binary deltas, and the reason is in `scripts/release.sh`.** Sparkle
  makes them as soon as the updates folder holds two versions, and a delta is
  named for the **build** numbers it spans — `Shellhand2-1.delta` — so nothing
  in the filename says which release should serve it and the per-version URL
  rewrite cannot place it. `--maximum-deltas 0` stops new ones. It does **not**
  evict one already in the appcast: `generate_appcast` updates an appcast in
  place and keeps what it finds, so delete `build/updates/appcast.xml` and let
  it rebuild from the DMGs. The guard that catches an unplaced URL fired twice
  on 0.0.2 before this was understood, and it is the reason nothing broken
  reached the feed — **keep it**.
- **A restored window title can read as a live connection.** On launch the
  window briefly carries the title of a session from a previous run — a real
  shell prompt, `root@ip-…: ~`, with the host as the subtitle — before
  SwiftUI's own `.navigationTitle` overwrites it with the truth. It is state
  AppKit restores, not a session: nothing has connected, and in the same
  moment there is no `ssh` child process and no established socket. This cost
  two separate alarms in one sitting, both of them a production hostname that
  was never contacted. **The title is not evidence.** `pgrep -P <pid>` is:
  this app connects by spawning `ssh` on a pty, so no child means no
  connection.
- **Sparkle's preferences share the bundle-id domain with everything else**,
  which is the `@AppStorage` trap again with teeth. This machine carries
  `SUAutomaticallyUpdate = 1`, so an update installs here with nobody
  clicking Install Update — while neither that key nor
  `SUEnableAutomaticChecks` is in the shipped `Info.plist` or set anywhere in
  the source, so a new user gets Sparkle's own default and is asked first.
  Don't read this machine's update behaviour as the product's. The same
  domain still holds window frames for `SpikeView` and `snippets`, both gone
  for weeks, which is how old it is.
- **`auto_updates true` in the cask is doing a job.** The app updates itself
  past whatever version brew installed, so `brew list` goes on reporting its
  own record — 0.0.1 after the app has reached 0.0.2 — and brew correctly
  does not call it outdated. That is intended; don't "fix" the discrepancy.
- **The published history is one commit, and what came before it is in a
  bundle outside this repository.** This app began inside a larger project of
  ours, over a core written in another language and reached from Swift as a C
  archive — the tree carried that bridge, a `go.mod`, and a `spike/`
  directory of servers to measure against — and the lineage ran through the
  first **86** of 118 commits, not just the early ones. Going public, the
  docs were rewritten to be about this app alone, and a history that
  contradicted them on its first page was not worth publishing, so `main` was
  re-rooted on a single commit. The bundle has the names and the detail; this
  file does not need them. The 118 are at
  `~/Projects/shellhand-history-9e19a70.bundle`, which `git clone` reads
  directly: that is the **pre-reset bundle** the three notes above point at
  for the harnesses, for keys and credentials, and for `Core/CopyID.swift`.
  It is deliberately not pushed anywhere, so anything wanted back has to be
  fetched from it by hand.
  It cost nothing to do, because the repository was still private with no
  forks and no other clones — and **it would not be free a second time**.
  Don't re-root a history anyone has pulled.
- Commit messages are one line, no trailer. Don't push; that is the user's call
  each time.

## Where it stands

**This is cut back to an MVP.** Keys, credentials and snippets were built and
have been taken out again; the convention above says what went and what it
costs. What is left is the host list, the editor, tabs on real `ssh`, files
over SFTP, and import and export — and that is what to finish before anything
is added back.

The engine behind it is Swift. The terminal takes a palette — five ship, and
the config can add more. A fresh install lands on a welcome that counts the
machines in `~/.ssh/config` and offers them, a CSV, or a YAML file. Hosts are
filed by dragging them onto a group, and found by tag as well as by name —
several tags at once, narrowing. A group can set the terminal's colours for
everything beneath it, so production need not look like staging, and passes
down the user, the key and the jump host to everything under it. Transfers
queue rather than all starting at once, a couple at a time, with the rest
shown waiting their turn, and carrying a file onto one already there asks
first.

A host that takes only a password still connects — ssh asks on the pty, where
it can be typed — but Files cannot reach one, because an sftp child is given
`BatchMode=yes` and there is nothing left to answer a prompt with.

It has an icon: a shell prompt, chevron and block cursor, as an Icon Composer
bundle that macOS composites into the Tahoe squircle. `docs/app-icon.md` has
the directions that lost and why this one did not.

Release packaging is built: `scripts/release.sh` takes it from `xcodebuild`
to a notarized, stapled DMG, a signed appcast and an updated cask, and the app
checks for its own updates through Sparkle. Hopmeter's `scripts/release.sh` in
`~/Projects/nettoolbox` was the model, and most of what is worth knowing about
it is in the conventions above.

**0.0.1 through 0.0.9 are out**, each tagged at the commit its DMG was built from,
with the appcast on `main` and the cask in `cuonggt/homebrew-tap`.
The notarytool profile `Shellhand` is stored, the EdDSA key is backed up off
this disk, and release notes live at `docs/release-notes/<version>.md` —
write one per version or the update window comes up blank.

**Updating is proven.** An installed 0.0.1 found 0.0.2 on the live feed,
offered it with the release notes carried inside the appcast, downloaded it,
checked the EdDSA signature and installed it — and what landed verifies,
staples and passes Gatekeeper. 0.0.2 was cut for that purpose and earned it
twice over: it also exposed the delta bug above, which is unreachable on a
first release because there is no earlier version to make a delta against.
An installed 0.0.3 then took 0.0.4 the same way, from the menu item: what
landed is 0.0.4 (4), hardened, secure-timestamped, stapled, accepted by
Gatekeeper and verifying `--deep --strict`, with Sparkle relaunching the app
on a new pid and `brew info` dropping its upgrade arrow once the app matched
the cask. **But nobody was asked**, because this machine carries
`SUAutomaticallyUpdate = 1` while the shipped `Info.plist` sets neither that
key nor `SUEnableAutomaticChecks`. So that run proves the feed, the signature
and the install, and says **nothing** about the dialog a new user meets — the
"offered with the release notes, then installed on a click" half is still
proven only by 0.0.2.
**0.0.6 did it again, unasked and unwatched.** It was published, and minutes
later the installed copy at `/Applications/Shellhand.app` had replaced itself
— bundle mtime 06:34:24, its process started 06:34:26 — reporting 0.0.6 (6),
hardened, carrying the release build's own `Timestamp=27 Oct 2026 at
06:11:12`, `stapler validate` intact and Gatekeeper calling it a *Notarized
Developer ID*. Sparkle will not install an update whose EdDSA signature does
not check out, so that path is proven for 0.0.6 end to end: feed, signature,
download, install, relaunch. `brew list --cask --versions` still says
**0.0.1**, which is `auto_updates true` working as intended rather than a
discrepancy to fix. And **nobody was asked**, again, because this machine
carries `SUAutomaticallyUpdate = 1` — so the dialog a new user meets is
*still* proven only by 0.0.2, and no amount of updating on this Mac will
change that. Put the key aside first or it proves nothing — which was done
for 0.0.8, below.
**0.0.7 had not reached this machine's copy an hour after it went out — and
then it arrived at an hour and a quarter, which killed the explanation.** The
release was published at 10:49:45 on 2026-10-27 and the feed naming it pushed
at 10:50:06. The copy in `/Applications` had been relaunched at 09:02, Sparkle
looked then (`SULastCheckTime` 09:02:46 local), found 0.0.6 current, and —
with no `SUScheduledCheckInterval` set — was taken to be waiting its default
of a day. It was not. At **12:04:42** the bundle replaced itself with 0.0.7
and relaunched on a new pid at 12:04:44: hardened, stapled, Gatekeeper calling
it a *Notarized Developer ID*, carrying 0.0.7's own build timestamp. So 0.0.7
is proven end to end here as well — feed, signature, download, install,
relaunch — and **nobody was asked**, for the third time.
**What was wrong is the model, not the observation**, and this file has
already warned twice about building one from a single sighting. **Then it was
done again, in this very paragraph, within the hour** — which is why the
mistake is left in rather than tidied away. The first version of these lines
read *"Sparkle checks shortly after a launch, since the relaunch at 12:04:44
was followed by a check at 12:04:55"*, and reasoned on to a relaunch somewhere
between 09:02 and 12:04. That is one correlated pair turned into a rule, and
it is **false**: the same copy was quit and relaunched twice that afternoon
and `SULastCheckTime` stayed at 15:56:34 through both. The 12:04:55 check
followed an **update install**, which is not an ordinary launch. Nothing
replaces it — no account of when Sparkle looks is established here, and with
`SUScheduledCheckInterval` unset its documented default of a day is the only
answer anybody has. **Don't predict when a release will reach an installed
copy.** What is safe is the pair of bounds, both now seen on this Mac: a copy
may take one within ten minutes, and a copy that has just checked may not
hear for a day. The consequence is the certainty — an install relaunches the
app under whatever sessions are open — which is why **Check for Updates… is
still not triggered from here**. That is the user's call, and this arrival
shows it can happen without anyone making it.
What 0.0.7 shipped is the host-key fix — a question answered on a quiet
server no longer comes straight back, and a second Accept no longer types
`yes` into the shell — with the descriptor leak into terminals behind it.
**0.0.8 went out seven seconds after that install finished**, published at
12:04:49 at `8c83bb3` — close enough to be worth saying plainly: the copy
took 0.0.7, not 0.0.8, from the feed as it then stood. It leads with the folder
fix — a folder from a host arrived without its empty folders, and an empty
folder arrived as nothing while the transfer reported success — and carries
the two host-key ones behind it, a question wrapped across a narrow window
going unasked and an answered one coming back for an instant. The suite went
448 → 459. Verified before publishing and again after: `stapler validate` and
Gatekeeper on the DMG and on the app inside it, the DMG fetched back from
GitHub hashing to the digest in the cask, every appcast URL answering 200 with
the length the feed claims, all three items' notes byte-identical to their
`docs/release-notes` files, and the signature **reproduced** by re-signing the
DMG — Ed25519 is deterministic, so that is a check and not a second guess.
**And it arrived here nine minutes later**, unasked, which is the fourth time
running. The copy in `/Applications` replaced itself at 12:14:03 and
relaunched at 12:14:05, `SULastCheckTime` 12:14:04, carrying `Timestamp=27 Oct
2026 at 11:59:10` — the same secure timestamp read out of the DMG's own app
before publishing, so it is that build rather than a version string taken on
trust. The feed had turned over about three minutes after the push, and the
copy had it some seven minutes after that. So 0.0.8 is proven end to end as
well: feed, signature, download, install, relaunch. It is the sharpest
arrival yet, and it is what tightened the bound above from an hour to ten
minutes — written the same morning, on one sighting, and already too loose.
**The dialog a new user meets is proven now, on 0.0.8 — and it needed no
release.** Every version's DMG is still on disk, so the experiment is to
`ditto` **0.0.7** from `build/release/0.0.7/` over `/Applications`, put
`SUAutomaticallyUpdate` aside, and let the live feed — already offering 0.0.8
— do the rest. Sparkle's default is to **ask**, so an install that happens at
all has been through the dialog. It was, with the **release notes shown**:
offered, installed on a click, relaunched at 15:56:34 on 2026-10-27 as
0.0.8 (8) carrying `Timestamp=27 Oct 2026 at 11:59:10` — the same secure
timestamp as the app inside the published DMG, so it is that build —
hardened, verifying `--deep --strict`, stapled and accepted by Gatekeeper.
One release now holds the whole path instead of it being split across two:
feed, signature, the notes in the dialog, a click, install, relaunch.
**Nothing was published to do it and the app ended where it started**, which
is what makes it repeatable. The costs are the two to know about: quitting the
app drops any live session it is holding — check `pgrep -P <pid>` first, and
`lsof -a -p`, because `lsof` ORs its selectors without `-a` and will otherwise
list the whole machine's sockets — and borrowing the preference domain has a
trap of its own, noted above.

**0.0.9 carries the two transfer fixes that 0.0.8's folder work turned up**,
published at `bc3f309` and live on every surface — release, feed, cask and
tap. It leads with symlinks: left behind entirely coming down, and going up
turned into a copy of the target's bytes, an empty folder, or nothing at all.
Behind it is the folder whose `mkdir` was refused and said nothing about it.
The suite went 459 → 466. Verified the same way as 0.0.8, before publishing
and again after: `stapler validate` and Gatekeeper on the DMG and on the app
inside it, the DMG fetched back from GitHub hashing to the cask's digest,
every appcast URL answering 200 with the length the feed claims, all three
items' notes byte-identical to their `docs/release-notes` files, and the
signature reproduced by re-signing. **The `mkdir` fix waited a release on
purpose** — one conditional fix is a thin release, and holding it until the
symlink work gave it company made a note about one thing rather than two.

**Installing from the tap needs `brew trust` first.** Since Homebrew 7 a cask
from a tap outside Homebrew's own must be trusted once before it will load,
because casks can carry install scripts. This one carries none, but the gate
applies anyway, so the README spells the step out rather than letting an
install fail with an error that reads like the cask is broken.
