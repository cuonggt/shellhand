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
- `tools/` — `osmarks.swift`, which writes the distribution marks, and
  `osmarks-preview.swift`, which sheets them at the sizes that decide them;
  `icon.py`, which writes the icon bundle, and `icon-preview.sh`
  with `RenderIcon.swift`, which render it at the sizes that decide it. Not
  checks: `icon.py` is where the mark's geometry lives, so it is the only way
  to change the icon at all.
- `scripts/release.sh` — the whole of a release, from `xcodebuild` to the cask.
- `Casks/shellhand.rb` — the Homebrew cask, copied into the tap on release.
- `appcast.xml` — the update feed, served from `main`. Generated, never
  hand-edited.
- `docs/` — the architecture, the Phase 0 measurements, the engine comparison,
  the app icon, and the name.
- `docs/notes/` — the stories behind the rules below, one file per subject,
  moved there word for word: how each was found, what was measured, and what
  went wrong first. A rule here links to its story; read it before changing
  what the rule is about.

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
  **Swept twice more on 2026-10-28, and both came back with nothing to
  delete: 422 functions, 10 mentioned nowhere and all 10 framework
  conformances, and — on the narrow sweep below — 2, both SwiftTerm
  delegates.** The narrow one had found `Store.replaceAll` and `withProxies`
  that morning; one was deleted and the other wired up, which is why it is
  down to the two callbacks a framework calls.
  **Run both, because each has a blind spot the other covers.** The wide
  sweep counts a name's mentions *anywhere in the app or the suite*, so a
  function only the **suite** calls reads as live — which is how
  `Store.replaceAll` sat there superseded for months. The narrow one —
  declared under `Shellhand/`, mentioned in `Tests/`, nowhere else in
  `Shellhand/` — finds those, and has a blind spot of its own: it is
  token-based, so a generic name is drowned by ordinary English and invisible
  to it. That is how `OSRelease.name` escaped both.
  **Swept after 0.0.9: 392 functions, 15 unmentioned, and all 15 are
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
- **ssh's own config reaches the resolver**, from one walk of its blocks
  (`SSHConfigFile.route`): a host whose name is an entry for the same machine
  is reached by that name, one whose name is an entry for another machine is
  flagged, and a jump host or `ProxyCommand` the config adds is shown. `glob`
  is a linear scan and every `Include`d file is read once — the naive versions
  cost 5 seconds a snapshot and 48 seconds a parse. A run under test reads an
  empty ssh config; the real branch is out of the suite's reach, so prove a
  change to it by hand.
  → [ssh's own config](docs/notes/ssh-config.md#sshs-own-config)
- Swift 6 language mode, the app target MainActor by default. The engine is
  `nonisolated` throughout — mark extensions of its types `nonisolated` too, or
  their members pick the default back up.
- **An `async` wrapper over a `nonisolated` engine function does not move
  the work anywhere**: it runs on the caller's actor, and the `await` only
  looks like yielding. Read the compiler's *"no 'async' operations occur
  within 'await' expression"* rather than silencing it — but check which
  closure you are in, since one inside a `@Sendable` closure is real.
  → [async that does not move](docs/notes/engine.md#async-that-does-not-move)
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
- **The host pane shows the list, always, and the inspector says what a
  host is.** Where the pane is *looking*, `Browsing`, is kept apart from what
  is *selected* — a group is a place, a host a thing — so **don't collapse
  `browsing` back into `Selection`**. The grid's arrow keys follow
  `Views/GridMove.swift`, which takes the sections; a row's menu is
  `Views/RowMenu.swift`, handed its subject rather than reading the
  selection; and the inspector opens a turn of the loop after a selection.
  → [the host pane](docs/notes/window.md#the-host-pane)
- **A host is drawn with its operating system's mark**, learned by reading
  `/etc/os-release` over a connection of its own (`Core.osOf`), once a day per
  host — `Host.shouldAskOS`, on `osSeen`, which records the asking and not the
  answering — and never while the switch in Settings ▸ General is off. A mark
  is a file found by name, `os-<ID>.svg` with `ID_LIKE` behind it, made by
  `tools/osmarks.swift` from CC0 logos; they identify machines, so they belong
  on host rows and nowhere else. The folder's own `README.md` is the guard
  that it is bundled: don't exclude it.
  → [the OS marks](docs/notes/os-marks.md#the-os-marks)
- **The SFTP conversation is checked against `ScriptedSFTP`**, a server
  written in Swift in this process and reached through
  `SFTPClient.speaking(to:from:)`, for the misbehaviour no real server can be
  asked for. Do **not** `close()` a client made that way: its `Process` never
  ran, and terminating one that never ran raises.
  → [the scripted server](docs/notes/sftp.md#the-scripted-server)
- **Every suite that reaches an SFTP server carries
  `.timeLimit(.minutes(1))`**, which really does interrupt a continuation
  nothing will resume — checked, not assumed. **Conclude nothing about an
  episodic failure from a clean batch, however long.** Parse logs with
  something that fails loudly, and name `/usr/bin/sed` and `/usr/bin/paste` by
  path: the profile aliases `sed` to GNU's and `paste` to `pbpaste`, and BSD
  `sed` ignores `\|` without a word.
  → [the hang that roamed](docs/notes/sftp.md#the-hang-that-roamed)
- **Every SFTP request has a deadline** — `SFTPClient.Deadline`, 30
  seconds, and 120 for the handshake, which waits on ssh's own patience — and
  the failure names the request. Only that request fails, and `ended` stays
  unset so `close()` still ends the `ssh` child. `lateReplies` tells an answer
  that was slow from one that never came.
  → [the request deadline](docs/notes/sftp.md#the-request-deadline)
- **The SFTP stall was the suite's own server, never the engine.** A reader
  thread holds a `dup` of its own descriptor, made with `F_DUPFD_CLOEXEC` and
  closed by the thread — never a number borrowed from a `FileHandle` that can
  go away and see the number handed to the next pipe.
  `Tests/SFTPChurnTests.swift` guards it, 20,000 conversations in about two
  seconds. **When something is episodic, build a reproducer and measure both
  arms in one sitting before holding a theory.**
  → [the stall](docs/notes/sftp.md#the-stall-a-reproducer)
- **The SFTP conversation is held against OpenSSH's own `sftp-server`
  too**, in `Tests/SFTPRealServerTests.swift`, because the scripted server
  shares this project's misunderstandings — and was itself wrong for weeks.
  `-d` is where the server starts, not a jail: it runs as you, so every path is
  absolute and under `TestScratch`, and a test that only reads passes `-R`.
  OpenSSH sends at most 100 names per `readdir`.
  → [the real server](docs/notes/sftp.md#the-real-server)
- **A palette is chosen by looking at it**, from the inspector as well as
  the editor: `PalettePicker` draws each as a `TerminalMiniature` in its own
  colours, applies a choice at once and stays open, so two can be compared on
  the terminal behind. Test what a view draws by rendering it with
  `ImageRenderer` against colours rendered the same way; a `List` or a
  `ScrollView` will not render at all.
  → [the palette picker](docs/notes/terminal.md#the-palette-picker)
- **A copy running from the build products did *not* stop a suite run**, which
  is narrower than this file has been claiming. The note above says what stops
  `xcodebuild test` is "one launched from the same build products the test
  host wants — the copy you have been looking at in `-derivedDataPath`".
  Today a copy from exactly that path was running, with a live `ssh` under it,
  and the run came back **539 passed**. So that is not the condition, or not
  the whole of it. What *is* still true is that **`window-check.sh` cannot
  run beside another copy** — System Events addresses a process by name and
  two make every lookup ambiguous — and that refusal is the thing to work
  around, by addressing the copy by its **`unix id`** rather than by name.
- **The terminal's text is inset 8pt and its background still runs edge to
  edge**: `padding`, a `frame` filling the pane at `.topLeading`, and a
  `background` in `TerminalSession.background`, taken from the palette —
  never `nativeBackgroundColor`, which reads back white. A container `NSView`
  was tried first, and painted over the tab strip.
  → [the inset](docs/notes/terminal.md#the-inset)
- **Option types characters unless Settings says Meta.** SwiftTerm's
  `optionAsMetaKey` defaults to true, which left `@`, `|`, `{}` and `[]`
  untypeable on many layouts up to 0.0.11. An open session follows the switch
  through `UserDefaults.didChangeNotification`, acting only when the setting
  differs from the one it last took.
  → [Option](docs/notes/terminal.md#option)
- **The terminal's font is a choice in Settings ▸ Terminal**, SF Mono by
  default. `TerminalFont` decides what is offered, and falls back to SF Mono
  for a family not installed or not monospaced. Open sessions follow through
  the same defaults observer and keep their size; Actual Size keeps the
  family. → [the font](docs/notes/terminal.md#the-font)
- **Clear Scrollback is ⌥⌘K**, and ⌘K stays Quick Connect's. It shrinks
  the history to nothing and back through `changeScrollback` — never by
  feeding `ESC [3J`, which acts on the buffer in front only and could land
  inside an escape sequence — and `TerminalSession.scrollback` names the size
  so it can be put back.
  → [Clear Scrollback](docs/notes/terminal.md#clear-scrollback)
- **Closing asks before it drops a live session**, by one rule,
  `Views/Closing.swift`: live is `.connected`, and nothing stored means ask.
  ⌘W, ⌘R and a tab's × ask through `ContentView.end`; the window through
  `ClosingGuard`, which stands **in front of** SwiftUI's own window delegate
  and is held by the window; ⌘Q through `ShellhandAppDelegate`, over every
  window's `Sessions`. ⌘W never reaches the window, so with the Hosts tab in
  front it does nothing. Sweep preference keys as well as functions: this
  switch did nothing for eleven releases.
  → [closing](docs/notes/window.md#closing)
- **SwiftTerm leaks every descriptor not marked close-on-exec into every
  terminal's child**: its `fork(andExec:)` goes straight to `execve`, so a
  shell forked anywhere in the process holds whatever pipes are open, and a
  reader waiting for their end waits for ever. The app had the same leak. A
  teardown is bounded regardless: `RealSFTPServer.stop` ends its server after
  five seconds.
  → [what SwiftTerm leaks](docs/notes/engine.md#what-swiftterm-leaks)
- **Every descriptor this project opens is close-on-exec**: a pipe from
  `Pipe.marked()`, `open` with `O_CLOEXEC`, a `dup` with
  `fcntl(_, F_DUPFD_CLOEXEC, 0)`; `FileHandle`'s readers and writers already
  are. **`Forking`'s lock**, in `Core/Descriptors.swift`, holds both of
  `TerminalSession`'s starts and every pipe's making-and-marking, which closes
  the race macOS's missing `pipe2` leaves, and tests check each start waits on
  it. Upstream declined the fix in the child (SwiftTerm #716).
  → [close-on-exec](docs/notes/engine.md#close-on-exec)
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
- **Write through a descriptor, never `FileHandle.write(contentsOf:)`**,
  which raises an ObjC exception no Swift `catch` can catch — it killed whole
  runs. `SFTPClient.writeAll(_:to:failing:)` is the one loop; a descriptor
  written to gets `F_SETNOSIGPIPE`, or a dead reader ends the process without
  a word; and a handle's `fileDescriptor` is taken while it is certainly open.
  → [writing to a descriptor](docs/notes/engine.md#writing-to-a-descriptor)
- **A size the far end gave must match exactly, zero included, and a size
  it did not give is not zero** — flattening the two left an empty file
  uncarryable up to 0.0.3. Uploads have no closing check, on purpose.
  → [empty files](docs/notes/sftp.md#empty-files)
- **A folder is carried whole, empty folders included**: `walk` records
  folders as well as files, and the destination and every folder are made
  before any file lands. An upload's `makeFolder` tolerates only a folder
  already there, found by asking the far end, since SFTP 3 answers a name
  already taken and a read-only disk with the same `SSH_FX_FAILURE`.
  → [empty folders](docs/notes/sftp.md#empty-folders)
- **A symlink is carried as a symlink, both ways** — its target copied
  verbatim, nothing followed. Ask what a path is with `attributesOfItem`
  (`lstat`), never `fileExists(atPath:isDirectory:)`, which follows the link.
  OpenSSH reads `SSH_FXP_SYMLINK`'s two paths target first, the reverse of
  draft 02. → [symlinks](docs/notes/sftp.md#symlinks)
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
- **A local shell starts at home**: `startProcess` is given
  `currentDirectory:`, since an app launched by LaunchServices has `/`. Its
  test asks the shell itself, through a file it writes, rather than reading
  the screen. → [the local shell](docs/notes/terminal.md#the-local-shell)
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
- **`Model/Files.swift`'s orchestration is tested with local panes**,
  which need no session: the open guard, and the replace question with a copy
  really parked on its continuation. Do not walk `parent()` up out of a
  temporary directory; make a parent of your own.
  → [testing the file panes](docs/notes/sftp.md#testing-the-file-panes)
- **`FilePlace.opens` exists so that one open can be told from two**,
  because the guard on `opening` leaves no other trace. Test that race by
  making both tasks before either runs, never by polling — and a retry after
  a failure must stay allowed.
  → [one open or two](docs/notes/sftp.md#one-open-or-two)
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
- **Every walk over the group tree lives in `Model/Tree.swift`**, built
  once per snapshot, because each walk carries a guard against a group that
  became its own ancestor, and the suite turns a loop through all of them — a
  rotted guard hangs the app. A host needs its own group open and everything
  above it; a group needs only its parents.
  → [the tree](docs/notes/engine.md#the-tree)
- Menus live in `Shellhand/App/Commands.swift` and reach the front window
  through `AppActions`, a focused scene value. Keyboard shortcuts belong there
  rather than on a button.
- **A menu is named for what its items act on, and that gates it**:
  **Host** needs one selected, **Terminal** a session in front, and the app
  menu's Hosts and SFTP nothing. There is no Library menu and nothing is
  called Library, except `@AppStorage("libraryLayout")`, which keeps its name
  because renaming a stored key resets everybody's choice.
  → [menus](docs/notes/window.md#menus)
- Text size sits in **Terminal**, not View: "Bigger Text" in a View menu does
  not say bigger than what, and these size the terminal and nothing else.
- **The toolbar is placed by what each item acts on**, like the menus:
  Quick Connect, New Host and SFTP over the sidebar, and the inspector toggle
  alone at the trailing edge. Keep `paneToolbar` even with one item, since
  each column needs its own `.toolbar`.
  → [the toolbar](docs/notes/window.md#the-toolbar)
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
- **Connect is not in the toolbar**: it is in the inspector, on ⌘↩ in the
  Host menu, and on ⏎ in the list. A double-click connects through
  `contextMenu(forSelectionType:)`'s `primaryAction` on rows and
  `NSApp.currentEvent?.clickCount` on cards — **never a `TapGesture(count: 2)`,
  which made every single click wait**. Look for the native hook before
  reaching for a gesture.
  → [connecting from the list](docs/notes/window.md#connecting-from-the-list)
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
- **Shellhand ▸ Hosts goes around `AppActions`**, which is nil exactly when
  the host window is not in front: `HostsWindow.front()` finds the window by
  its identifier instead. SFTP fronts a browser already open the same way,
  with `FilesWindowController.front()`, before asking `AppActions` to open one.
  → [Hosts and SFTP](docs/notes/window.md#hosts-and-sftp)
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
- **Never change the inspector in the same update that swaps the pane**:
  it crashes, intermittently, as a reentrant table-view operation. Defer it a
  turn of the loop with `DispatchQueue.main.async`, and prove a change here
  with a dozen round trips, the previous build as the control.
  → [the inspector crash](docs/notes/window.md#the-inspector-crash)
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
- The **welcome stands in for the hosts tab, not for the window.** On a fresh
  install there is no list to look at, and "All hosts, 0 hosts" is not what to
  meet — but that reason says nothing about a terminal somebody has just
  asked for. It replaced everything while the list was empty, so **a local
  shell opened on a fresh install really started** — a `-zsh` with a pid,
  confirmed — behind the welcome, with the tab strip hidden too, and nothing
  could see it, reach it or close it. `Panes.welcoming` and `Panes.showsTabs`
  hold the rule now: the welcome only when the hosts tab is in front, and the
  strip the moment anything is open. Found by trying to do an ordinary thing
  — open a local shell — on an empty store, which is also the only state it
  was ever broken in.
- The **Window menu lists the sessions too**, with ⌘1 to ⌘9 for the first
  nine. That came in with the column and stays without it: a keyboard way to
  the fourth session is worth having whatever the switcher looks like, and
  one menu is cheaper than a second switcher.
- **⇧⌘] and ⇧⌘[, and ⌃⇥ and ⌃⇧⇥, step through the strip** by
  `Panes.stepping`, the Hosts tab included, going round. The first pair are
  Window menu items; ⌃⇥ is `StepsTabs`, a local key monitor that sees the key
  before the terminal can, acts only on keys meant for the host window, and
  lets it through when there is nowhere to go.
  → [the tab keys](docs/notes/window.md#the-tab-keys)
- **⌘T opens another of the session in front**: the same host, or another
  local shell for a local shell. Only with the hosts in front does it open
  the host the list has selected. It used to open the selection whatever was
  in front — connected to `db` through ⌘K with `web` picked, ⌘T opened
  `web`, and with a group picked it was greyed out beside a live terminal —
  because it was gated on `hasHost`, which is about the list. The rule is
  `Panes.newTab`, and the item is gated on what it returns. **A session on a
  host since deleted opens nothing**, not the selection: the argv comes from
  the list, and opening some other machine instead is the surprise this
  exists to end. The host is taken from the list as it is now, not from the
  session's copy, so an edit made since is the one connected with.
- **A tab has a menu of its own** — Reconnect, Duplicate, SFTP, Close Tab
  and Close Other Tabs — and each item is handed its session through
  `TabActions`, since right-clicking a tab does not bring it in front.
  → [the tab menu](docs/notes/window.md#the-tab-menu)
- **File ▸ Export…** writes the list the way the import sheet's Export… does,
  where it used to live alone — behind a sheet called Import. No key: ⇧⌘E,
  the usual one, is Edit Group's. `YAMLDocument.defaultFilename` names the
  file once for both, and a save the disk refuses is said through the
  window's alert (`HostStore.report`) rather than dropped; Cancel is not a
  failure.
- **Help ▸ Report a Problem… opens `.github/ISSUE_TEMPLATE/problem.yml`**
  with its `version` and `macos` fields filled from the link, and carries
  nothing else: no host name goes into a URL. **Those ids are as permanent as
  `SUFeedURL`**, and `HelpTests` reads the form to hold the link to it;
  `config.yml` keeps blank issues allowed for the link 0.1.0 shipped. Quote a
  placeholder that looks like a number. → [Help](docs/notes/window.md#help)
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
- **Closing the SFTP window ends both panes' sessions**, through
  `FilesModel.close()`, answering a replace question still up first — for
  weeks it left an `ssh` child per pane running until quit, while a comment
  beside it said the opposite.
  → [closing the window](docs/notes/sftp.md#closing-the-window)
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
- **Carrying a file onto one already there asks first, once for the whole
  batch**, and a local copy that fails is filed as a failed transfer through
  `copyOnThisDisk`, never swallowed by a `try?`. `HostStore.preview(of:)`'s
  swallowed failure was weighed and left on purpose.
  → [replacing](docs/notes/sftp.md#replacing)
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
- **A terminal that has heard nothing is blank, not empty**:
  `getBufferAsData` hands back its own blank rows, so the test for output is
  blank once whitespace is trimmed, or every session reads as connected on its
  first look. The rule and the buffer's blankness are pinned in different
  tests, since SwiftTerm may change the second.
  → [blank, not empty](docs/notes/terminal.md#blank-not-empty)
- **A host-key question is found however the terminal wraps it**: the
  tail is sixteen rows, rejoined before matching with whitespace dropped from
  both sides, and `question(in:)` finds where the warning and the fingerprint
  start, so the dialog shows them whole down to about three columns. The
  fixtures are OpenSSH's real question cut at real widths, never typed.
  → [wrapped questions](docs/notes/terminal.md#wrapped-questions)
- **A host-key question is live only while nothing follows its closing
  `?`**, since a pty echoes the answer onto the question's own row. An answer
  records the question it answered, and `SessionProgress.next` holds back
  that question, and only that one, until the session is through — so a jump
  chain's next hop is still asked.
  → [answered questions](docs/notes/terminal.md#answered-questions)
- **The watchdog's decision is `SessionProgress`; `watch()` is only the
  looking.** The loop sleeps, ticks, reads ssh's log and looks; what it makes
  of the screen is one pure function, which is why there are tests for it at
  all. `watch()` is deliberately not private, and `logPath` is readable, so a
  test can run the real loop against a view it has fed through SwiftTerm's own
  `feed(text:)` — no pty, no process, no unknown host. `ticks` is what tells
  "the watchdog ran and the state did not move" from "the watchdog never ran",
  and there is a test for each.
- **The scrollback is 10,000 lines, and the screen is read only around
  connecting**: `SessionProgress.watches` says yes while connecting, while a
  question is up and for `settling`, two minutes, after coming through. Every
  read is the whole history, since SwiftTerm 1.99's view gives the app no part
  of the buffer, and stopping at `.connected` would miss a jump chain's next
  hop. **Check what SwiftTerm's view exposes, not the class behind it.**
  → [the scrollback](docs/notes/terminal.md#the-scrollback)
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
- **⌘K connects to machines not in the list** — `host`, `user@host:port`,
  `[v6]:port` or an `ssh://` link, read by `QuickConnect.destination` and
  ranked by `QuickConnect.rows`. Nothing typed may start with `-`, which ssh
  would read as an option. The machine is a `Host` with an empty id, which
  keeps it out of the list, the inspector and the OS question.
  → [typed destinations](docs/notes/window.md#typed-destinations)
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
  - **`click at` is inert here too, and that was proven with a control rather
    than assumed.** Clicking the exact centre of a real `AXRow` — geometry
    read off the element, 28pt high — left the inspector empty, which looked
    exactly like the double-click gesture on those rows stealing the click
    that selects. The same click against a build with **no gesture attached**
    did nothing either. So a click probe here cannot tell a working click from
    a broken one, and any conclusion drawn from one is worth nothing. **What
    that costs is real:** whether a click selects is not checkable from a
    script in this app, so anything riding on it cannot be settled here at
    all. The pane's double-click went through `onTapGesture` and then
    `simultaneousGesture` on that reasoning, and in the end came out
    altogether — not because it stole the click, but because it **delayed**
    every one of them, which is a thing no script here could have seen and a
    user saw at once. When a question is only answerable by a hand on the
    mouse, ask for the hand rather than building around the gap.
  - **An `AXOutline`'s children include an `AXColumn`**, whose centre is the
    middle of the whole list — four hundred points below the rows on a short
    one. A first pass clicked it and read the empty result as a broken click.
    Filter to `role is "AXRow"`, and sanity-check the height: a row is tens of
    points tall, the column is hundreds.
  - **Keyboard paths, though, are fully drivable — including connecting.**
    Arrow to a host in the pane's list, press Return, and a session opens:
    seen as the **Terminal** menu's gate going false to true, the same trick
    `Edit Host…` is read with. Drive it against a host at **`127.0.0.1` port
    1**, which refuses instantly with status 255 and reaches nothing — the
    rule this file already sets for Quick Connect, and the reason a check can
    exercise connecting at all. Checked the way round that matters: with the
    `onKeyPress(.return)` handler taken out, the gate stays false.
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
  is keyed by the bundle id and a scratch store does not protect it.
  **It covers the pane and the inspector too**, since the host list stopped
  being swapped out for a host's details: that the pane holds an `AXOutline`
  of its own with rows in it, and that *"What will run"* — drawn by
  `HostDetailView` and nothing else — is on screen, which proves in one
  string that the inspector is open and describing a host rather than on
  "Nothing selected". Checked the way round that matters: with the pane put
  back to swapping itself for the details, it fails with *"the pane has no
  list of its own"*.
  **And it has to choose the layout, which is the `@AppStorage` trap wearing
  a new hat.** Only list mode is a `List` with a selection — a `LazyVGrid`
  has none, so grid mode is buttons and no outline at all. This machine's
  preference is `grid`, so the first run of that assertion failed against a
  build that was perfectly correct. The check writes `libraryLayout` itself
  now; the domain is already borrowed and given back, so it costs nothing.
  **And then the identical trap sprang a second time the same day**, which is
  why this says *every* preference rather than naming one: `hostInspector`
  decides whether the inspector is on screen, a user who shuts it hands the
  check a window with no inspector in it, and the assertion failed against a
  build that was — again — perfectly correct. Pin everything the assertions
  lean on, and do it the moment an assertion starts leaning on something.
  **Give a text probe room.** The first one stopped at depth 8 and the dump
  ended at "Jump host", so an inspector drawing everything read as one that
  had not filled in. Depth 16 reaches the bottom of it. A probe that cannot
  see the thing it asserts on is worse than no probe — it fails against
  working code, which is the most expensive kind of wrong.
  **A handler may return one element reference, but not a list of them.**
  `findOutline` returns a single `AXOutline` and always has; collecting
  several into a list and returning that fails, which is why `findNthOutline`
  counts through a `property` instead. Ungated routes are still the cheapest
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
  capture away if it was not. **`-l` does photograph one window alone** — the
  window and nothing over it, transparent corners and all — but only given a
  CoreGraphics window number: `kCGWindowNumber` out of
  `CGWindowListCopyWindowInfo`, filtered to the process's pid and layer 0.
  This file used to say `-l` falls back to the whole screen; that was
  measured with some other number, and a window id from System Events is
  not one. Proven taking the README's picture on 2026-10-29.
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
- **Read YAML through `Core/YAMLDocuments.swift`**, never
  `try load_all(…).compactMap { $0 }`: Yams's sequence keeps a scan error in
  its `error` and simply ends, so that expression reads a broken file as no
  documents — which is how `Config.parse` and `Portable.parse` read one, in
  every release up to 0.1.0.
  → [YAML that is not YAML](docs/notes/engine.md#yaml-that-is-not-yaml)
- **A settings file that cannot be used is said, not dropped**:
  `LaunchConfig.read` keeps the problem and the window puts it up, in state of
  its own because a refresh that works clears `store.lastError`. The launch
  read was a `try?` in every release up to 0.1.0 — a `try?` whose fallback is
  a plausible value reads as handling a failure rather than dropping it.
  → [the settings file](docs/notes/engine.md#the-settings-file)
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
  measured. **On 0.0.10 both came back at `source-age 0` at once**, which is
  the same rule from the other side: nothing had asked for either path for
  hours, so there was no stale copy to serve. An instant verification is not
  evidence that caching is absent — only that nobody had looked lately.
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
  **And it orders and prunes by the integer build, not by the version
  string** — which 0.0.10 was the first release able to show, since `0.0.10`
  sorts **below** `0.0.9` as text. Had anything compared the short version as
  a string the feed would have offered the wrong release, and an app on 0.0.9
  would never have seen anything newer. It does not: the feed came out builds
  10, 9, 8, newest first, with 0.0.7 retired and 0.0.8 kept. Checked rather
  than reasoned, because the appcast step is skipped in a dry run and this was
  the one release where a string comparison could have surfaced.
- **`Updates` deliberately does not bridge `canCheckForUpdates`.** Sparkle's
  own sample publishes it through Combine, which costs an `ObservableObject`
  in a codebase that is otherwise `@Observable` and a KVO callback that has to
  hop to the main actor to be legal under Swift 6 — all to grey the menu item
  out for the second a check is already running, which is harmless to ask
  twice. The menu reads it when it is built, which is often enough.
- **The updater starts a turn of the run loop late, from before there was an
  app delegate.** Sparkle wants its controller made before any window, which
  is `ShellhandApp.init()` — but that runs *during* launching, too early to
  start checking. `start()` hops through `DispatchQueue.main.async`, the same
  deferral the inspector needs, rather than adding an `AppDelegate` to reach a
  single notification. There is one now, `ShellhandAppDelegate`, for ⌘Q; the
  hop works, so it was left where it is.
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

**0.0.1 through 0.0.12, and then 0.1.0 and 0.1.1, are out**, each tagged at
the commit its DMG was built from, with the appcast on `main` and the cask in
`cuonggt/homebrew-tap` — whose clone on this Mac is Homebrew's own, under
`/opt/homebrew/Library/Taps`; see 0.0.12 for what it needs before a cask is
copied in.
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

**0.0.10 is the host window's shape rather than a fix**, published at
`87ba111` and live on release, feed, cask and tap. Picking a host no longer
takes the list away: the list stays with the host highlighted, its details
moved to the inspector, and where the pane is **looking** came apart from what
is **selected** — see the `Browsing` note above, and do not put them back
together. The suite went 466 → 479. Verified the way 0.0.8 and 0.0.9 were,
before publishing and again after, with the one addition this release needed:
the feed's ordering, since `0.0.10` sorts below `0.0.9` as a string.
**What it cost to get right is worth more than the feature.** A double-click
to connect went in, was made a `simultaneousGesture` to stop it taking the
click, and came out altogether a day later because it made **every** single
click wait out the system's double-click interval. No probe here could have
seen that — a synthetic click does nothing in this app, proven with a control
— and a user felt it on the first click. Ask for a hand on the mouse when the
question is only answerable by one.

**0.0.11 finished what 0.0.10 started**, published at `3f8e02d` and live on
release, feed, cask and tap. Clicking a host opens the panel on the right, two
clicks connect, a right-click gives the sidebar's own menu acting on the host
clicked rather than the one selected, the arrow keys reach the list in rows or
cards with Return connecting, and a file dropped from Finder that cannot be
copied says so. The suite went 479 → 495. Verified the way the last three
were, and Apple's notary route was flapping again — a credentials check timed
out and answered on retry, and the DMG's submission needed one attempt before
it went through, which is the widened pattern earning its place for the second
release running.
**Every one of those five came from somebody using the app**, not from a test
or a sweep: the layout change shipped in 0.0.10 and the gaps in it showed up
within a day of real use. The double-click alone took three attempts — see
the pane's own note — and two of them were handed over as done before a hand
on the mouse said otherwise. **The suite is 495 checks and it could not have
found any of this.** That is not an argument against the suite; it is the
reminder that what it covers and what a user meets are different sets, and
this release is entirely the second one.

**0.0.12 is the first release that reads your machines and your ssh config,
not only your list**, published at `86b345d` and live on release, feed, cask
and tap. It leads with the marks: a host is drawn with its distribution's own
logo — 30 of them, generated by `tools/osmarks.swift` from the CC0 sources in
`tools/logos/` — learned by reading the host's own `/etc/os-release` over a
connection of its own, and asked again once a day so a rebuilt machine
corrects itself. Then what ssh's own config does to a host, all of it built,
drawn and tested in earlier releases and never handed anything to work with:
the clash warning fires, the jump host row stops saying a host has none while
ssh takes it through a bastion, a `ProxyCommand` gets a row of its own, and a
host named for an entry on the same machine is reached by that name. Behind
those, four fixes — Option types characters, with Meta a switch in Settings;
closing, reconnecting or quitting asks before it drops a live session; an
`Include` that branches back into its own folder no longer holds the welcome
and the import up for a minute; and a local shell opened on a fresh install is
no longer hidden behind the welcome — with the palette picker in the inspector
and the inset terminal beside them. The suite went 495 → 570.
Verified the way 0.0.8 to 0.0.11 were. **Before publishing:** Gatekeeper,
`codesign --deep --strict` and `stapler validate` on the app **inside** the
DMG as well as the one in the build products; the DMG's staple; all three feed
items' notes identical to their `docs/release-notes` files; the 0.0.12 item's
length equal to the DMG's size; and the signature reproduced by re-signing.
**After:** every appcast URL answering 200 at the length the feed claims; the
DMG fetched back from GitHub hashing to the digest in **both** casks, this
repository's and the tap's as GitHub serves it; the feed's blob on `main`
matching the local one through the API; and the release page's notes identical
to the file. Apple's notary route held this time — both submissions went
through on the first attempt — and the CDN in front of the feed had nothing
cached, serving 0.0.12 at `source-age 0`: nobody had asked lately, which is the
0.0.10 rule again.
**Hash the DMG as it streams, not from a saved copy.** The first after-check
deleted a scratch folder and wrote the DMG to disk, and it was refused;
`curl -sL <url> | shasum -a 256` asks the same question and needs neither.
**The tap is Homebrew's own clone, at
`/opt/homebrew/Library/Taps/cuonggt/homebrew-tap`, and it was three commits
behind its remote**: 0.0.9 to 0.0.11 had been committed outside it, so a cask
copied straight in would have been committed on a stale base. Fetch and
`git merge --ff-only origin/master` first; once the cask is copied in, the diff
should be the `version` and the `sha256` and nothing else. Every cask update
has used the message "Update the shellhand cask to <version>".
**Two of its fixes came from reading, not from use and not from the suite.**
The close switch had done nothing since 0.0.1 and Option had been Meta in every
release, and neither showed from where anybody stood: the suite presses no
keys and reads no preferences, and on a US keyboard Option-as-Meta looks like a
feature. A review that grepped one preference key and read SwiftTerm's
`keyDown` found both in one sitting. And the drive that proved the closing
questions on screen corrected a claim the code and this file had both just
made — that ⌘W with the Hosts tab in front closes the window. It closes
nothing.

**0.1.0 is what people expect of a terminal before they expect anything
new**, published at `00c7b77` and live on release, feed, cask and tap. It
leads with Quick Connect reaching machines that are not in the list —
`user@host:port`, a bare host, `[v6]:port` or an `ssh://` link, offered as one
more row and opened as a `Host` with an empty id, so nothing is saved. Then
the tabs: ⇧⌘] and ⇧⌘[, and ⌃⇥ and ⌃⇧⇥, step through the strip, ⌘T opens
another of the session in front rather than the host selected, and a tab has
a menu of its own. Behind those, the terminal's font can be any monospaced
family installed, Clear Scrollback is on ⌥⌘K, Export… and a Help menu are
where people look for them, and the inspector's destination has a line of its
own instead of breaking inside an address. The suite went 570 → 622.
Verified the way 0.0.12 was, and everything passed both times. **Before
publishing:** Gatekeeper, `codesign --deep --strict` and `stapler validate`
on the app **inside** the DMG as well as the one in the build products; the
DMG's staple; all three feed items' notes identical to their
`docs/release-notes` files; the 0.1.0 item's length equal to the DMG's size;
the signature reproduced by re-signing; and the cask's digest the DMG's.
**After:** every appcast URL answering 200 at the length the feed claims; the
DMG streamed back from GitHub hashing to the built one and to **both** casks,
this repository's and the tap's as GitHub serves them, which say 0.1.0 and
are the same file; the feed's blob on `main` matching the local one through
the API; and the release page's notes byte-identical to the file. Both
notarizations went through on the first attempt again, the CDN had nothing
cached for the feed or the tap's cask and served 0.1.0 at `source-age 0`, and
the tap's clone was level with its remote this time — 0.0.12 was committed
from it — so the cask went straight in, its diff the `version` and the
`sha256` and nothing else.
**The first version past 0.0.x, and nothing in the pipeline leaned on the old
shape**: the per-version rewrite put `Shellhand-0.1.0.dmg` under `v0.1.0`,
and the feed came out by build — 13, 12, 11 — with 0.0.10 retired as old
versions are. As text `0.1.0` sorts above `0.0.12` anyway, so this release
could not have caught a string comparison; 0.0.10 was the one that could, and
it held.
**`gh … --jq .body` reads one line longer than the notes it came from**, and
that is the check, not the release. The body keeps the file's own final
newline and `--jq` prints one more, so a `cmp` against the file fails on a
blank last line that nobody wrote. Compare the exact string instead — `body`
out of `gh api repos/cuonggt/shellhand/releases/tags/v<version>`, read as JSON
— which came back identical, 2,954 characters each.
**The copy in `/Applications` was still on 0.0.11 half an hour later**, and
that was no delivery failing: its `SULastCheckTime` was 23:26 on 28 October,
before 0.0.12 went out at 10:18 the next morning, so it had not looked since
either release existed. Nothing here asked it to, which is still the rule.

**0.1.1 is the first release from the list for a second user, and most of it
is things that used to fail without a word**, published at `4a1a8a3` and live
on release, feed, cask and tap. A terminal keeps 10,000 lines, which waited
on the watchdog reading the screen only around connecting — see its note
above, and the jump-chain catch that shaped it. A settings file that cannot
be used is named by an alert when the window opens, where every release before
ignored it, and a YAML import with a mistake in it is refused with the line
and column instead of arriving as an empty list. Settings ▸ General has a
switch for asking hosts what they run, on as before, and Report a Problem…
opens the issue form, with Discussions on for questions. The suite went
622 → 643.
Verified the way 0.1.0 was, and everything passed both times. **Before
publishing:** the script's own checks — signed, timestamped, universal, 0.1.1
(14), both notarizations accepted on the first attempt, Gatekeeper accepting
the app and the DMG — and on top of them Gatekeeper, `codesign --deep
--strict` and `stapler validate` on the app **inside** the DMG; the DMG's
staple; all three feed items' notes identical to their files, each served
from its own release; the 0.1.1 item's length equal to the DMG's size; the
signature reproduced by re-signing; and the cask's digest the DMG's.
**After:** every appcast URL answering 200 at the length the feed claims; the
DMG streamed back from GitHub hashing to the built one and to **both** casks,
which say 0.1.1 and are the same file; the feed's blob on `main` matching the
local one through the API; and the release page's notes byte-identical to the
file, compared as JSON this time. The CDN had nothing cached for either path
again, and the tap's clone was level with its remote, so the cask went
straight in, its diff the `version` and the `sha256`.
**Warnings, and one false alarm, none of them the release's.**
`generate_appcast` printed ten "failed to move" warnings: it retires every DMG
past the feed's few into `build/updates/old_updates`, and copies of them from
earlier runs sit both there and in the folder, so every move collides. It is
local housekeeping, and the feed checked out. The false alarm was the
pre-publish check calling the signature mismatched when it was identical:
**a base64 signature ends in `=`, so a greedy `sed 's/.*="//'` runs on to its
padding and leaves nothing.** Anchor the extraction at the attribute's name.
It is the `--jq` lesson in another key — when a check fails, read both values
before believing either.
**One thing it ships is still unseen working**: the issue form's version
fields arriving filled in rests on GitHub's documentation, since nothing here
could open the page signed in. The Hosts section was looked at after
publishing, on a scratch copy opened with `open -g` and Settings opened by
AXPress on its menu item: the switch, its caption and the corrected "read
each time Shellhand opens" all read back, and the window photographed as
built. **System Events would not name that window**: matching `name of` it
against "General" found nothing and `size of` it failed, while
`value of attribute "AXTitle"` said "General". Find a Settings window by
that attribute or by what it holds.
**The copy in `/Applications` still has 0.0.11, and that is no puzzle any
more**: it is not running, and Sparkle only looks while the app is open — its
`SULastCheckTime` was still 23:26 on 28 October after 0.1.1 went out.

**The README's picture was retaken on 2026-10-29**, from a scratch copy on a
host list of its own: Production with EU and US inside it, Staging, a few
ungrouped machines, the marks of eight distributions and one host never
asked, all on documentation addresses — and `db-01` in the inspector, since
it inherits its user, key and palette from Production and its jump host
from US. Four things to know before taking it again:
- **Launch it with `XCTestSessionIdentifier` set**, which is `TestRun`'s
  switch. A copy launched the ordinary way reads the real `~/.ssh/config`
  into the inspector, and a `Host *` there would put somebody's own bastion
  or `ProxyCommand` into a public image. The switch sends ssh's config to an
  empty scratch file and changes nothing else that `--db` and `--config` do
  not already override.
- **Arrow Up through the pane, not Down.** Its list leads with its groups,
  and arrowing onto a group goes into it — Down from nothing walked into
  Production, then EU. Up from nothing starts at the last host and climbs
  through hosts alone, so the pane stays on all of them.
- **The inspector's header wrapped inside an address**, which is why that
  picture's addresses are short. Its subtitle shared a row with Edit and
  Connect, so `deploy@203.0.113.21 port 2222` broke as `deploy@203.0.113.2` /
  `1 port 2222`. **Fixed since**: the destination has a full-width line of
  its own under the name and the buttons, keeps to one line and is cut in
  the middle when longer, with the whole of it on the tooltip; the name
  beside the buttons is cut the same way. `DestinationLine` is its own view
  so `HostHeaderTests` can render it at 200pt and measure one line's height —
  with a control first, plain text that long wrapping at that width, since
  without it a renderer handing back one fixed size would pass for nothing.
  Checked the way round: with `.lineLimit(1)` taken off, only the long
  destination's check fails. The README's picture was taken again after the
  fix, with the same list and drive, so it shows the header as it is now.
- **Size the window before arrowing**, through System Events, at
  1220×798 points — the old picture's — or it comes up at whatever frame
  this Mac last saved. The preference domain is borrowed for the run anyway,
  for `libraryLayout` and `hostInspector`.

**Installing from the tap needs `brew trust` first.** Since Homebrew 7 a cask
from a tap outside Homebrew's own must be trusted once before it will load,
because casks can carry install scripts. This one carries none, but the gate
applies anyway, so the README spells the step out rather than letting an
install fail with an error that reads like the cask is broken.
