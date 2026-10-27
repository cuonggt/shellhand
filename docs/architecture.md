# How the app is put together

Shellhand is one window: a host list on the left, and on the right either the
list again as cards, a host's details, or a terminal. SFTP is a window of its
own. Everything below the views goes through `Core`, an actor that holds the
store connection and the work — sessions, transfers — that outlives the call
that started it.

## The layers

- `Shellhand/Core/` — the engine. The store, the inheritance resolver, the
  argv builder, the config, YAML and `ssh_config`, SFTP. Plain values and
  rules, no views, which is why it is the part that has tests.
- `Shellhand/Model/` — what the window reads. `HostStore` holds a snapshot and
  refreshes it when something changes, so nothing calls into `Core` per view,
  per row or per keystroke. `FilesModel` is the SFTP browser's two places and
  what is moving between them.
- `Shellhand/Terminal/` — a session: `ssh` on a pty through SwiftTerm.
- `Shellhand/Views/` — SwiftUI, plus the handful of AppKit pieces SwiftUI
  cannot do: the Settings and SFTP windows, and the sidebar's click monitor.

The host list is SQLite through GRDB, at
`~/Library/Application Support/Shellhand/`. A snapshot of a couple of hundred
hosts is a millisecond or two, because the store is one connection held open
rather than a file opened per call.

Every host arrives with what is written on it **plus an `effective` block**:
what inheritance made of each value, and the name of whatever supplied it.
That is why the detail pane can say not just `deploy` but where `deploy` came
from, and why the editor's empty fields can show what they would inherit.

## Connecting

Every tab is its own `ssh`. They are not multiplexed over one connection, and
that is deliberate: `ssh -O exit` takes down every session riding a master, so
a shared connection means one error closes every shell.

The app adds one option of its own, `-E`, which sends ssh's own output to a log
file instead of the terminal. With it the pty carries only what the remote
wrote, so refusals, warnings and host-key questions can be shown as the app's
own words; without it they arrive mixed into the shell's output, as they do in
any terminal.

So a session that ends shows what ssh said about it, with Reconnect beside it;
and a host key nobody has seen stops the session and asks, with the fingerprint
ssh printed. Answering writes `yes` or `no` back to the pty, which is exactly
what answering ssh would do, and the key lands in `known_hosts` the usual way.
The question is only recognised at the end of the buffer, because ssh writes it
last and then waits — matching it anywhere left a session stuck on a prompt
that had already been answered. That rule is `Terminal/HostKey.swift`, out on
its own so it can be asked without a pty, an unknown host or a window; the
tests include the stuck case, and the boundary of how far back it looks.

**A password is typed into the terminal**, as it would be anywhere else. An
askpass helper answering from the keychain was built and taken out with
credentials, so the app no longer answers a prompt at all — and an sftp child,
which is given `BatchMode=yes`, cannot reach a host that takes only a password.

## The settings file

`config.yaml` names `ssh_options` that reach every connection the app makes,
and `themes:` for terminal palettes — eighteen colours is a thing to paste,
not a thing to fill in on a form. Options are ordered by how specific they
are, because ssh keeps the **first** value it is given: the host's own, then
each group going up, then the config's.

## What the window shows

- Hosts in their groups, folded on open under a "Hosts" heading, with the tags
  they carry along the bottom and a search that takes a name, an address, a
  user or a tag.
- ⌘K to connect to a host by part of its name, nearest match first, with the
  arrows moving the highlight.
- A host's detail: where it goes, what it logs in as, the `ssh` line it will
  actually be given, the sessions already open on it, and beside each value
  the group it came from. An ssh config entry that takes this host's name
  somewhere else is called out, since the settings written there are not this
  host's.
- An editor whose empty fields say what they would inherit, so leaving one
  empty reads as a decision rather than an omission.
- Importing from `~/.ssh/config`, a CSV, or this app's own YAML, with a
  preview of exactly what the import will do.
- ⌘F searches the scrollback, ⌘G and ⇧⌘G walk the matches, and ⌘+, ⌘- and ⌘0
  size the text. Links in the output are already clickable: SwiftTerm opens
  them itself.
- SFTP: a window of its own, one at a time, this Mac on the left and a host on
  the right, with transfers along the bottom. The session is kept open, so
  walking into a directory is not a connection each time, and progress counts
  the bytes. Carrying a file onto one already there asks before replacing it.
- Two sessions side by side, which shows a session that already exists rather
  than making a pane a thing of its own.
- Menus. Every shortcut is in one, because a shortcut that is only on a
  toolbar button is a shortcut nobody finds. **A menu is named for what its
  items act on**, and that is what gates it: **Host** needs one selected,
  **Terminal** needs a session in front, and the app menu's own two — Hosts
  and SFTP — need nothing.

macOS restores the window; the app restores what was selected in it. Nothing
reconnects on its own — opening a window should not reach out to other
people's machines.

## SFTP

Version 3, written here, over the pipe `ssh -s sftp` opens. Driving `sftp -b`
instead would have been a tenth of the code and lost the byte-level progress
the transfer list shows. Reads are pipelined eight deep, and only whole chunks
are committed — a server may answer a read short, and code that assumed
otherwise would write a file with a hole in it.

Transfers queue rather than all starting at once: one file's turn ends with a
close and the next begins with an open and a stat, so a second transfer keeps
the link busy across that gap, while many at once are back to competing for
the one connection.

## Importing

Three shapes arrive — OpenSSH's own config, a CSV, and this app's YAML — and
all three become one `Portable.Document`, so the merge, the preview and the
apply are one path rather than three. The preview is the plan the import
applies, not a second implementation that predicts it.

The merge **fills in and corrects but never blanks**, which is what lets a
config be imported twice without the second pass wiping something added in
between. An unsupported `Match` block is skipped rather than refusing the
file: a `Match exec` cannot be answered from here, and importing the rest of a
config beats importing none of it. Keys the app no longer keeps are accepted,
dropped, and listed in the preview — refusing a whole file over a field that
is no longer read would be worse than saying what was passed over.

## Building and checking it

```bash
xcodegen generate               # after adding or removing a file
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project Shellhand.xcodeproj -scheme Shellhand -configuration Debug \
  -destination "platform=macOS" -derivedDataPath build -skipPackagePluginValidation
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Shellhand.xcodeproj -scheme Shellhand -configuration Debug \
  -destination "platform=macOS" -derivedDataPath build -skipPackagePluginValidation
```

`Tests/` is the whole suite: inheritance, the argv, the merge, the delete
rules, SFTP's wire format and the conversation over it — including against
OpenSSH's own `sftp-server` — the `ssh` layer itself against macOS's own
`sshd`, and a terminal session over it, real host-key prompt included, the
transfer queue,
validation, themes, tags — and the rules lifted out of the layers above
`Core/`, which is most of what used to be out of reach. What is under what and
the fold the sidebar opens on; what a file pane calls itself and how it names a
child; which tab is in front, what is beside it, and what ⌘D and closing a tab
do; what ⌘K offers for what was typed; the sidebar flattened into one list and
what search narrows it to; whether ssh is waiting to be told about a host key,
and which part of the screen is the question; what a session's state becomes
given what is on its screen. None of those needs a window, because none of
them keeps state — the views still own that and simply obey.

**What it still does not do is drive the views themselves.** One thing checks
the app end to end: `scripts/window-check.sh`, which seeds a store of its own,
launches a real window against it with `--db`, and walks the sidebar through
System Events the way somebody on the keyboard does — folded as it comes up,
then opened with the arrow keys, then a row picked and the **Host** menu read
back to prove the selection reached the app rather than only the outline. It
asks the app for nothing it does not already publish. Everything else above
`Core/` is judged by building it and using it — which is why so much of
`CLAUDE.md` is about what that costs and how to do it without being fooled.

A release is `scripts/release.sh`, which takes it from `xcodebuild` through
signing, notarization and a stapled DMG to a signed appcast and an updated
cask — and **publishes nothing**, printing the two commands that would.

## Traps worth knowing

**A binding that cannot say no.** Three of these turned up together. An error
alert bound to `.constant(store.lastError != nil)` could not be dismissed and
came straight back. A sheet driven by a flag rather than `.sheet(item:)` could
open with nothing to show. A host-key prompt on a constant binding left the
session hanging when dismissed — that question is a decision and ssh is
waiting on it, so dismissing it any other way now answers no.

**A terminal can only be in one place.** The pane showing a session sits at
the same spot in the view tree whichever tab is in front, so SwiftUI saw no
reason to rebuild it: the first session's terminal was handed over once and
every tab showed that one. A terminal is an `NSView` and a representable
cannot swap the view it already returned, so the identity has to change, which
`.id(session.id)` does. The same fact bites in a split: showing the session
already beside the front one would ask for one view in two places, so the two
panes trade places instead.

Focus belongs to the view for the same reason. Handing it the keyboard from
the representable does nothing, because at that moment the terminal is not in
a window yet; `viewDidMoveToWindow` is where it knows.

**A list cannot hold two shapes.** Searching used to swap the sidebar from a
tree of nested `DisclosureGroup`s to a flat section of matches. AppKit kept
rows of the shape it had just left and drew them over the new ones, and
because the leftovers were real rows they survived clearing the search and
piled up. The tree is flattened to rows now — one `ForEach` over one array —
so filtering is an ordinary row diff.

**A name that means two things.** `Sessions` had a `current` meaning "the
session whose id is selected", which was the same as "the session in front"
right up until the hosts tab could be in front too. It then became quietly
wrong in four places at once: the inspector, the window title, the subtitle
and the whole Terminal menu, where it left ⌘W closing a session off screen.
What is in front is `ContentView.pane`; `current` is gone so it cannot be
asked again.

`CLAUDE.md` has the rest, and there are a lot of them.

## Two names to know

`Group` and `Host` are this app's own types, and SwiftUI has a `Group` of its
own; `Color` belongs to both SwiftUI and SwiftTerm. Write `SwiftUI.Group` and
`SwiftUI.Color` in a file that hits them.

## Not here yet

**Files cannot reach a host that takes only a password.** An `sftp` child is
given `BatchMode=yes`, so there is nothing left to answer a prompt with. It is
the one capability the cut back to an MVP costs; a session to such a host still
works, because ssh asks on the pty where it can be typed.

**A host-key question is found by putting rows back together, not by reading
logical lines.** It is found and shown whole down to about three columns, which
is narrower than anyone types in, but the right fix is still at the source —
have `screen` rejoin wrapped rows, so every reader sees logical lines — and it
is not available: SwiftTerm keeps `Buffer.lines` and `Terminal.cols` internal,
so the app cannot ask how wide the terminal is or which rows continued.

**And one bug is bounded rather than understood.** A run of the suite once sat
sixteen minutes on a single SFTP conversation, with both pipe reader threads
idle and a continuation nothing was ever going to resume. It is episodic, it
has turned up in three different tests — including the minimal conversation, so
every theory about batching and framing is dead — and a clean batch proves
nothing about it, however long. A request carries a deadline now, so the next
sighting is a named failure saying which request went unanswered. That is not
an explanation; it is a way of buying one cheaply.
