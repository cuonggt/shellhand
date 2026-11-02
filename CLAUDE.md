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
  `browsing` back into `Selection`**. A group picked in the sidebar is gone
  to; one picked in the pane is only selected, and two clicks or ⏎ open it
  (`Browsing.scope`'s `pickedInPane`) — it opened on any pick, so the list
  was replaced under the highlight and ↓ could not get past Production. The
  grid's arrow keys follow
  `Views/GridMove.swift`, which takes the sections; a row's menu is
  `Views/RowMenu.swift`, handed its subject rather than reading the
  selection; and the inspector opens a turn of the loop after a selection.
  → [the host pane](docs/notes/window.md#the-host-pane)
- **The pane tells the truth about the list.** A group counts everything
  beneath it (`Browsing.summary`): "Production · 1 host" held seven. The
  whole list counts every group as it counts every host — "12 hosts, 2
  groups" was said of four — and the sidebar heads the tree Groups, as the
  pane does, where Hosts beside Ungrouped read as the groups' name. The
  sidebar's All Hosts row and the pane's breadcrumb (`Tree.lineage`) lead
  back to the whole list, which nothing did once a group was open; All Hosts
  says you are there by its weight, not a band, which was the grey of a
  selection without the keyboard, so a host picked made two rows read as
  chosen. The search
  text and the chosen tags belong to the window, and the pane narrows to the
  sidebar's own matches (`SidebarRows.matches`) and says so: they narrowed
  the sidebar alone, beside a pane still listing everything.
- **A narrow pane drops before it squeezes.** A host's row shows what fits:
  its tags go first, then its group, then the name column narrows; and a grid
  with room for one column lets it fill the pane. In a pane about 450pt wide
  — a wide sidebar does it — the tags wrapped a letter to a line, group names
  hyphenated and destinations read "d…2", and one column of cards left a
  third of the pane empty. **Every row of a list drops the same**
  (`Browsing.rowShape`, from every row's text measured in the row's own
  fonts, with `ViewThatFits` below it for a row measured a point wrong):
  each row chose for itself, and at the window's default size one host kept
  its tag beside the next, with the same tag, losing it. **The name column
  is as wide as the list's widest name**, 120 to 240 (`Browsing.nameColumn`):
  held at 240, it stood mostly empty at the default size, "staging-web"
  about 76pt of it, while every row lost its tags. **A card is 210pt
  at its narrowest** (`Browsing.cardColumns`), so the grid holds two at the
  window's default size: at 230 two needed 470pt of the pane's 453, and the
  grid there was one column of wide cards, their words in the left quarter.
  A host card keeps its line of group and tags whether or not anything is
  on it, so a row's cards stand one height: one with neither stood 13pt
  shorter than a tagged one beside it, under a minimum that held only the
  short ones. The line is laid over a blank one as wide as the card, which
  hands it the card's width: in a ZStack beside the blank — any second
  child, before it or after — the tags were handed next to none, and every
  card read "US … …" for a walk, since the drive that proved the heights
  looked at nothing else. **Look at what a fix draws, not only the number
  it was for.**
  Its sections are named as the list's are, small, grey and semibold, where
  they were bold headlines over the list's grey ones. The title, the list
  and the grid share one left edge, the inset list's own 16pt
  (`HostsPane.inset`): at 24 the list stood 8pt left of All Hosts, and
  padding the list in to meet it took the rule under its first heading 8pt
  in from the pane's edges with it — `contentMargins` does not reach a
  list's rows here. The list/grid switch stands at its own width on the
  edge they end on, where in a frame of 84 it stood 16pt short of them.
  The grid starts where the inset list puts its first heading
  (`HostsPane.listTop`), so it stays put as the layout changes, where it
  rose 6.5pt into the grid.
- **The inspector describes whatever the tab in front is about**
  (`Panes.inspected`): a listed host; a group, with what it passes down
  (`FromAbove`) — its ssh options too, and every group's above with whose
  they are, since they add up (`FromAbove.sshOptions`), where they showed
  nowhere but the editor — and what is inside, in one grid with it, where
  two put its values 41.5pt left of the rest; a local shell, with Open now
  listing the shells on this Mac, where it said neither which was in front
  nor offered the other; or a machine typed into
  ⌘K, with Save as Host…, its address written as a listed host's
  (`UnsavedHostInspector.addressLine`), port and all — it gave the port a row
  of its own — and What will run and Open now as a listed host's has them
  (`WhatWillRun`, `OpenNow`), its tabs those on the machine typed the same
  way (`UnsavedHostInspector.sameMachine`), never matched by the empty id
  every typed machine shares: with two tabs open on one, it said neither,
  and its command was nowhere but Save as Host…'s sheet. It said "Nothing
  selected" for the last three, so a ⌘K machine could not be saved from
  anywhere. `Views/Inspectors.swift` draws them. **A host's Open now marks
  each of its tabs as the strip does** (`StatusMark`): every row wore one
  terminal icon, so a tab that never connected was listed as open as a live
  one. The tab in front says In
  front, where its Show did nothing, and the heading counts nothing:
  "Open now (2)" sat over a tab named "refuser (2)".
- **A destination has one spelling, `Host.destinationLine`**, which is
  `QuickConnect.Destination.spelled`: the sidebar, the pane, the inspector,
  ⌘K and the window's subtitle wrote it five ways. An inherited value says
  "from Production", in the inspector as in the editors, and the command is
  read one argument a line (`HostPreview.lines`, drawn by `CommandLines`),
  a long value wrapping under itself rather than under its option — in the
  inspector's What will run and along the host editor's foot alike — while
  Copy gives the quoted line: wrapped to the margin, a jump host read as a
  second destination, and the editor's quoted line, cut to two, hid a jump
  chain's middle in `'"'"'`. The editor's box hugs the command up to six
  lines and scrolls past that.
- **A host is drawn with its operating system's mark**, learned by reading
  `/etc/os-release` over a connection of its own (`Core.osOf`), once a day per
  host — `Host.shouldAskOS`, on `osSeen`, which records the asking and not the
  answering — and never while the switch in Settings ▸ General is off. A mark
  is a file found by name, `os-<ID>.svg` with `ID_LIKE` behind it, made by
  `tools/osmarks.swift` from CC0 logos; they identify machines, so they belong
  on host rows and nowhere else. The folder's own `README.md` is the guard
  that it is bundled: don't exclude it. Where there is no mark, the plain
  server is fitted into a mark's slot: drawn at the slot's size in points,
  it inked 18.5pt across a row's 16 and 25.5 across a card's 22, past a
  mark's edges on both sides.
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
  inspectors, both editors and Settings — through `PaletteChoice`, a swatch
  that opens `PalettePicker`; three of them were a menu of names, and the
  group inspector's row the palette's name, beside a host's swatch, though
  a group's palette is what tells production from staging. Its
  name is black when set there and grey when inherited, since a grouped
  form greys whatever it is handed: a group's own Gruvbox Dark read as
  grey as one from Production. Its arrows sit in a round bezel, as a menu's
  do beside it, where bare and grey they read as another kind of control —
  drawn as the menu's is, measured off it: its fill `secondarySystemFill`,
  its arrows black, 12.5pt after the words and 3.5pt in from the row's end,
  where `.quaternary`, arrows a grouped form greyed and an 8pt gap made a
  near copy whose circle stood 3.5pt right of the menu's under it;
  and its words drop under the swatch and its arrows where they would not
  keep their lines beside them: the bezel took 12pt from the inspector's
  column, and "Gruvbox Dark from Production" went down a word to a line.
  Its words' baseline is said, a line centred on the swatch having it
  `centreToBaseline` below the centre, so a form sets the row's label on
  it: "Colours" stood 1.5pt above "System".
  `PalettePicker` draws each as a `TerminalMiniature` in its own colours,
  applies a choice at once and stays open, so two can be compared on the
  terminal behind. It is as tall as its rows need, where the window it
  opens over has room, and otherwise as the room allows
  (`PalettePicker.height`): Settings is shorter than the 460 it was, and
  its Done hung below the window's edge; and held to 460 with room to
  spare, the inherit row pushed the last palette out of sight. What
  inheriting gives is read with the host's own palette
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
  family. Its sample line is shown whole at any size, on two lines where one
  will not hold it: held to one, it lost "{} [] =>", the characters it is
  there to show, from about 19pt. Its caption ends on the keys, "with ⌘+ and
  ⌘-", where "⌘-" ended a line above "change" and read as "⌘-change"; and
  Colours' says palettes are added in the settings file, not "under themes",
  its key. → [the font](docs/notes/terminal.md#the-font)
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
  in front is Close Window, where it did nothing. With SFTP in front the bar
  names them, by `FilesInFront`, its model while its window is key: File's
  ⇧⌘N item is New Folder…, asking the side in front
  (`FilesModel.askNewFolder`), View has Refresh — at its head, a divider
  under it, as it acts on what a side lists, where it stood undivided
  between Show Inspector and Show Sidebar — and Reconnect gives ⌘R up —
  they were New Group… and Reconnect, greyed, on the very keys. New Folder…
  has New Group…'s ellipsis, as it too asks a name before anything is made,
  where it had none. Refresh draws
  no key: **SwiftUI draws none on an item that gains one after the menu is
  made** — measured, put in with ⌘R, or there always and handed ⌘R — while
  New Folder keeps ⇧⌘N by taking New Group's place, whose key never changes.
- **A menu item that would do nothing is greyed out**: File's New items,
  Import… and Quick Connect… need the host window, Shellhand ▸ SFTP a host
  window or a browser to bring forward, and Reconnect a host — a local
  shell has none. With SFTP or Settings in front they were live and did
  nothing. In the SFTP window Edit ▸ Delete needs a file selected:
  `onDeleteCommand` is handed nil without one.
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
- **View names the inspector and the sidebar, and says what each would
  do**: Show or Hide Inspector on ⌥⌘I (`Panes.inspectorTitle`, the toolbar
  button's tooltip too), and Show or Hide Sidebar on ⌃⌘S
  (`Panes.sidebarTitle`), both greyed with no host window in front. It said
  Toggle Host Details — a host over a group as well, Toggle beside ⌘D's Show
  Beside — and had nothing for the sidebar. **The sidebar's item is the
  app's own, not `SidebarCommands`**: the system's drew Hide Sidebar with
  the sidebar out, while accessibility read it as Show Sidebar however it
  stood, menu open or shut. A title the app sets is read as drawn.
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
  With the Hosts tab in front that window is titled Hosts, as the item and
  the strip's tab call it, what is picked said under it ("db-01 ·
  Production / US"), so the Window menu lists it so: it said Shellhand, and
  then the host picked — "waiter" beneath the session on waiter, named the
  same.
  → [Hosts and SFTP](docs/notes/window.md#hosts-and-sftp)
- Two `.disabled` on one menu item **compose**, so both have to be true for it
  to be usable. "Delete Group…" carried one on `hasGroup` and a second on
  `hasHost`, which meant deleting a group needed a host selected as well.
- **New Group… lives in File and says where it will land** — "New Group Inside
  Production…" — because it reads the selection; an item that quietly does two
  things has earned a longer label. It names the group by its path, "Inside
  Production / EU…", as the host editor's item does: by its name it said
  "Inside EU" where the editor said "inside Production / EU". **Inside is
  where a group sits**, there, in a row's menu and in the group editor's
  row; what a group holds is its
  Contents in the inspector and its Groups in the pane, where both said
  Inside, beside the editor's row meaning the opposite. **The host editor's
  New group… lands where the host was filed** and its item says so — "New
  group inside Production / US…", as File's does, and it stays the menu's
  value once chosen — so the host keeps what that group passes down; its
  preview and inherit rows read the host filed there. It went to the top of
  the list unsaid, taking the host's inherited user, key and jump host with
  it; a caption under the name said where, and cost the form a line it did
  not have at the window's default size. Its missing name is said quietly,
  as New Group says it, where on a host being edited it was a warning.
  → [New Group](docs/notes/window.md#new-group)
- **A menu on a row acts on that row**, handed it rather than reading the
  selection: a group's New Host… is `newHostIn` that group, while ⌘N in File
  still makes an unfiled host. `RowMenu.lines` carries each item's subject and
  `RowMenuTests` holds it: a group's Edit and Delete read the selection until
  0.1.1, so on a grid card they acted on some other group.
  → [a row's menu](docs/notes/window.md#a-rows-menu)
- **A file session is opened once per pane**, behind a flag set before the
  first await; two opens together once sent a download to the wrong folder
  while the job reported success. **Once per place**: the flag names the
  host being opened (`FilePlace.opening`), so a side re-pointed while it
  connects opens where it points now, at once, and what the first open
  brings back is closed on arrival (`departures`) — the flag turned the
  second call away as a second open of the first, and the side named the
  host it was pointed at over nothing, neither a listing nor a refusal.
  Closing the window lets go the same way (`FilePlace.letGo`): a session
  arriving after it had closed was kept, its `ssh` child alive until quit.
  → [opened once](docs/notes/sftp.md#opened-once)
- **Sessions are a strip of tabs across the terminal**, at the user's word, and
  the sidebar is the host list alone. A tab shows its name from
  `Sessions.titles` — `Sessions.shortTitle`, a second of one name numbered
  as the Window menu, the inspector's Open now and **the title bar**
  (`Sessions.title(of:)`) number it, and a local shell named This Mac, as
  the inspector and SFTP call it; the title bar showed the shell's own title,
  "cuonggt@Cuongs-MacBook-Pro:~" over a tab saying "Local — ~", and
  "refuser" over "refuser (2)" — capped at
  180pt and cut in the middle; as the strip fills the tabs share its room
  by what each name needs, short names giving their spare to long ones,
  down to 60 (`Panes.tabTitleWidths`) before it scrolls — shared evenly,
  "This Mac — ~" was cut to "This…c — ~" with 65pt of the strip empty —
  and what a tab takes besides its name is counted from the parts it is
  drawn with (`Panes.tabChrome`, its × at a width of its own), a Needs you
  badge included: a round 50 was 3pt short a tab, and four tabs scrolled
  at 1220pt with every name above 60, the first under its fade;
  and a tab's tooltip is its name whole (`Panes.tabHelp`), where it was
  the shell's own title alone; and the Hosts tab
  stays outside the scrolling, where a full strip pushed it half off its
  edge. An edge with tabs past it fades (`Panes.hiddenEdges`): at the
  window's default size four tabs fill the strip, and the first was shown
  sheared, square against Hosts, with nothing to say the strip scrolled. The
  tab shown beside is outlined. **Don't move sessions back to the sidebar**.
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
  ⌘D's item reads Hide Beside while a tab is beside (`Panes.splitTitle`),
  since that is when it closes the split. **The hosts are never a side**:
  with them in front the split waits unshown (`Panes.shownBeside`), its tab
  not outlined and ⌘D not reading Hide Beside, and comes back with the next
  session picked, while the tab that was beside comes in front alone. It was
  outlined over the host list alone, and picking it put the list beside the
  terminal.
  → [the strip's selection](docs/notes/window.md#the-strips-selection)
- **The middle column has one minimum, whatever it shows**
  (`Panes.paneMinimum`, a frame on `DetailView`). Left to its content it
  moved — picking a group raised it 34pt — and a window already at its
  narrowest then had to widen inside a layout pass, which AppKit ends by
  throwing: 0.1.7 crashed on the first group picked there, every time.
  `window-check.sh` arrows through the sidebar at the narrowest. The column
  keeps about 300pt of its own beside that minimum while the inspector is
  up, so 500 made the narrowest window 1532 — **measure the narrowest window
  after touching either**, and keep the window's `defaultSize` at it: it
  asked for 1100 beside a narrowest of 1106, so every check at "the default
  1100×720" ran at 1106.
  → [the narrowest window](docs/notes/window.md#the-narrowest-window)
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
  install runs hidden behind it. Only the welcome says there are no hosts:
  the sidebar says where they will go and the inspector what it will
  describe, where the sidebar said "No hosts yet" too and the inspector
  asked for a host to be picked from an empty list. The sidebar's has a
  line under it as the inspector's has, so the two stand level, where a
  title alone sat 30pt below the inspector's.
  → [the welcome](docs/notes/window.md#the-welcome)
- The **Window menu lists the sessions too**, with ⌘1 to ⌘9 for the first
  nine. That came in with the column and stays without it: a keyboard way to
  the fourth session is worth having whatever the switcher looks like, and
  one menu is cheaper than a second switcher. Sessions of one name are told
  apart there — "refuser", "refuser (2)", `Panes.menuTitles` — because
  SwiftUI matches menu items by title: two of one name came out as one item
  twice, both on ⌘2 and nothing on ⌘4.
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
  not — **and again once the tabs' widths settle**: a tab opened with the
  strip nearly full shares the room out anew, and the scroll measured against
  the widths before stopped short, the new tab's × out of sight. At the
  default size with a fourth tab, four trials in four, before and after the
  strip's fade alike; with the second scroll, none in four.
- **File ▸ Export…** writes the list the way the import sheet's Export… does,
  where it used to live alone — behind a sheet called Import. No key: ⇧⌘E,
  the usual one, is Edit Group's. `YAMLDocument.defaultFilename` names the
  file once for both, and **both greys with nothing to export and say a save
  the disk refuses** (`HostStore.canExport`, `YAMLDocument.failure`) — the
  menu's through the window's alert (`HostStore.report`), the sheet's along
  its foot; Cancel is not a failure. The sheet's wrote a file holding nothing
  from the welcome, and dropped every refusal without a word. Both offer
  the Documents folder (`YAMLDocument.exportFolder`, a run's own folder
  under test), each from a view of its own so the folder reaches no other
  panel: the save panel opened wherever a panel last chose — ~/.ssh, after
  the ssh config's Choose….
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
- **The SFTP window opens with the keyboard in the active side's list**, This
  Mac's, as the host window opens in its host list: left alone, AppKit gave
  it to the first path field, where ↓, Space and ⌫ edited the path.
- **Quick Look's panel is the SFTP window's while that window is key**: its
  controller accepts the panel up the responder chain and is handed it, and
  only then is the data source set (`QuickLook.take`). It was set from
  outside, which the panel's header says never to do while not in control.
- **This Mac is always the left side** of the browser; the right is the host
  it was opened on. Opened from no host in particular — ⌘B, the toolbar
  button with nothing selected — the right side **asks which host** rather
  than showing this Mac a second time, which told you nothing and made you
  choose anyway. Either side can be re-pointed from its own menu, so
  host-to-host copying is intact; it is just not what opening SFTP means.
- **A side's Name column takes the table's spare room**: Size and Modified
  are held to what they hold, 100 and 150 at most, where with no most they
  shared it — Size 154pt for "6 bytes" beside a Name of 172.
- **SFTP is a window, and one at a time**: asking again brings it forward and
  re-points it through `FilesModel.show(host)`. It has flipped between tab and
  window four times — **don't flip it a fifth on reasoning alone**.
  → [a window, one at a time](docs/notes/sftp.md#a-window-one-at-a-time)
- **Closing the SFTP window ends both panes' sessions**, through
  `FilesModel.close()`, answering a replace question still up first — for
  weeks it left an `ssh` child per pane running until quit, while a comment
  beside it said the opposite.
  → [closing the window](docs/notes/sftp.md#closing-the-window)
- **A side showing no listing counts nothing** and draws no Copy of its own,
  which kept its place greyed with nothing to choose; the other side's Copy is
  plain Copy while this one is pointed nowhere (`Places.copyTitle`): "0
  items" read as an empty folder, and the button said "Copy to Choose a
  host". A file double-clicked or Returned on across from it beeps, as a key
  with nothing to do does, where it did nothing and said nothing. Its ↑
  greys where there is no folder above (`Places.goesUp`) — at "/" it stood
  live and did nothing. Its path field greys with the buttons beside it,
  where Return in
  it went nowhere and said nothing — and looks it, at half: greyed, a field
  draws as a live one, its border 235 and its placeholder the 128 of any
  empty field, where at half the placeholder is 191 beside their 192 — and
  so does its "…" menu, whose Show Hidden Files had nothing to act on. The header's icons are drawn in
  AppKit's control colours, black as the menu is while they can act and
  its grey while they cannot (`.controlIcon`: `controlTextColor`,
  `disabledControlTextColor`), as Settings' Reveal in Finder is, which was
  124 beside its black switches: borderless they came out mid-grey, nearer
  greyed than live, and a hierarchical style changed nothing — `.primary`
  in a borderless button is the button's own grey, and `.tertiary` drew
  the greyed ones fainter than the greyed menu. That fix was called done
  from a crop: **measure a colour, never judge it by eye** — the icons were
  128 before it and after, beside the menu's 37. **It draws no table**:
  the question or the refusal stands alone on the table's ground, where it
  was laid over an empty table whose stripes ran through it under a
  sortable header. A
  side's selection is cleared on the side, since the table is not there to
  see the listing it comes back with.
- A `FilePlace` that has not been pointed anywhere is **not this Mac** — it is
  a question (`chosen` is false) and says "Choose a host", its header and
  its empty side alike (the side said "Pick a host"), and under it "Choose
  one from the menu above, and its files show here" — after "Use the menu
  above", "its" read as the menu's; and the window says
  folder, never directory. Without that state
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
  cannot — and every failure offers Edit Host…, as a terminal tab that could
  not connect does, and Try Again, which reads the host from the list afresh
  (`FilePlace.tryAgain(with:)`, handed it by the window): it went again with
  the copy the side was pointed with, so a host renamed in Edit Host… kept
  its old name there. A host deleted since offers Try Again alone, which
  says so; its Edit Host… opened nothing.
  Only Try Again was there, under advice to check the host's user and key.
  Both reach the host window as a `HostRequest`, which one window takes. **It
  is drawn as the terminal's card for the same refusal**: the headline red
  with its mark, ssh's line boxed and first, the way on leading and
  prominent, its buttons small as the terminal's are. It was plain, the line
  unboxed after the advice and the retry last, so one failure looked like
  two things in two windows; then its buttons were the regular size. This
  Mac's own failure, with nothing listed, says "Couldn't open this folder",
  as a host's says "Couldn't connect to web", where it kept the "Cannot show
  this" the card replaced.
- **A transfer says which way it goes and where it lands**
  (`TransferQueue.route`): labels the engine's reports do not carry, which
  `Transfer.labelled` keeps across them. A failed one is retried in its own
  row while the sessions it went through are still the panes' own
  (`FilesModel.canRetry`), a relay between hosts as a whole.
- **Deleting on this Mac goes to the Trash**, and nothing in the suite calls
  it: a test would leave files in the user's Trash, which an app without Full
  Disk Access cannot take back out. A failure with a listing up is a banner
  (`Places.notice`); before that it was drawn nowhere.
- **New Folder's Create and Rename's button grey for a name they would
  refuse** (`Places.usableName`, which `FilePlace`'s own guards use): empty,
  a path, `.` or `..`, or the name already held. They took one, closed the
  question and did nothing. **New Folder says where the folder goes**
  (`Places.newFolderPlace`, `FilePlace.folder`) — "It goes in ~/Projects on
  This Mac", as Delete names its host: ⇧⌘N acts on whichever side last had
  the keyboard, and the question said only "New Folder". The home folder is
  named, "your home folder", where a bare "~" read as a stray mark.
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
- **Every scratch copy launches with `-ApplePersistenceIgnoreState YES`**,
  `window-check.sh`'s as well as the drives': a copy killed at the end of a
  run comes back at its next launch as it was left, and one launched with the
  flag still leaves its window behind. Without it window-check, run straight
  after itself, came up in the last run's window with the tree open and
  failed its first look, whichever build — the failure noted as unexplained.
  → [the window left behind](docs/notes/window.md#the-window-left-behind)
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
- **Deleting a group says what moves and what goes** (`Validation
  .deletionWarning(for:groups:hosts:)`): the hosts filed in it, and the groups
  inside it with their own hosts, as `Store.deleteGroup` moves them, and
  what it gives the hosts beneath it — the user, the key, the palette — which
  goes with it. It said all seven of Production's hosts moved to the top,
  six staying in EU and US, and nothing of what they would lose. Where they
  land is named as the sidebar and the editors name it — into the group
  above, or with none, the hosts to Ungrouped and the groups each "a group
  of its own", Inside's words — where "the top of the list" named both and
  the hosts land at its foot. It ends as every deletion question does, "This
  cannot be undone.", which it alone left out.
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
- **A selectable text whose words can change in place is made with
  `.selectable(words)`**, which keys it by them (`.id`): the inspector's
  values and destination, SFTP's failures, the import's problem, the
  terminal's ssh line and host-key question, and Settings' trouble. A
  `.textSelection(.enabled)` text comes twice in the accessibility tree, and
  changed in place the first copy kept its first words: after a switch the
  inspector held the last host's user, address and jump host there while
  the screen showed this one's. Seen there, not yet elsewhere; text that
  never changes keeps plain `.textSelection(.enabled)`. System Events reads
  that much — a static text's value, which is not a button's name.
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
  The cards hold at a side's width beside another tab: the connecting line
  breaks between its parts (`SessionStatus.connectingLines`) and an ending's
  buttons stack, where they broke inside a port and cut to "Recon…" — at one
  width, the widest's (`stackedButtonLabel`, the stack held to its widest),
  in SFTP's card too, where each stood at its own, 76, 77 and 72pt — and
  ssh's line is as tall as its lines in both, as the sentence under it is:
  beside another tab at 1220pt it was held to one, "port 2…", its
  "Connection refused" cut, while a narrower side wrapped it whole. Whether
  the connecting line takes one row is asked once, at the longest it will
  be (`SessionStatus.longestWait`, "59 min 59 s"): asked each second, a
  line of one row at 9 s took three at 10, and the card jumped. **A card
  is drawn on the window's own ground, opaque, with a hairline round it**
  (`Card.ground`, `Card.edge`): a material let the terminal through, and
  over a black one came out mid-grey, 147, the red headline about 1.3:1
  on it and the secondary words 2.9:1, where on the window's ground they
  are 3.7 and 3.9, as anywhere else in the window, and the headline 14.9;
  and without the hairline, a card on SFTP's white side was white on
  white, its words standing alone. Their secondary words are the
  secondary label colour as itself (`Card.secondary`): as `.secondary`,
  the material drew them vibrant, over a black terminal darker than the
  headline, 20 against 44.
  **All three cards are one shape** — connecting, ended, and SFTP's
  refusal (`cardChrome`: 480 at most, left-aligned, 14pt in and 12 out) —
  so one state's card gives way to the next in place: the connecting card
  was 440 wide, centred, in 20pt margins, and jumped as it failed, and
  SFTP's was 460 in 24. In place to the point: over a pane with nothing on
  it a card's top stands a set way above the middle (`CardPlacement`,
  `Card.rise`), where centred, a refusal's top stood 28pt above the
  connecting card's it replaced, 154pt tall against 98; and a headline's
  icon stands in a slot of one width (`.cardHeadline`), where the words
  started 24 after a circle, 24.5 after the spinner and 25.5 after the
  triangle.
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
  overridden by it. **The Window menu lists it as Settings all the same**
  (`NSApp.changeWindowsItem`, put back whenever the title changes, since
  AppKit lists a window afresh by its title): by the pane's name it read
  "SFTP" on its SFTP pane, beside the SFTP window.
- A sidebar footer goes in a **`safeAreaInset`, not a `List` row**: a row is
  indented for a selection it will never have, and the inset left so little
  width that the build number fell off the end of "Version 0.0.1 (1)".
- Settings is a **window**, like Files, so the three dialog widths below do
  not apply to it. It opens at 700×757, as tall as its tallest pane,
  General, and will not go below 620×420 — made in the order the SFTP
  window's is: the hosting controller, then the size, then the autosave
  name, `SettingsFrame`. Before the controller they were undone by it:
  Settings opened at its minimum, 620×472, re-centred every time, no resize
  stuck, and General's last section and Terminal's Keyboard sat wholly
  below its edge. The old name's frames, all that minimum, are removed. At
  700×500 those two still sat below it, each pane ending on a whole section
  with room under it, which says there is nothing more where macOS shows no
  scroll bar until something scrolls; and at 756 General still scrolled, by
  under a point.
- **A stepper's number sits beside its arrows**, as Size's sits beside its
  slider — a `LabeledContent` around both, the stepper's label hidden.
  Written as the stepper's label, `Stepper { LabeledContent(…) }`, SFTP's
  "At once 2" sat with its label at the left and the arrows 330pt away.
  Both numbers are black, as a value set there is: grey, beside "SF Mono"
  and "System" in black, they read as inherited, which grey says here.
- **Dialogs come in three widths**, `Views/DialogSize.swift`: 460 for one
  question, 560 for a record or a plain list, 820 for a list beside its detail.
  Width only: each dialog measures its own height.
  → [dialog widths](docs/notes/window.md#dialog-widths)
- **Quick Connect is a palette, not a dialog**, and is deliberately outside
  that grid: ⌘K, type, return, the shape Spotlight has, where a footer would
  be noise. What a palette does owe you is a way out, and with no button bound
  to `.cancelAction` nothing answers Escape — `onExitCommand` is what does.
- **⌘K's typed row says what it is**: "Not in your list", or — where a saved
  host is that very machine — "As typed, without web's settings"
  (`QuickConnect.typedCaption`). It said "Not in your list" under the host
  it named.
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
  it is how ssh is typed and how the command along the bottom ends.
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
- **A greyed Add says why from the start, in both editors**: a new host or
  group nobody has typed into says what it needs quietly, in grey with an
  info mark, and as a warning only once something has been typed. New Host
  said nothing, leaving Add greyed with no reason, while New Group warned
  before anything had been typed.
- **A grouped `Form` right-aligns what it is given, and that reaches inside a
  `.roundedBorder` field**: every placeholder sat against the right edge of its
  own box, which reads as a value somebody chose. `.multilineTextAlignment(
  .leading)` on each field is the fix — **a plain field inside a view of its
  own as well**: `TagField`'s typing field went without it through two walks,
  "add a tag" floating off the last token. And a placeholder of "—" for
  "nothing inherited" reads as a value too — an example of what belongs there
  does not.
- A label that is only a placeholder **disappears exactly when it is needed**.
  Two bare fields side by side in a row said which was which until both were
  filled, and then nothing did. Every field gets a label beside it, in the
  same `LabeledContent` + `.roundedBorder` row the rest of the app uses, and
  **asks for a modest width and takes what there is** (`idealWidth` with
  `maxWidth: .infinity`): a grouped form puts the label above a field that
  wants more than the room beside it, and a field wants its text's width —
  the import's File, holding a long path, sat under its label. Two fields
  one above the other in a sheet stand in one column instead, one fixed
  modest width: the import's File took all there was after its short label
  while its group field sat 125pt off its own, and the group field keeps an
  unseen twin of File's Choose… beside it to match — on every tab, so it
  stays put as the tab changes: on SSH Config's alone, it moved 88pt
  sideways. Its Choose… is one size wherever it stands, the drop area's as
  File's, where it was small on two tabs.
- **The group editor's tabs divide what a group is from what happens on its
  hosts**, and its Advanced tab shows `•` when anything there is set, the
  palette included.
  → [the group editor](docs/notes/window.md#the-group-editor)
- **Both editors are sized so that neither tab ever scrolls**, and sized for
  **editing** rather than for a new record: an editor opened on something has
  a Delete in its footer, which costs the form 23pt. The host editor's
  General needs 736 and its Advanced 640 — room for the command's six lines
  at its foot and one line more, a problem or a rename note, and for the
  inherited user's caption under Connect to — and the group editor's 486,
  General's with the footer's problem line up, where 570, measured when it
  had rows since gone, left General 137pt of empty form and Advanced 160.
  **Each editor is drawn at its taller tab's height on both tabs**: a
  sheet is centred on its window, so one that changed height with the tab
  moved the tab control under the pointer, 7pt in the group editor and 27
  in the host editor. The earlier 500/490 and 600/480 were measured against **new**
  records and scrolled on every tab but one as soon as a real host or group
  was opened in them; 650/570 was 41pt short on both tabs once the command
  was drawn a line an argument.
- **A sheet over the host window is no taller than the room below its
  toolbar** (`SheetHeight`, the room read off the window's
  `contentLayoutRect` by `MeasuresRoom` — SwiftUI's geometry took the toolbar
  off twice — and held in `SheetRoom`, so a resize redraws an open sheet
  rather than the whole window and its menus): the editors
  and the import are what they were measured to need where that fits, and
  otherwise the room less a margin, with what scrolls in them giving way —
  in the host editor the command's box first, so the form keeps its room —
  but only what the form cannot spare (`commandCap`, with the lines along
  the foot taking that spare): giving up all of it left the box two lines and
  a half under 55pt of empty form. What it can spare is read off the form as
  drawn (`commandCap(room:)`: its scroll area less its content, with the
  box), the estimate standing in until it is laid out — guessed from db-01's
  General, Save as Host… cut a three-line command under 58pt of empty form.
  Where not a line of it fits beside the form, the box gives way altogether,
  and New group…'s name sits in the Group row under its menu, not a row of
  its own: held to a line beside a Called row, the form scrolled 39pt at the
  window's default size, its Tags under the foot.
  At 720, 0.1.7's host editor hung below
  the window at its default
  1100×720, where every check had run at the README's 1220×798. **Check a
  sheet at the window's default size as well.**
- **A list or a command cut short ends partway down a row, never on its
  edge** (`PalettePicker.height`, `HostEditorSheet.commandShown`): macOS
  shows no scroll bar until something scrolls, so a scroll area that ends on
  a row's edge says it holds nothing more. Settings' picker showed five
  palettes of six and nothing of the sixth, and the host editor at the
  window's default size three lines of the command that read as all of it,
  the ProxyCommand and the destination out of sight beneath.
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
  `—`. The caption says "from Production" in every editor: the host
  editor's said "Production" alone up to 0.1.5, which read as a value. Its
  row is set on the field's baseline (`.firstTextBaseline`), which is where
  the form sets the label: centred, the row's baseline was the caption's,
  and the label stood 1.5pt above the field's words.
  Connect to's user says it under the row, which has no room beside it —
  "user from Production" — where it said nothing at all. An inherited
  palette reads the same way, value first — "Gruvbox Dark from Production",
  "System from Settings" (`Effective.inherited`) — where it said "From
  Production — Gruvbox Dark", and the group inspector "As in Settings"; and
  the host inspector's Colours row draws it as its neighbours do, the palette
  with "from Production" in grey beside or under it
  (`Effective.inheritedPaletteParts`), where the one sentence wrapped a word
  to a line in full-size type, the label centred against it. So
  does agent forwarding — "Carried from Production", or "Not carried by
  default" where nothing says (`Effective.agent`) — in both editors and both
  inspectors, where it read "From Production — carried", "Not carried
  (nothing says)" beside the group inspector's "—", and the host inspector
  had no row for it. A host's inherit rows are read off its groups
  (`FromAbove(of: host)`), not off what it resolves to, which has its own
  choice in it. **An
  example never names something in the list** (`HostEditorSheet
  .jumpExample`, `.userExample`, `.nameExample`, `GroupEditorSheet
  .nameExample`) — New Host's name "web" was a tag three hosts carried, the
  one example nothing checked: "bastion"
  in Production's Jump host, with bastion filed there, read as Production
  going through it, and "Production" over "Inside: Production" as the name
  already chosen — in the host editor's New group… as well, under a menu
  listing Production; "deploy", Production's user, sat grey in a user field
  inheriting nothing. The tag field asks "add a tag", empty or not, where
  "web, eu" named two tags in use in the comma form it turns into tokens.
- **One setting has one name** wherever it is shown: Jump host and Agent
  forwarding, in both editors and the inspectors, and Colours in Settings as
  well. The host editor called the first two Through and Agent up to 0.1.5,
  and Settings the last Palette, under a header saying Colours, where an
  inspector's "System from Settings" sent you. **The jump host is typed or
  picked from your hosts in both editors** (`JumpHostField`): the group
  editor's was a field alone, though a group needs the menu as much as a
  host — EU and US send all six of their hosts through bastion.
  → [where a value comes from](docs/notes/window.md#where-a-value-comes-from)
- Tags are **tokens you can take off**, not a line of commas, and the value
  underneath is still the comma form so nothing below the view knows. Their
  field is drawn with a border like every other, because a row that is a field
  and does not look like one reads as decoration. **Its first line's baseline
  is the row's** (`FlowLayout`'s `explicitAlignment`), the typing field's
  said by hand where AppKit puts a borderless field's
  (`TagField.fieldBaseline`): asked from inside a custom layout, a text field
  answered 8pt down a 22pt field, above its words at 13, and "Tags" stood
  5pt above "add a tag" — with a token first, it lined up. An offscreen form
  drew that row 2.5pt apart from the app's; measure the app.
- **The window can be driven through System Events, keyboard paths
  included**: walk with `UI elements` and `role of`, never the per-class
  accessors, and `repeat with x in y`, never `item 1 of y`. `select` on a row
  and `click at` do nothing here — focus the outline once and arrow instead —
  and a row's context menu cannot be opened from a script. Drive connecting
  against `127.0.0.1` port 1 — **picking the host by searching for it, and
  pressing Connect only once the title names it**: an arrow walk that missed
  connected whatever it stopped on. ⌘B connects SFTP to the host selected,
  so clear the selection before pressing it. Pin every preference an
  assertion leans on. A shell whose command line names the app's path trips the
  "another copy" guards, so run a drive or `window-check.sh` from a file.
  **Compile every helper with `osacompile` before a drive**: one that does
  not compile returns nothing, and AppleScript keeps words a helper reaches
  for — `middle`, `items`, `times`, `buttons`, `row`, `th`, `my`; inline
  ones too, or the shell does arithmetic on the error. Read `front window` again
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
  file is said as one. **What an ssh config holds is said one way**
  (`ImportPlan.configSays`) — "No file at ~/.ssh/config", or what it names
  — on the welcome and once in the sheet, under its field: the three said
  it three ways, two of them at once, and a file naming no machine
  (`Core.sshConfigHosts` gives nought, not nil) was said to be no file. A
  path typed there is settled before it is read (`SSHConfigFile.settled`),
  its `~` expanded: the field's own example, typed, found no file — and the
  field is filled the way the line under it spells the path, "~/.ssh/config",
  where it held /Users/…/.ssh/config over "~/.ssh/config names 12". What
  each source is called and what it is read the same on the welcome and on
  its tab — the name atop the tab as atop its card, and its line under
  (`ImportSheet.Source.name`, `.about`): the tabs were headed by one card's
  name and two cards' lines, the CSV tab said "A sheet" — inside a sheet —
  where the welcome said a spreadsheet, and the ssh config's tab "The
  machines OpenSSH already knows about", where the welcome calls it Your
  SSH config. The file is spelled "SSH config" wherever the app names it —
  the tab, its heading and the inspector's "from your SSH config" — where
  it read SSH Config, SSH config and ssh config.
- **The group typed into an import files only the hosts it adds**
  (`Portable.merge(newHostsIn:)`): a host already in the list stays where it
  was filed, and one the file files goes where the file says. The group was
  given to every loose host before the merge could tell new from old, so
  importing an ssh config again with a group typed moved hosts filed in
  Production into it, under a field that said "Put new hosts in". A CSV's
  guide to its columns comes before that field, under the file it is about,
  where the field stood between them; and the caption under it says "already
  in your list", where "already in it", after "this group", read as the group.
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

**0.0.1 through 0.1.7 are out**, each tagged at the commit its DMG was built
from, with the appcast on `main` and the cask in `cuonggt/homebrew-tap`, whose
clone on this Mac is Homebrew's own, under `/opt/homebrew/Library/Taps`:
fast-forward it before copying a cask in. The notarytool profile `Shellhand`
is stored, the EdDSA key is backed up off this disk, and release notes live
at `docs/release-notes/<version>.md` — write one per version or the update
window comes up blank. **Updating is proven end to end**, the dialog a new
user meets included. Every release is checked the same way before and after
publishing: hash a download as it streams, compare a release page's notes
as JSON, and fetch the tag `gh release create` made before comparing the
release's target to it. A DMG that grew more than its changes explain is
mounted beside the last one and compared file by file before it goes out. Don't predict when a release will reach an installed copy, and never
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
