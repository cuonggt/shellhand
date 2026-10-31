# CLAUDE.md

Shellhand is a native macOS SSH client: the host list, tabs on real `ssh`,
and files over SFTP, in a window. It is Swift all the way down, and it
keeps its own list.

`docs/architecture.md` has the shape of it and the traps worth knowing before
touching anything.

This repository is public, under GPL-3.0-or-later: `LICENSE` holds the licence
and `README.md` is what a visitor reads. `docs/name-and-pricing.md` has the
name, and the decision that it is free and open-source. A vulnerability goes to
a private report, never an issue: `.github/SECURITY.md` says so, and the
README, the issue form and the site point there. `.github/CONTRIBUTING.md` is
what a contributor reads: the ad-hoc build, a feature discussed before it is
written, and GPL with no CLA.

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
calls itself, what it shows, how it names a child and what it says about a
host it cannot reach),
`Views/Panes.swift` (which tab is in front,
what is beside it, what ⌘D and closing a tab do), `Views/QuickConnect.swift`
(what ⌘K offers for what was typed, and where an arrow moves the highlight),
`Views/SidebarRows.swift` (the sidebar flattened into one list, and what the
search field narrows it to),
`Sessions.shortTitle`, `Terminal/HostKey.swift` (whether ssh is waiting to be
told about a host key, which part of the screen is the question, and what it
is about), `Terminal/SessionStatus.swift` (what a session says it is doing,
and what ssh's last words mean),
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

Two things about the suite hold whatever is added to it. The removed shell
harnesses stay removed: they cost a Go toolchain and test-only flags inside
the shipping binary, and driving the app from outside costs it nothing. And
**every connection the suite makes is kept off its user's own `~/.ssh`**:
`ssh` is tested against macOS's own `sshd`, a server of the test's own on
`127.0.0.1`, through `LocalSSHD.isolation` — `-F /dev/null`, known hosts in
scratch, no agent, no control sockets — with `ProxyCommand=none` and
`ClearAllForwardings` left out on purpose, since they would break jumps.
→ [the suite's harnesses](docs/notes/testing.md#the-suites-harnesses)

**CI is `.github/workflows/tests.yml`**: the whole suite on GitHub's
`macos-26` runner, for every push and pull request that touches more than
docs, the site or Markdown. It signs ad hoc —
`CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO`, the
README's line for anyone without the Developer ID — and fails a run in which
the result bundle counts nothing passed. The runner's Xcode is older than the
one releases are built with, so read a red run as possibly the toolchain's.
**Don't run that ad-hoc build on this Mac under the app's own bundle id**:
macOS re-records the Desktop, Documents and Downloads grants against the
ad-hoc signature, and the signed app — the installed one too — is asked again.
→ [CI](docs/notes/testing.md#ci)

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
- `site/` — shellhand.com: one static page with no build step, published to
  GitHub Pages by `.github/workflows/site.yml` whenever it changes on `main`.
  `tools/site-images.swift` makes its images from `docs/screenshot.png` and
  the rendered icon. Like the README it names no version: its download
  buttons ask GitHub for the latest release.
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
- **Port forwarding is gone, and tmux with it**: in weeks of real use the list
  held no rules. Its table is dropped by migration v6, since migrations are
  append-only. **Don't bring it back without a reason from someone other than
  us.**
  → [port forwarding](docs/notes/cuts-and-sweeps.md#port-forwarding)
- **No Docker and no external hosts.** This held when there were harnesses —
  anything needing a server ran `gliderlabs/ssh` in-process on loopback — and
  it still binds anything added later. A check that reaches someone else's
  machine is not a check.
- **Keys, credentials and snippets are gone**, and the askpass helper with
  them, so **this app no longer answers a password prompt** and the SFTP window
  cannot reach a host that takes only a password. `identity` stayed, a plain
  `-i`. **Don't bring any of it back without a reason from someone other than
  us.**
  → [the MVP cut](docs/notes/cuts-and-sweeps.md#the-mvp-cut)
- **The cut's leftover engines are gone**: `Core/Command.swift` and
  `Model/Shell.swift` ran programs for features since removed, and are in this
  repository's root commit. Three things in `Command` outlast it, for whenever
  something runs a program again: read output as it arrives, lock what a
  `readabilityHandler` appends to, and record a cancel apart from a failure.
  → [the cut's leftovers](docs/notes/cuts-and-sweeps.md#the-cuts-leftovers)
- **Sweep for dead declarations both ways**: every method declared under
  `Shellhand/` against every mention anywhere — checking the **conformance**,
  not the name, so a framework's callbacks are not taken for dead — and the
  narrow sweep, declared under `Shellhand/` and mentioned only in `Tests/`,
  which finds what only the suite calls. Sweep preference keys and `try?`s
  too. → [sweeps](docs/notes/cuts-and-sweeps.md#sweeps)
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
  their members pick the default back up. **Mark the extension, not each
  member**: Swift 6.2 (Xcode 26, which CI builds with) puts a conformance in an
  extension that is not on the main actor however its members are marked, and
  Xcode 27 lets it through. → [CI](docs/notes/testing.md#ci)
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
- **Decisions lifted out of the views live beside them**: `Views/Panes.swift`,
  `Views/QuickConnect.swift` and `Views/Browsing.swift` keep no state, so each
  behaviour is a test with a couple of values — and testing ⌘K by driving it
  once connected a live machine.
  → [rules upward](docs/notes/window.md#rules-upward)
- **The host pane shows the list, always, and the inspector says what a
  host is.** Where the pane is *looking*, `Browsing`, is kept apart from what
  is *selected* — a group is a place, a host a thing — so **don't collapse
  `browsing` back into `Selection`**. The grid's arrow keys follow
  `Views/GridMove.swift`, which takes the sections; a row's menu is
  `Views/RowMenu.swift`, handed its subject rather than reading the
  selection; and the inspector opens a turn of the loop after a selection.
  → [the host pane](docs/notes/window.md#the-host-pane)
- **The pane tells the truth about the list.** A group counts everything
  beneath it (`Browsing.summary`): "Production · 1 host" held seven. The
  sidebar's All Hosts row and the pane's breadcrumb (`Tree.lineage`) lead
  back to the whole list, which nothing did once a group was open. The search
  text and the chosen tags belong to the window, and the pane narrows to the
  sidebar's own matches (`SidebarRows.matches`) and says so: they narrowed
  the sidebar alone, beside a pane still listing everything.
- **The inspector describes whatever the tab in front is about**
  (`Panes.inspected`): a listed host; a group, with what it passes down
  (`FromAbove`) and what is inside; a local shell; or a machine typed into
  ⌘K, with Save as Host…. It said "Nothing selected" for the last three, so a
  ⌘K machine could not be saved from anywhere. `Views/Inspectors.swift` draws
  them.
- **A destination has one spelling, `Host.destinationLine`**, which is
  `QuickConnect.Destination.spelled`: the sidebar, the pane, the inspector,
  ⌘K and the window's subtitle wrote it five ways. An inherited value says
  "from Production", in the inspector as in the editors, and What will run
  is read one argument a line (`HostPreview.lines`), a long value wrapping
  under itself rather than under its option, while Copy gives the quoted
  line: wrapped to the margin, a jump host read as a second destination.
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
- **A palette is chosen by looking at it**, everywhere one is chosen — the
  inspector, both editors and Settings — through `PaletteChoice`, a swatch
  that opens `PalettePicker`; three of the four were a menu of names.
  `PalettePicker` draws each as a `TerminalMiniature` in its own colours,
  applies a choice at once and stays open, so two can be compared on the
  terminal behind. What inheriting gives is read with the host's own palette
  left out (`HostDetailView.inheriting`) and drawn through
  `TerminalSession.palette(named:)`, or a host's inherit row was named after
  its own palette. Test what a view draws by rendering it with
  `ImageRenderer` against colours rendered the same way; a `List` or a
  `ScrollView` will not render at all.
  → [the palette picker](docs/notes/terminal.md#the-palette-picker)
- **A copy running from the build products has also been seen not to stop a
  run**, 539 passing beside one, so that rule is narrower than it reads. What
  holds is that `window-check.sh` cannot run beside another copy; address a
  copy by its `unix id`, never its name.
  → [a copy beside the run](docs/notes/testing.md#a-copy-beside-the-run)
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
  front it does nothing — **because nothing else holds it**: Close Tab stands
  in place of the system's Close and Close All (`CommandGroup(replacing:
  .saveItem)`). Beside them SwiftUI gave ⌘W to its own Close in 0.1.3 and
  0.1.4, and ⌘W closed the whole window, asking only when a session was
  live. `window-check.sh` checks who holds it. The SFTP window asks the same way before it stops
  transfers still to go, and ⌘Q counts those too. Sweep preference keys as
  well as functions: this switch did nothing for eleven releases.
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
- **Close an ssh child before reading its stderr to the end**: that read ends
  only when ssh does, so reading first hangs on a far end that keeps ssh alive.
  `close()` returns early once `ended` is set, which keeps a dead child's own
  sentence for the report.
  → [stderr](docs/notes/engine.md#stderr)
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
- **A type a test will touch starts `nonisolated`**, the enum it works on
  included: the app target defaults to MainActor, `Tests/` is compiled into it,
  and nothing in the app notices until a test from outside fails to compile.
  → [nonisolated](docs/notes/engine.md#nonisolated)
- **A local shell starts at home**: `startProcess` is given
  `currentDirectory:`, since an app launched by LaunchServices has `/`. Its
  test asks the shell itself, through a file it writes, rather than reading
  the screen. → [the local shell](docs/notes/terminal.md#the-local-shell)
- **`Sessions.shortTitle` has a pure overload** taking the host's name and the
  title, with the `TerminalSession` one calling it. A session builds a 900×560
  terminal view and registers a notification observer, which is a lot of
  machinery to stand up in order to check where a string gets cut.
- **`HostStore` is tested against a scratch database**, since every call
  carries its own `db:` and it needs no fake. Check the real store's
  modification time after touching any of it — the suite once opened and
  migrated the real list.
  → [HostStore](docs/notes/testing.md#hoststore)
- **A file pane's derived values live in `Model/Places.swift`**, testable
  without a session. `isLocal` decides whether names clash case-insensitively,
  and a pane pointed nowhere is not local: three states are pinned, not two.
  → [a pane's places](docs/notes/sftp.md#a-panes-places)
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
- **Every scratch path in the suite goes through `Tests/TestScratch.swift`**:
  one root per run, removed at exit. Sweeping the temporary directory by hand,
  go by `-type d`, since `shellhand-ssh-` also names the log a live session is
  writing, and leave `shellhand-under-test` alone: it is the store a test run
  opens. → [scratch paths](docs/notes/testing.md#scratch-paths)
- **A file pane under test opens on a scratch `home:`**, never the real home
  directory: listing that reads Desktop, Documents and Downloads, and macOS
  holds the read on a privacy prompt whenever the test host's signature is not
  the one it remembers. Every test that did so timed out, on a question that
  came up on the screen of whoever was at the Mac.
  → [the privacy prompt](docs/notes/testing.md#the-privacy-prompt)
- **Every walk over the group tree lives in `Model/Tree.swift`**, built
  once per snapshot, because each walk carries a guard against a group that
  became its own ancestor, and the suite turns a loop through all of them — a
  rotted guard hangs the app. A host needs its own group open and everything
  above it; a group needs only its parents.
  → [the tree](docs/notes/engine.md#the-tree)
- Menus live in `Shellhand/App/Commands.swift` and reach the front window
  through `AppActions`, a focused scene value. Keyboard shortcuts belong there
  rather than on a button.
- **A disabled menu item still takes its key**: NSMenu stops at the first
  item whose key matches, enabled or not, so a second item on the same key in
  a later menu never fires — measured, two menus and ⌘R. A window's own
  controls see a key before the menus, so the SFTP window's ⌘R and ⇧⌘N are
  its active pane's buttons (`FilesModel.active`), and ⌘W with no host window
  in front is Close Window, where it did nothing.
- **A menu item that would do nothing is greyed out**: File's New items,
  Import… and Quick Connect… need the host window, Shellhand ▸ SFTP a host
  window or a browser to bring forward, and Reconnect a host — a local
  shell has none. With SFTP or Settings in front they were live and did
  nothing.
- **A menu is named for what its items act on, and that gates it**:
  **Host** needs a listed host — the session in front's, or else the one
  selected (`Panes.subject`, ⌘T's rule) — **Terminal** a session in front,
  and the app menu's Hosts and SFTP nothing. With a session in front, ⌘B
  once opened SFTP on the sidebar's host rather than the one on screen. There is no Library menu and nothing is
  called Library, except `@AppStorage("libraryLayout")`, which keeps its name
  because renaming a stored key resets everybody's choice.
  → [menus](docs/notes/window.md#menus)
- Text size sits in **Terminal**, not View: "Bigger Text" in a View menu does
  not say bigger than what, and these size the terminal and nothing else.
- **The toolbar is placed by what each item acts on**, like the menus:
  Quick Connect, New Host and SFTP over the sidebar, and the inspector toggle
  alone at the trailing edge. Keep `paneToolbar` even with one item, since
  each column needs its own `.toolbar`. Quick Connect wears a bolt, not the
  magnifying glass the search field under it already wears.
  → [the toolbar](docs/notes/window.md#the-toolbar)
- **⌘F finds hosts with the hosts in front** — it puts the keyboard in the
  sidebar's search field, bringing a hidden sidebar back — and a session's
  scrollback with one in front. With the hosts in front it did nothing.
- **The window opens with the keyboard in the sidebar's host list**
  (`SidebarFocus`), so the arrows and Return work before anything is
  clicked. Left alone, macOS hands a window's keyboard to its first text
  field — the search — where ↓ and Return reached nothing, in every release
  up to 0.1.3. `window-check.sh` checks it as the window comes up.
- **It is called SFTP, everywhere**, at the user's word — **don't re-argue
  it**. Anything still called Files is a spot the rename missed, except
  `setFrameAutosaveName("FilesWindow")`, which must not change or every saved
  frame is lost.
  → [the name SFTP](docs/notes/window.md#the-name-sftp)
- **Connect is not in the toolbar**: it is in the inspector, on ⌘↩ in the
  Host menu — **and only there**, since a second ⌘↩ on the inspector's button
  could pick another host — and on ⏎ in the list. A double-click connects through
  `contextMenu(forSelectionType:)`'s `primaryAction` on rows and
  `NSApp.currentEvent?.clickCount` on cards — **never a `TapGesture(count: 2)`,
  which made every single click wait**. Look for the native hook before
  reaching for a gesture.
  → [connecting from the list](docs/notes/window.md#connecting-from-the-list)
- **Each column carries its own `.toolbar`**: hung on the split view, the
  detail's items land against the divider whatever the placement; with a
  toolbar of its own and `.primaryAction`, they sit at the trailing edge.
  → [a toolbar per column](docs/notes/window.md#a-toolbar-per-column)
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
- **New Group… lives in File and says where it will land** — "New Group Inside
  Production…" — because it reads the selection; an item that quietly does two
  things has earned a longer label.
  → [New Group](docs/notes/window.md#new-group)
- **A menu on a row acts on that row**, handed it rather than reading the
  selection: a group's New Host… is `newHostIn` that group, while ⌘N in File
  still makes an unfiled host. `RowMenu.lines` carries each item's subject and
  `RowMenuTests` holds it: a group's Edit and Delete read the selection until
  0.1.1, so on a grid card they acted on some other group.
  → [a row's menu](docs/notes/window.md#a-rows-menu)
- **A file session is opened once per pane**, behind a flag set before the
  first await; two opens together once sent a download to the wrong folder
  while the job reported success.
  → [opened once](docs/notes/sftp.md#opened-once)
- **Sessions are a strip of tabs across the terminal**, at the user's word, and
  the sidebar is the host list alone. A tab shows `Sessions.shortTitle`, capped
  at 180pt and cut in the middle; if the strip fills, shorten it further —
  **don't move sessions back to the sidebar**.
  → [the strip](docs/notes/window.md#the-strip)
- The strip is **not there at all when nothing is open**, list or no list
  (`Panes.showsTabs`): with nothing open it held one tab, the one you were
  on.
- **`Sessions` does not say what is on screen, and must not be asked**: what is
  in front is `ContentView.pane`, read through `frontSession`. `current` was
  removed after it went wrong in four places at once.
  → [what is on screen](docs/notes/window.md#what-is-on-screen)
- **The strip's selection is what the pane shows**: a `PaneTab`, held as `pane`
  in front and `beside` for the split. Picking the tab shown beside trades the
  two places, since a terminal is one view and can be in one place. **The
  split is `SideBySide`, not an `HSplitView`**: an `NSSplitView` sized its
  sides from the terminal views' own frames, 900pt from when they are made,
  and Show Beside widened the window past the screen. The sides are laid out
  in the room the window has, by `Panes.frontWidth`, with a line to drag.
  → [the strip's selection](docs/notes/window.md#the-strips-selection)
- **Never change the inspector in the same update that swaps the pane**:
  it crashes, intermittently, as a reentrant table-view operation. Defer it a
  turn of the loop with `DispatchQueue.main.async`, and prove a change here
  with a dozen round trips, the previous build as the control.
  → [the inspector crash](docs/notes/window.md#the-inspector-crash)
- **An `onChange` sees a value, never the act**: before driving state off one,
  ask what happens when the value is set to what it already holds. A `Bool`
  mode set that way silently broke the strip, and the sidebar with it.
  → [onChange](docs/notes/window.md#onchange)
- The strip **comes with the first session**, so the hosts tab is there to
  come back to whenever there is somewhere else to be. It used to be drawn
  whenever there was a list, and a strip of the hosts tab alone was the
  clutter this line said to revisit; the UI/UX review settled it. A fresh
  install meets the **welcome** in place of the list.
- **The welcome stands in for the hosts tab, not the window** —
  `Panes.welcoming` and `Panes.showsTabs` — or a local shell opened on a fresh
  install runs hidden behind it.
  → [the welcome](docs/notes/window.md#the-welcome)
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
- **⌘T opens another of the session in front**, by `Panes.newTab`; only with
  the hosts in front does it open the host selected. A session on a host since
  deleted opens nothing rather than some other machine.
  → [⌘T](docs/notes/window.md#new-tab)
- **A tab has a menu of its own** — Reconnect, Duplicate, SFTP, Close Tab
  and Close Other Tabs — and each item is handed its session through
  `TabActions`, since right-clicking a tab does not bring it in front.
  → [the tab menu](docs/notes/window.md#the-tab-menu)
- **Reconnecting keeps the tab where it was** — `Sessions.replace` puts the
  new session in the old one's place in the strip, and `Panes.replacing` in
  front or beside — where it closed the tab and opened another at the end.
  The tab in front scrolls into view, which a new one past a full strip did
  not.
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
- **Each session as its own `NSWindow`, drawn as a real macOS tab bar, was
  built and thrown away. Don't offer it again.** macOS's own window tabs are
  switched off at launch (`NSWindow.allowsAutomaticWindowTabbing`), or View
  and Window offer them anyway, beside a second pair of items on the
  strip's ⇧⌘[ and ⇧⌘]; `window-check.sh` checks they are gone.
  → [windows as tabs](docs/notes/window.md#windows-as-tabs)
- **This Mac is always the left side** of the browser; the right is the host
  it was opened on. Opened from no host in particular — ⌘B, the toolbar
  button with nothing selected — the right side **asks which host** rather
  than showing this Mac a second time, which told you nothing and made you
  choose anyway. Either side can be re-pointed from its own menu, so
  host-to-host copying is intact; it is just not what opening SFTP means.
- **SFTP is a window, and one at a time**: asking again brings it forward and
  re-points it through `FilesModel.show(host)`. It has flipped between tab and
  window four times — **don't flip it a fifth on reasoning alone**.
  → [a window, one at a time](docs/notes/sftp.md#a-window-one-at-a-time)
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
- **A pane pointed at a host acts through its session or not at all**
  (`Places.session`), and drops its listing the moment it is re-pointed.
  An empty session is this Mac to `Core`, so a Delete made while a pane was
  connecting, or after its host refused, removed the same path here while the
  dialog named the host. A refused host stays named, rather than the pane
  calling itself This Mac over nothing.
- **A host SFTP cannot open says what it means and what to do**
  (`Places.trouble`): one never connected to, or one taking only a password,
  offers Open in Terminal — a tab can answer what SFTP's `BatchMode=yes`
  cannot — and every failure offers Try Again. Open in Terminal reaches the
  host window as a `TerminalRequest`, which one window takes.
- **A transfer says which way it goes and where it lands**
  (`TransferQueue.route`): labels the engine's reports do not carry, which
  `Transfer.labelled` keeps across them. A failed one is retried in its own
  row while the sessions it went through are still the panes' own
  (`FilesModel.canRetry`), a relay between hosts as a whole.
- **Deleting on this Mac goes to the Trash**, and nothing in the suite calls
  it: a test would leave files in the user's Trash, which an app without Full
  Disk Access cannot take back out. A failure with a listing up is a banner
  (`Places.notice`); before that it was drawn nowhere.
- **There are no secondary `Window` scenes.** If one comes back: `openWindow`
  works only when a live view asks, and the first scene in `body` opens at
  launch, so another needs `.defaultLaunchBehavior(.suppressed)`.
  → [scenes](docs/notes/window.md#scenes)
- **The sidebar's `List` holds one `ForEach` over one flat array of rows**,
  tree and search alike, built and tested in `Views/SidebarRows.swift`; two
  shapes in one list drew stale rows over new ones.
  → [the sidebar's rows](docs/notes/window.md#the-sidebars-rows)
- Anything automated waits for **its own copy** of the app. `pgrep Shellhand`
  matches every copy, including one the user has open.
- **Driving Quick Connect against a real host list connects to a real
  machine**: synthetic keys get dropped and arrive late. Drive a scratch store
  with a host at `127.0.0.1:1`, which fails at once and reaches nothing.
  → [Quick Connect](docs/notes/driving.md#quick-connect)
- `Group`, `Host` and `Color` are ambiguous: SwiftUI has a `Group` and a
  `Color`, SwiftTerm has a `Color`. Write `SwiftUI.Group` and `SwiftUI.Color`
  in files that hit them.
- **The sidebar is one list.** A second tab and a sidebar of three lists were
  both built and cut; if a second tab is ever wanted, make it one switch over a
  menu.
  → [one list](docs/notes/window.md#one-list)
- **Never write to the store while a list is drawing**: a save resolves every
  host and crashes the table view reading them. Anything that saves as it is
  typed must debounce, and flush on disappear.
  → [writes while drawing](docs/notes/window.md#writes-while-drawing)
- **`.searchable` goes where it likes, not where you put it.** Inside a plain
  sheet it detaches, drawing a second search box floating at the top right
  while the list draws its own; and with `placement: .sidebar` it is hoisted
  to the very **top of the column**, outside the list it belongs to. A plain
  `TextField` is what works in both places; the host sidebar draws its own in
  a `safeAreaInset(edge: .top)` on the list, which also avoids re-indenting
  the whole modifier chain.
- **In a list beside its detail, give the detail `maxWidth: .infinity`**: a
  `maxWidth` on the list caps the list, not its pane, and the slack shows on
  deselecting.
  → [a list beside its detail](docs/notes/window.md#a-list-beside-its-detail)
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
- **`@AppStorage` is keyed by the bundle id, not by `--db`**: a scratch copy
  and the test host read and write the user's real preferences. Borrow the
  domain with `defaults export` and give it back with `import`, then compare;
  restore a single key with the type it had — `defaults delete` it first,
  since `write` keeps an existing key's type — and check `defaults read-type`.
  → [preferences](docs/notes/driving.md#preferences)
- **The test bundle is hosted by the app, so a test run launches it**:
  `LaunchOptions` sends a run under XCTest to a scratch store and a scratch
  config, and `TestRun` sends ssh's config there too, and the SFTP window's
  This Mac to a folder of its own. Keep it so, and check
  the real store's timestamp after touching that code; `--db` and `--config`
  still win when they are named. **Everything that reads ssh's config reads
  `SSHConfigFile.pathInUse`**: the import sheet and the welcome read the real
  one, and a drive's import sheet listed its user's own hosts. **So does
  every `ssh` a run starts**, handed it with `-F` (`TestRun.sshFixed`) at the
  front of a session's argv and every hop's, and of a file session's: ssh
  reads `~/.ssh/config` by itself otherwise. ssh keeps the last `-F`, so the
  suite's own `-F /dev/null` still wins; the line shown and copied has none.
  → [the hosted test bundle](docs/notes/testing.md#the-hosted-test-bundle)
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
  Deleting one **asks**, with the hosts it comes off (`Tags.deletionWarning`
  over `Tags.removing`'s count): it went from every host at once without a
  word. The chips **wrap** (`TagFlow`) rather than scrolling sideways, which
  clipped mid-word with nothing to say there were more.
- **Deleting a host says what jumps through it** (`Validation.deletionWarning`),
  matched as the resolver matches a jump: a host counts if its jump field
  names it or a group above it does (`effective`), and the groups that name
  it are named — "the jump host for 2 groups" said nothing of the six hosts
  in them. Without it ssh is left to find a machine by that name on its own.
  **Renaming one takes them along** (`Validation.renaming`): every host's and
  group's jump field that named it is rewritten in the rename's own
  transaction, as renaming a tag retags its hosts, and the editor says so
  before Save. Nothing follows while another host still answers to the old
  name, which only a list from before names had to differ can hold.
- A hosting controller sizes its window to **the view's minimum**, throwing
  away the rect `NSWindow` was given — so `setContentSize` has to come after
  `contentViewController`, and `setFrameAutosaveName` after that, because
  setting the autosave name applies a saved frame at once and would otherwise
  be overwritten by the default size.
- `.help()` is a tooltip, **not an accessibility name**. An icon-only button
  with one still reads as "button": `Image(systemName: "plus")` carries no
  text. Every icon-only button gets `.accessibilityLabel` — seventeen of them
  across the views did not have one.
- **Don't check an accessibility name through System Events**: it reads every
  SwiftUI button alike, named or not, and cannot read the attributed
  description back. Accessibility Inspector or VoiceOver can.
  → [accessibility names](docs/notes/driving.md#accessibility-names)
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
- **`import Foundation` in a test file makes `Host` ambiguous**: leave it out,
  or spell the type `Shellhand.Host`, and leave the comment on the import
  saying why.
  → [Host and Foundation](docs/notes/testing.md#host-and-foundation)
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
- **The host-key question names the machine by the route**: `HostKey.asked`
  reads the machine and the fingerprint out of ssh's question, with the
  whitespace out and a SHA256 fingerprint taken at its 43 characters, and
  `Route` — the resolver's own jump chain, in the order it is reached — says
  which hop it is. Return trusts and Esc does not. A question in a tab behind
  another says Needs you on the tab, since the far end gives up on it.
- **The watchdog's decision is `SessionProgress`; `watch()` is only the
  looking**, left open with `logPath` so a test can run the real loop on a fed
  view. `ticks` tells a watchdog that ran from one that never did, and `looks`
  one that read the screen.
  → [the watchdog's shape](docs/notes/terminal.md#the-watchdogs-shape)
- **A session says what it is doing in words and a symbol, never a colour
  alone** (`SessionStatus`): connecting shows where, the way there and the
  time so far, with Stop Connecting on ⌘.; an ending says whether it never
  connected, was lost, was stopped or simply ended, with ssh's own line and
  what it means (`SessionEnding`) — where "status 255" read the same as
  `exit`. **Through is no proof of logging in**: an answered question or a
  password prompt reads as through, so what ssh said decides first. **ssh's
  own warnings are no word from the far side** (`SessionProgress
  .heardFromTheFarSide`): it warns about a key file that is not there on the
  terminal, before its log takes over, and a hop's ssh writes everything
  there — read as output, a session still trying showed as connected.
  → [blank, not empty](docs/notes/terminal.md#blank-not-empty)
- **The scrollback is 10,000 lines, and the screen is read only around
  connecting**: `SessionProgress.watches` says yes while connecting, while a
  question is up and for `settling`, two minutes, after coming through. Every
  read is the whole history, since SwiftTerm 1.99's view gives the app no part
  of the buffer, and stopping at `.connected` would miss a jump chain's next
  hop. **Check what SwiftTerm's view exposes, not the class behind it.**
  → [the scrollback](docs/notes/terminal.md#the-scrollback)
- **Settings is a window this app makes**, `SettingsWindowController`, because
  the glass chrome needs `.fullSizeContentView` and a SwiftUI scene puts the
  window back; it sets `isReleasedWhenClosed = false`.
  → [the Settings window](docs/notes/window.md#the-settings-window)
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
- **Dialogs come in three widths**, `Views/DialogSize.swift`: 460 for one
  question, 560 for a record or a plain list, 820 for a list beside its detail.
  Width only: each dialog measures its own height.
  → [dialog widths](docs/notes/window.md#dialog-widths)
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
- **A mark in a segmented picker's label is a character, not an SF Symbol**: an
  `Image` there collapses to U+FFFC and draws nothing, while accessibility
  still reads it back.
  → [marks in a segment](docs/notes/window.md#marks-in-a-segment)
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
- **The group editor's tabs divide what a group is from what happens on its
  hosts**, and its Advanced tab shows `•` when anything there is set, the
  palette included.
  → [the group editor](docs/notes/window.md#the-group-editor)
- **Both editors are sized so that neither tab ever scrolls**, and sized for
  **editing** rather than for a new record: an editor opened on something has
  a Delete in its footer, which costs the form 23pt. The host editor is
  650 General / 570 Advanced, the group editor 570 / 555. The earlier
  500/490 and 600/480 were measured against **new** records and scrolled on
  every tab but one as soon as a real host or group was opened in them.
- **Whether a form fits is its own scroll area** — the sheet's direct child,
  not a recursive search — where no scroll bar means it fits, and a thumb's
  size gives the missing height in one pass.
  → [does it fit](docs/notes/driving.md#does-it-fit)
- **Focus the outline once, then arrow**: re-focusing before each press puts
  the selection back where it started. Group rows are reachable that way;
  `click at` reaches nothing.
  → [arrowing](docs/notes/driving.md#arrowing)
- **Where an inherited value comes from is a caption beside the field**, not
  part of the placeholder, which is the inherited value or an example — never
  `—`.
  → [where a value comes from](docs/notes/window.md#where-a-value-comes-from)
- Tags are **tokens you can take off**, not a line of commas, and the value
  underneath is still the comma form so nothing below the view knows. Their
  field is drawn with a border like every other, because a row that is a field
  and does not look like one reads as decoration.
- **The window can be driven through System Events, keyboard paths
  included**: walk with `UI elements` and `role of`, never the per-class
  accessors, and `repeat with x in y`, never `item 1 of y`. `select` on a row
  and `click at` do nothing here — focus the outline once and arrow instead —
  and a row's context menu cannot be opened from a script. Drive connecting
  against `127.0.0.1` port 1 — **picking the host by searching for it, and
  pressing Connect only once the title names it**: an arrow walk that missed
  connected whatever it stopped on — and pin every preference an assertion
  leans on. A shell whose command line names the app's path trips the
  "another copy" guards, so run a drive or `window-check.sh` from a file.
  **Compile every helper with `osacompile` before a drive**: one that does
  not compile returns nothing, and AppleScript keeps words a helper reaches
  for — `middle`, `items`, `times`, `buttons`. Read `front window` again
  after anything that retitles it: a reference held from before names the
  old title and no longer resolves.
  → [System Events](docs/notes/driving.md#system-events)
- **A key path is spelled however it was typed**, so anything comparing two
  must settle both first — tilde expanded, `.pub` dropped. Nothing compares
  them now; write that again rather than comparing strings.
  → [key paths](docs/notes/cuts-and-sweeps.md#key-paths)
- **A screenshot needs the app frontmost**: ScreenCaptureKit refuses a freshly
  built tool. Check who is frontmost first, and skip rather than take focus
  while somebody is typing. While the Mac is in use, check a layout by
  rendering the view's own code with `ImageRenderer` from a script, which
  needs no window and no focus.
  → [capturing](docs/notes/driving.md#capturing),
  [0.1.2](docs/notes/releases.md#every-release)
- **A locked screen looks exactly like an app that failed to launch**:
  System Events sees no windows and every menu item disabled, and the app in
  front still reports as frontmost. Check `CGSSessionScreenIsLocked` in
  `ioreg` before a drive and before every key, and conclude nothing from
  behind a lock. → [the lock](docs/notes/driving.md#the-lock)
- **`screencapture -R` takes the screen at a rectangle, not a window**, so
  check the app is frontmost before and after; `-l` takes one window alone,
  given its `kCGWindowNumber`.
  → [screencapture](docs/notes/driving.md#screencapture)
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
- **Import runs on exactly what was previewed** (`ImportPlan`): the source,
  the path, the text and the group it was made of. A path edited and
  Returned imported a file nobody had looked at, a group typed after the
  preview imported into one it had not shown, and a second press reported
  the first's count. A preview that comes back after the window has moved on
  is let go; the plan says what it would do (`MergeResult.plan`); a missing
  file is said as one.
- **The group typed into an import files only the hosts it adds**
  (`Portable.merge(newHostsIn:)`): a host already in the list stays where it
  was filed, and one the file files goes where the file says. The group was
  given to every loose host before the merge could tell new from old, so
  importing an ssh config again with a group typed moved hosts filed in
  Production into it, under a field that said "Put new hosts in".
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
- **The settings file has one name, and Settings makes it**: Create Settings
  File writes `Config.template` — every setting explained and commented out,
  its example held by a test to parsing — and never over a file already
  there. It was sent to as "ssh options", "Settings" and "your settings
  file", and nothing made it.
- **Swift reads CRLF as ONE `Character`.** `"\r\n"` is a single grapheme
  cluster, so a parser that matches `"\r"` and looks ahead for the `"\n"`
  matches neither: the lookahead eats the next value and the row never ends.
  Match `"\r\n"` as itself, beside `"\n"` and `"\r"`.
- **A field removed from the model stays accepted by the importer**, its value
  dropped and the host noted, or every export written before is refused whole —
  as `forwards`, `credentials`, `snippets`, `credential` and `startup` are.
  → [removed fields](docs/notes/cuts-and-sweeps.md#removed-fields)
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
- **A button whose label is a stack needs `.accessibilityLabel`**, placed
  before its background and border — never `.accessibilityElement(children:
  .ignore)`, which leaves a button that does nothing when pressed.
  → [naming a stack](docs/notes/window.md#naming-a-stack)
- **A palette is eighteen colours**, kept in `Core/Theme.swift` and pasted
  under `themes:` in the config. A channel is multiplied by **257**, not 256; a
  palette missing a colour is refused whole; and "System" means SwiftTerm's own
  colours, left alone.
  → [palettes](docs/notes/terminal.md#palettes)
- **The app icon is an Icon Composer bundle**, `Shellhand.icon`, written by
  `tools/icon.py`; `ASSETCATALOG_COMPILER_APPICON_NAME` must be set, or the
  build ships the generic icon without a warning.
  → [the icon bundle](docs/notes/releases.md#the-icon-bundle)
- An icon is judged at **16pt**, not at 512: that is where it fails, and a
  mark that works at 512 says nothing about it. `tools/icon-preview.sh` writes
  a loupe — 16 and 32 blown up with the pixels kept square — because smoothing
  a 16pt icon makes it look better than it is. It renders by asking
  NSWorkspace for a stub app's icon rather than by rasterising the SVG, since
  the squircle, the gradient, the shadow and the specular are the system's
  half of the picture.
- **A copy of the app launched from the build products the test host wants
  can stop `xcodebuild test` before it starts** — *"Failed to send resume to
  target process"* and `Executed 0 tests` — while the installed copy in
  `/Applications` can stay open. Quit the copy built to `build/` first.
  When that copy is somebody's and in use — a session open in it — give the
  run a `-derivedDataPath` of its own instead: the usual run rebuilds the
  very program that copy is running from.
  → [a copy in the way](docs/notes/testing.md#a-copy-in-the-way)
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
- **Sparkle's helpers are signed again by the release script**, not a build
  phase, which cannot be ordered after a package's frameworks are embedded; the
  app is then re-signed with `--preserve-metadata`.
  → [Sparkle's helpers](docs/notes/releases.md#sparkles-helpers)
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
- **A dry run and a real run share `build/release/DerivedData`**, and the build
  service holds its database after a build ends: leave a moment between runs,
  or give one its own `-derivedDataPath`.
  → [a locked build database](docs/notes/releases.md#a-locked-build-database)
- **`release.sh` reads the desktop app's untracked `.claude/` as a dirty
  tree**, since it counts anything `git status --porcelain` prints. Pass
  `--allow-dirty` only once that says exactly `?? .claude/`, so the DMG is
  still the commit its tag names.
  → [every release](docs/notes/releases.md#every-release)
- **Never name a shell variable `status` in zsh**, where it is read-only: a
  wrapper died that way while its release ran on. A stale log beside a running
  process means two runs — check `ps -o pid,ppid,etime,command`.
  → [a wrapper's status](docs/notes/releases.md#a-wrappers-status)
- **`SUFeedURL` is permanent for a build's life**, so the feed is `appcast.xml`
  on `main` and the DMGs come from GitHub releases; the release script refuses
  to build with any other address.
  → [the feed's address](docs/notes/releases.md#the-feeds-address)
- **The feed and the tap's cask sit behind a CDN that caches a path for
  five minutes**, but only a path something fetched lately, so an instant
  answer after a push may only mean nobody had looked. Ask what `main` holds
  through the API — the blob's sha against `git rev-parse HEAD:appcast.xml` —
  rather than pushing again. → [the CDN](docs/notes/releases.md#the-cdn)
- **Back up the EdDSA private key**, under the account `shellhand` in the login
  keychain, or every shipped app is stranded: nothing else can sign an update
  they will take.
  → [the EdDSA key](docs/notes/releases.md#the-eddsa-key)
- **Nothing about updates runs in a Debug build.** Sparkle would offer a
  Debug build the newest release DMG and install it over itself. `start()`
  and `check()` return early and `canCheck` is false, so Check for Updates…
  greys out while developing rather than looking live and doing nothing.
- **The appcast is written from a folder**, so `release.sh` fetches past
  DMGs back first, and `generate_appcast` retires all but the newest few by
  itself, ordered by the integer build rather than the version string. Its
  "failed to move" warnings about `old_updates` are local housekeeping.
  → [the appcast](docs/notes/releases.md#the-appcast)
- **`Updates` deliberately does not bridge `canCheckForUpdates`.** Sparkle's
  own sample publishes it through Combine, which costs an `ObservableObject`
  in a codebase that is otherwise `@Observable` and a KVO callback that has to
  hop to the main actor to be legal under Swift 6 — all to grey the menu item
  out for the second a check is already running, which is harmless to ask
  twice. The menu reads it when it is built, which is often enough.
- **The updater starts a turn of the run loop late**, through
  `DispatchQueue.main.async` from `ShellhandApp.init()`, which runs too early
  in launching to check.
  → [the updater's start](docs/notes/releases.md#the-updaters-start)
- **notarytool's retry matches a failed transport by a wide pattern**,
  case-insensitively, and echoes what notarytool said: it words a timed-out
  upload more than one way, and matching one wording cost 0.0.5 a whole
  signed build.
  → [notarytool's retries](docs/notes/releases.md#notarytools-retries)
- **No binary deltas**: they are named for build numbers the per-version URL
  rewrite cannot place. `--maximum-deltas 0` stops new ones; delete
  `build/updates/appcast.xml` to evict one, and keep the guard that catches an
  unplaced URL.
  → [deltas](docs/notes/releases.md#deltas)
- **A restored window title is not evidence of a connection**: AppKit brings an
  old session's title back for a moment. `pgrep -P <pid>` is — no `ssh` child,
  no connection.
  → [the restored title](docs/notes/driving.md#the-restored-title)
- **Sparkle's preferences share the bundle-id domain**, and this Mac sets
  `SUAutomaticallyUpdate`, so updates install here unasked; don't read this
  machine's update behaviour as the product's.
  → [Sparkle's preferences](docs/notes/releases.md#sparkles-preferences)
- **`auto_updates true` in the cask is doing a job.** The app updates itself
  past whatever version brew installed, so `brew list` goes on reporting its
  own record — 0.0.1 after the app has reached 0.0.2 — and brew correctly
  does not call it outdated. That is intended; don't "fix" the discrepancy.
- **The published history is one commit**, re-rooted when the repository
  went public; the 118 commits before it are the pre-reset bundle,
  `~/Projects/shellhand-history-9e19a70.bundle`, which `git clone` reads and
  nothing pushes. **Don't re-root a history anyone has pulled.**
  → [the history](docs/notes/cuts-and-sweeps.md#the-published-history)
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
it can be typed — but the SFTP window cannot reach one, because an sftp child
is given `BatchMode=yes` and there is nothing left to answer a prompt with.

It has an icon: a shell prompt, chevron and block cursor, as an Icon Composer
bundle that macOS composites into the Tahoe squircle. `docs/app-icon.md` has
the directions that lost and why this one did not.

Release packaging is built: `scripts/release.sh` takes it from `xcodebuild`
to a notarized, stapled DMG, a signed appcast and an updated cask, and the app
checks for its own updates through Sparkle. Hopmeter's `scripts/release.sh` in
`~/Projects/nettoolbox` was the model, and most of what is worth knowing about
it is in the conventions above.

**0.0.1 through 0.1.5 are out**, each tagged at the commit its DMG was built
from, with the appcast on `main` and the cask in `cuonggt/homebrew-tap`, whose
clone on this Mac is Homebrew's own, under `/opt/homebrew/Library/Taps`:
fast-forward it before copying a cask in. The notarytool profile `Shellhand`
is stored, the EdDSA key is backed up off this disk, and release notes live
at `docs/release-notes/<version>.md` — write one per version or the update
window comes up blank. **Updating is proven end to end**, the dialog a new
user meets included. Every release is checked the same way before and after
publishing: hash a download as it streams, compare a release page's notes
as JSON, and fetch the tag `gh release create` made before comparing the
release's target to it. Don't predict when a release will reach an installed copy, and never
trigger Check for Updates from here.
→ [every release](docs/notes/releases.md#every-release)

**The README's picture** is taken from a scratch copy on a host list of its
own, with ssh's config kept out by `XCTestSessionIdentifier`, the window sized
to 1220×798 points and photographed alone with `screencapture -l`.
→ [how it is taken](docs/notes/driving.md#taking-the-readmes-picture)

**Installing from the tap needs `brew trust` first.** Since Homebrew 7 a cask
from a tap outside Homebrew's own must be trusted once before it will load,
because casks can carry install scripts. This one carries none, but the gate
applies anyway, so the README spells the step out rather than letting an
install fail with an error that reads like the cask is broken.
