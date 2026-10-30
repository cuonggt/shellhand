# Driving the app from outside: how its rules were found

Moved here word for word from `CLAUDE.md`, which keeps each rule in a line or
three and links to the story it came from. They stand in the order they stood
there, so "above" and "below" mean in this file, unless a story names a rule
that stayed in `CLAUDE.md`.

## Preferences

**`@AppStorage` is keyed by the bundle id, not by `--db`.** A run against a
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

## System Events

**The whole window can be driven through System Events, sidebar included** —
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

## The lock

**A locked screen looks exactly like an app that failed to launch.** With
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

## Taking the README's picture

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

## Quick Connect

**Driving Quick Connect against a real host list connects to a real
machine.** Return activates the highlighted match, and synthetic keystrokes
here are not reliable — they get dropped (three arrows moved the highlight
one row at one-second spacing, all three at two seconds) and they arrive
late, so a Return meant for one step can land in another. That is how a
session to a live host opened during a check nobody asked to connect.
Escape is **not** the culprit: it dismisses and never activates, measured
six times. Give the scratch store a host pointing at `127.0.0.1:1` and
drive that instead — it fails instantly with status 255 and reaches
nothing.

## Accessibility names

**Don't try to check that through System Events.** It reports every SwiftUI
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

## Does it fit

The test for "does it fit" is the form's scroll area — the `AXScrollArea`
that is a **direct** child of the sheet's top group, not a recursive search,
because the ssh options text editor is itself a scroll area and reports an
overflow that is not there. No `AXScrollBar` among its direct children means
it fits. If there is one, its `AXValueIndicator` gives the answer in one
pass rather than by bisecting heights: content height is the form's height
times track ÷ thumb, so a 284pt thumb in a 333pt track over a 331pt form
means 388pt of content and 57pt missing.

## Arrowing

**Arrow keys do reach a group row — focus the outline once and then
arrow.** Re-focusing it before each press puts the selection back where it
started, so a loop that focuses, presses Down, and checks never gets past
the first row; that is what made group rows look unreachable and `Edit
Group…` look permanently disabled. One `set focused of <the AXOutline> to
true`, then as many `key code 125` as you need, and the selection walks the
list — groups included. A synthetic `click at` genuinely does nothing here,
which is the part that is true.

## Capturing

Capturing a window **without** taking focus does not work here: the modern
way is ScreenCaptureKit (`CGWindowListCreateImage` is now unavailable, not
merely deprecated), a plain command-line tool needs `NSApplication.shared`
before it or CoreGraphics trips `CGS_REQUIRE_INIT`, and then
`SCScreenshotManager` still fails with -3811 because Screen Recording is
granted per binary and a freshly built one has not been granted it. So
screenshots need the app frontmost — which means **not while the user is
typing in another app**. Check who is frontmost first and skip rather than
fight for it.

## screencapture

A screenshot taken with `screencapture -R` captures **the screen at that
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

## The restored title

**A restored window title can read as a live connection.** On launch the
window briefly carries the title of a session from a previous run — a real
shell prompt, `root@ip-…: ~`, with the host as the subtitle — before
SwiftUI's own `.navigationTitle` overwrites it with the truth. It is state
AppKit restores, not a session: nothing has connected, and in the same
moment there is no `ssh` child process and no established socket. This cost
two separate alarms in one sitting, both of them a production hostname that
was never contacted. **The title is not evidence.** `pgrep -P <pid>` is:
this app connects by spawning `ssh` on a pty, so no child means no
connection.
