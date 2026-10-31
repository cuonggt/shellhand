# The window: how its rules were found

Moved here word for word from `CLAUDE.md`, which keeps each rule in a line or
three and links to the story it came from. They stand in the order they stood
there, so "above" and "below" mean in this file, unless a story names a rule
that stayed in `CLAUDE.md`.

## The host pane

**The host pane shows the list, always; the inspector says what a host is.**
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
**The grid has arrow keys now, and the order of work is the point.** A
`LazyVGrid` has no keyboard either, so the first question was whether a key
reaches one at all — answered with a throwaway probe before a line of the
rule was written, because a rule nothing could use would have been a wasted
afternoon. It does: `.focusable()` on the scroll view plus `.onKeyPress`,
and the selection walked. Focus has to arrive first, which a click does and
Tab does.
**`Views/GridMove.swift` is the rule, and it takes the sections rather than
one flat run of cards.** The pane draws **two** grids — the groups, then
the hosts — so flat arithmetic gets the boundary wrong: with two groups and
four columns, "down" from the first group lands four cards into the hosts
instead of on the card drawn beneath it.
**The tests found two bugs in it, and the second only because the first was
being fixed.** "Up" from the top row clamped to the first card, which is not
up. And "down" from a card already in the **last row** slid sideways to the
last card, because that case had been conflated with the **ragged gap** —
being above a column the final row never filled, where falling to the last
card is right. They look identical in the arithmetic and are opposite in
meaning; only the first had a test, and writing one for the second is what
made it visible.
**The column count is derived, not published.** `.adaptive` settles it at
layout time and SwiftUI says nothing, so a `GeometryReader` measures the
width and the view repeats `.adaptive`'s own sum: as many cards of the
minimum width as fit, counting the gaps. Measure **inside** the frame and
**outside** the padding — the scroll view is 48pt wider and puts the count
one out at some sizes. Checked against a real window at 1728pt wide, where
it settles on four and the moves matched the rule exactly.
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
**The row menu is one definition, `Views/RowMenu.swift`**, carried by a
sidebar row, a pane row and a grid card alike — the user asked for the same
menu, and two copies of a decision drift, which the local-copy error
handling proved by doing it for months.
**Everything in it is handed its subject rather than reading the
selection**, which `AppActions.newHostIn` already did and said why. In the
sidebar and the pane's list it would not matter, since
`contextMenu(forSelectionType:)` selects the row first — but a
`contextMenu` on a **card** does not, so a menu reading the selection would
edit
or delete whichever host was picked before. `AppActions.onHost` holds those
versions.
**Selecting a host opens the inspector**, since that is where a host is
described and a selection that shows nothing reads as a click that failed.
It is set from `onChange(of: selection)` **deferred a turn of the loop** —
the same hop the inspector has always needed, because changing it in the
update that also moves the pane is the "reentrant operation" crash. That is
intermittent, so it was driven twelve times rather than once, and the
process was still up at the end.
**No focus ring on the pane.** The grid is `.focusable()` for the arrow
keys, not to be outlined: a ring around the whole pane is a lot of chrome
for "the arrows will go here", and the selected card already says where
they will land. `.focusEffectDisabled()` on both the list and the grid.

## Closing

**"Ask before closing a live session" switched nothing for every release up
to 0.0.11.** The toggle was in Settings from the day it was added and no
code read its key: ⌘W, a tab's ×, the window's close button and ⌘Q all
dropped live sessions while Settings said they would ask. **The sweep for
dead declarations cannot see this shape** — it counts functions, and a
preference key is a string — so sweep the keys as well: every
`@AppStorage` key against every place that acts on it. A key whose only
reader is the switch that writes it is this bug; a key mentioned once and
read by the very view that declares it, like `hostInspector`, is fine.
Run on 2026-10-29, this was the only one.
The rule is `Views/Closing.swift`, pure: a session is **live** when it is
`.connected` — somebody is in it — so one still connecting, one waiting on
a host-key answer and one that has ended all close without a word; a local
shell is connected from the start. ⌘R asks too, since reconnecting a live
session drops it as surely as ⌘W does. Absent means **ask**, which is what
the switch shows — `UserDefaults.bool(forKey:)` would have said no, so it
is not used. Three places put the question, each where it can be put:
- **⌘W, ⌘R and a tab's ×** go through `ContentView.end`, a
  `confirmationDialog` like the delete ones. The × used to call
  `sessions.close` itself, so it is handed back to the window now.
- **The window** asks through `ClosingGuard`, which stands **in front of**
  SwiftUI's own delegate rather than replacing it. Measured before it was
  written: the host window's delegate is SwiftUI's `AppKitWindowController`,
  which answers `windowShouldClose` itself and hears the window become key,
  resize and close — cut it off and SwiftUI loses its own window. So
  everything the guard does not answer is forwarded, and once the question
  is answered yes, SwiftUI's own answer is asked too. The **window** holds
  the guard, as an associated object: a delegate is held weakly, and a
  guard owned by a view SwiftUI rebuilt would have left the window with no
  delegate at all. This catches the close button. **⌘W never reaches the
  window**, which was written here the other way round until a drive
  measured it: "Close Tab" holds ⌘W, so with the Hosts tab in front ⌘W does
  nothing — neither asks nor closes. It held it then beside SwiftUI's own
  File ▸ Close, which was left with **no key equivalent at all** — until
  0.1.3 made the item's title change with what is in front (Close Window
  over SFTP and Settings). From then SwiftUI gave ⌘W to its own Close
  instead, and nothing said so: ⌘W on a tab put up the **window's**
  question, "Close the window and end the session on …?", and with nothing
  live it closed the window and every tab in it. The walk after 0.1.4 read
  it off the menu, where Close Tab had no key, and one ⌘W pressed as a key
  confirmed it. Which of two items on one key gets it is SwiftUI's to
  decide, so the fix leaves it nothing to decide: Close Tab stands in place
  of the system's Close and Close All (`CommandGroup(replacing:
  .saveItem)`), and `window-check.sh` checks that it alone holds ⌘W. Driven
  after the fix: a stopped tab and a refused one closed without a word, the
  hosts tab alone did nothing, a live local shell asked the tab's question,
  and Settings and SFTP closed.
- **⌘Q** asks in `ShellhandAppDelegate.applicationShouldTerminate`, through
  `@NSApplicationDelegateAdaptor` — the app's first delegate. It needs
  every window's sessions, and a delegate cannot reach a window's state,
  so `Sessions` keeps a weak list of itself. Sparkle relaunching for an
  update goes through here too, and that is wanted: an install should not
  drop sessions behind somebody's back either.
`Tests/ClosingTests.swift` holds the rule and three of the links, each
checked the way round that matters: with `Sessions` not listing itself the
quit test fails; with the guard not put up the window test fails; and with
a guard that **replaces** SwiftUI's delegate rather than standing in front
of it, the window test fails on all three counts and nothing else does.
**What no test reaches** is the presenting — the dialog, the sheet, the
alert — and the delegate adaptor's hook-up. Those were proven on
2026-10-29 by driving a scratch copy, cancelling each: ⌘W and File ▸ Close
Tab on a local shell, ⌘R on a live ssh session, the close button, File ▸
Close and ⌘Q all put their question with the right words, Cancel left
everything open, and a second ⌘Q answered Quit did quit. ⌘R on a local
shell asks nothing, since it has no host to reconnect to. If you touch any
of it, drive it again; three things made that cheap:
- **A live ssh session needs no machine of yours**: macOS's own `sshd`
  as you on `127.0.0.1`, as `LocalSSHD` makes one, with the host's own
  `-o` settings pinning it — `HostName`, `ProxyJump=none`,
  `ProxyCommand=none`, known hosts in scratch, no agent, no control
  socket — since a real session reads `~/.ssh/config` and a `Host *`
  `ProxyJump` there would otherwise take it through a real bastion.
  Expect **two** logins per connect, not one: the second is the
  once-a-day OS probe.
- **A menu item answers AXPress**, so File ▸ New Local Shell and Close
  Tab can be clicked with no keystroke at all, and a sheet's Cancel the
  same way. Keys still need the copy in front, checked before every one,
  and the lock checked too: behind a lock a key goes to the login window.
- **`kind` is a reserved word in System Events.** `set kind to …` fails
  with *"Can't set kind"*, and a helper that hid its stderr turned that
  into five pictures silently not taken.
The two kinds of question look slightly different: the tab's is SwiftUI's
`confirmationDialog`, with a red Close that is not the default, while the
window's and quitting's are `NSAlert`s whose Close or Quit is the blue
default, so Return answers those and not the tab's.

## Menus

**A menu is named for what its items act on**, and that is also what gates
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

## The toolbar

**The toolbar is placed by the same rule as the menus** — by what each item
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

## Connecting from the list

**Connect is not in the toolbar.** It was the one item that appeared and
disappeared with the selection, so every button to its right slid sideways
as you clicked down the list — what a width that jumps between sheets does
under the pointer. It was also the third copy of it — and the three are
now the **inspector**, under the host's own name; the Host menu's ⌘↩; and
**⏎ in the list**, which is where the hand already is once you have arrowed
to a row. The toolbar is still not one of them, and the reason has not
changed.
**A double-click connects as well, and how it is done is the whole
lesson.** The first attempt was a `TapGesture(count: 2)`, and it cost
**every single click** the system's double-click interval — a tap gesture
for two clicks cannot tell one click from the first of a pair until that
interval has passed, so the row did not light up until it had. It shipped,
a user felt it immediately, and it came out. **Checking that the gesture
did not take the click was the wrong question**: it did not, and it still
had to go.
**What works costs nothing: `primaryAction` on
`contextMenu(forSelectionType:)`,** which is AppKit's own double-click
action rather than a gesture, so the first click still selects at once. The
sidebar had been using it the whole time — the mechanism was already in the
codebase while a worse one was being invented beside it. Look for the native
hook before reaching for a gesture.
**`primaryAction` is a `List` feature, though, and the grid is not one.**
Wiring it covered the rows and quietly left the cards without a
double-click at all — the half that could be tested from a script was the
half that got fixed, and the user browses in grid mode.
**What the cards use is three words: `NSApp.currentEvent?.clickCount`.** The
button already fires once per click, so the second click of a double arrives
in the same action carrying a count of 2; reading the triggering event is
the whole mechanism. Nothing is disambiguating, so the first click still
selects at once.
**Two attempts failed first and neither should be tried again.** A
`TapGesture(count: 2)` taxed every single click, as above. An
`NSClickGestureRecognizer` on the card's **superview** — with
`delaysPrimaryMouseButtonEvents` off, which is the right knob for that
approach — never fired at all: a SwiftUI `Button` consumes the clicks
before an AppKit recogniser above it sees them. It built, read plausibly,
and it
did nothing, which is the third time in two days that the untestable half
was where the defect went.

## Hosts and SFTP

**Hosts is the one menu item that cannot go through `AppActions`.** That is
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

## The inspector crash

**Changing the inspector in the same update that swaps the pane crashes
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

## The tab keys

**⇧⌘] and ⇧⌘[ step through the strip, and so do ⌃⇥ and ⌃⇧⇥.** The rule
is `Panes.stepping`: the hosts, then the sessions as they were opened,
round from the last to the first, the way Terminal.app and Safari go. **The
hosts are a stop**, unlike in `splitting` — they lead the strip and cannot
be closed, so skipping them would leave a tab the keys could not reach. It
goes through `pick`, so a tab shown beside trades places exactly as a click
on it does. Nil when only the hosts are there, which greys the items out.
**An item holds one key**, so the Window menu carries "Show Previous Tab"
and "Show Next Tab" on ⇧⌘[ and ⇧⌘], and ⌃⇥ is `StepsTabs`'s: a local key
monitor behind the host list, which also sees the key before the terminal
in front can take it as a control key. It acts only on keys meant for the
host window — a sheet is a window of its own — and lets ⌃⇥ through when
there was nowhere to step to. Measured before choosing either: the Window
menu held no "Show Next Tab" of AppKit's, since no window here is a native
tab, so neither pair was taken. `Tests/TabKeysTests.swift` asks real
`NSEvent`s which keys count, Caps Lock included and ⌃⌥⇥ not.
**Driven on a scratch copy on 2026-10-29**, with the front tab read two
ways — the window's title, and whether the Terminal menu is live — since
the strip's own buttons publish no selection: all four keys moved it, ⇧⌘]
on a US keyboard included, where the chord types `}`. ⌃⇥ missed once in
five presses and did not miss again in the identical sequence run straight
after, which reads as the dropped synthetic keystrokes noted under Quick
Connect rather than as the monitor. A hand on the keyboard settles it.

## The tab menu

**A tab has a menu of its own**: Reconnect, Duplicate, SFTP, Close Tab and
Close Other Tabs. **Each is handed its session** through `TabActions`, the
rule a row's menu already keeps: right-clicking a tab does not bring it in
front, so a menu that read the session in front would reconnect or close
some other tab. Nothing in it decides anything of its own. Reconnect and
Close go through `end`, so they put ⌘R's and ⌘W's questions; Duplicate is
`Panes.newTab` asked of that tab, so it is ⌘T for it and greys out for a
host since deleted; SFTP is `Panes.sftp`, offered only for a saved host the
list still holds — a local shell is this Mac, the window's left side
already, and a machine typed into ⌘K has no entry to open a file session
from. Close Other Tabs asks once for all of them — `Closing.closingOthers`
counts every tab going and names only the live ones — and brings the kept
tab in front. Close Tab was not asked for and is there because a tab menu
with Close Others and no Close reads as a mistake.

## Help

**Help has two items now**: Shellhand Help opens the README, and Report a
Problem… opens the problem form, `.github/ISSUE_TEMPLATE/problem.yml`,
with its version and macOS fields filled in — GitHub's form schema fills a
field from the query item named for its `id`. The link is `Help.report`,
pure and tested, and carries **nothing else** — a URL lives on in a
browser's history, so no host name goes near it, and the form asks people
to leave theirs out of a public issue too. Questions go to Discussions,
through the contact link in the same folder's `config.yml`. The system's
own Help item, replaced, only said help was not available.
**Those ids are as permanent as `SUFeedURL`**: a build opens the link it
was born with for ever, so a field renamed in the form arrives empty from
every copy already out. `HelpTests` reads the form from this tree the way
the app reads YAML, through `YAMLDocuments`, and fails when the link names
a field the form lacks or the form is not YAML at all: with `macos`
renamed in the form only that test fails, and an unclosed quote fails it
with Yams's own line and column.
**The suite can import Yams the way it imports SwiftTerm**, taking the
code from the app's build rather than linking a copy — with `import Yams`
in a test, the only Yams symbols its binary defined were the glue any
caller emits, metadata caches and `load_all`'s default arguments. This
note said the opposite for a day, and the test read lines instead;
`import SwiftTerm` in `TerminalSessionTests` was the counterexample all
along.
**0.1.0 shipped
the older link**, a blank issue with the questions in its body, so
`config.yml` keeps `blank_issues_enabled: true`, and a test holds that too.
**Live since 2026-10-29, and checked as far as no sign-in allowed.**
GitHub's page for the file renders it as a form — the four fields, each
required, with the label and the privacy note — and no error, so GitHub
parses it; the API serves the contact link, and the Discussions page it
opens answers 200. GraphQL's `issueTemplates` came back empty and the
community profile said `issue_template: false` while that page rendered
the form, so neither is evidence about a form either way. **Not checked:**
what the new link opens, and what 0.1.0's blank-issue link opens now that
there are templates — both pages need a browser signed in to GitHub, and
none was to hand. Open both, signed in, before relying on either.
**Quote a placeholder that looks like a number**: `26.1` bare is a float,
and the schema wants a string. Ruby's YAML, which macOS ships, checked both
files against the rules GitHub documents, and caught exactly that in a
control copy.

## Typed destinations

**⌘K connects to machines that are not in the list**: `host`, `user@host`,
`host:port`, `[v6]:port`, or an `ssh://` link, read by
`QuickConnect.destination` and offered as one more row, "Connect to …".
**Where that row goes is the rule**, in `QuickConnect.rows`: a saved host
that what was typed names exactly comes first — its name, or its address
with no user or port typed that says otherwise — so its key and jump host
still apply; then the typed row when it could only be a destination (a
user, a port, a dot or IPv6), so `10.0.1.5` is not beaten by a host at
`10.0.1.50`; and a bare word stays a search, its row last, so `web` is
`web-1` before it is a machine called `web`.
**Nothing may start with `-`**: the destination ends ssh's command line and
ssh reads such an argument as an option, so `-p` typed here would not be a
host. Checked the way round that matters — with that refusal out, only the
test for it fails, on `-p`, `-l@web` and `-x@web:22`; `-oProxyCommand=…`
is refused anyway, since `=` is no part of a name.
**The machine is a `Host` with an empty id**, made by
`QuickConnect.unsaved` and named as typed. The empty id is the whole
mechanism: `HostStore.sshArgs` resolves it as it stands, the way the editor
previews a draft, where a saved host is looked up (`HostStoreTests` pins
it: with that branch out, the typed host gets no line and an error saying
it "is no longer in the list") — and it keeps the host
out of the list, out of the inspector, out of a group's repaint and out of
the once-a-day OS question, whose `shouldAskOS` already refuses an empty
id. ⌘R reconnects it the same way, and ⌘T opens another of it through
`Panes.Opening.unsaved`, carried whole since there is nowhere to look it
up. The inspector says "Nothing selected" for its tab: there is no saved
host to describe.

## Rules upward

**The same rule now applies upward, not just to data.** `Views/Panes.swift`
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

## The name SFTP

**It is called SFTP, everywhere**: the app menu, the toolbar, a row's menu,
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

## A toolbar per column

**Each column carries its own `.toolbar`**, and that is the whole trick.
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

## New Group

**New Group… lives in File**, beside New Host… and Import… — it makes
something rather than acting on what is selected, so it is not in Host.
It does read the selection, though: a group selected means the new one goes
inside it. So the item **says where it will land** — "New Group Inside
Production…" — rather than leaving you to open the editor and read its
parent picker. An item that quietly does two things has earned a longer
label. The sidebar's own version can say just "Inside" because the row it
came from names the group; the menu bar has no row, so it names it.

## A row's menu

**A menu on a row acts on that row**, and a group's menu is handed the
group rather than reading it back out of the selection. "New Host…" there
called the same plain action the File menu does, so the one item in a
group's menu that made something made it at the top of the list instead,
while "New Group Inside…" directly below it nested. `newHostIn` takes the
group, which also means ⌘N in the File menu still makes an unfiled host —
two items that look alike must not quietly become one action.

## The strip

**The sessions open are a strip of tabs across the top of the terminal**,
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

## What is on screen

**`Sessions` does not say what is on screen, and must not be asked.** It
had a `current` meaning "the session whose id is selected", which was the
same thing as "the session in front" right up until the hosts could be in
front too. Then it quietly became wrong in four places at once: the host in
the inspector, the name in the title bar, the subtitle, and every item in
the **Terminal** menu — where it left ⌘W closing a session off screen.
`current` is gone so it cannot be asked again; `ContentView.frontSession`
reads `pane`, and anything about what is on screen goes through that.
`Sessions.selected` survives and still means which terminal is current,
which is a different and narrower claim.

## The strip's selection

**The strip's selection is what the pane shows** — `PaneTab`: `.hosts` or
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

## onChange

That replaced a `Bool` called `browsing`, and **the reason it had to go is
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

## The welcome

The **welcome stands in for the hosts tab, not for the window.** On a fresh
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

## New tab

**⌘T opens another of the session in front**: the same host, or another
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

## Windows as tabs

**Making each session its own `NSWindow`,
so that macOS draws them as a real tab bar with the host list as the first
tab, was built and thrown away** — it worked, tab overview and `⌘⇧[` and
dragging a session out included, and it was still not wanted. **Don't offer
it again.** What it cost, for the record: a window per session puts the host
list's store and sheets a scene away, so every menu item needing either has
to be posted back to it, and the split has to go, because macOS already does
side-by-side by dragging a tab out.

## Scenes

There are **no secondary `Window` scenes left**, and only one window this
app makes itself: Settings, an `NSWindowController`. SFTP was a second one
and is a tab again. If a scene is ever added back, two things bit last time:
`openWindow` does nothing unless a live view asks for it (not a `Commands`
body, not an `AppActions` closure — no error, no window), and the **first
scene in `body` is the one macOS opens at launch**, so a secondary one needs
`.defaultLaunchBehavior(.suppressed)` or it comes up instead of the host
list.

## The sidebar's rows

The sidebar's `List` holds **one `ForEach` over one flat array of rows**,
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

## One list

**The sidebar is one list, and a second tab was built and cut.** It had a
Hosts/Library switch above the search field, with Library a menu of three —
Keys, Credentials, Snippets — and the records drawn as cards in the pane.
All three records are gone now, so the switch went with them. Before that,
a sidebar of three **lists** was built and taken out too, because it made
the host list, which is what the window is for, one tab among three. If a
second tab is ever wanted again: one switch over a menu, not a third list.

## Writes while drawing

**A write to the store while a list is drawing is a crash**, not a slow
frame: every save rereads the store and resolves every host's inheritance,
which mutates the array the list view is reading — AppKit calls it a
"reentrant operation in its NSTableView delegate". Nothing saves as it is
typed any more, the editor that did having gone with snippets; if one is
ever written again it has to debounce, replacing the write still waiting,
and flush on disappear so the last characters are not lost.

## A list beside its detail

In a list beside its detail, the **detail side needs `maxWidth: .infinity`**.
With neither side greedy, `HSplitView` shares the spare width between them —
and a `maxWidth` on the list constrains **the list, not its pane**, so the
pane grows past the cap and the list sits centred inside it with a band of
nothing either side. It shows up on **deselecting**, because that is when
the detail collapses to a `ContentUnavailableView` and slack appears.
Collapsing the list's two `.frame`s into one does **not** fix it; that was
the first guess and it changed nothing.

## The Settings window

**Settings is a window this app makes itself**, not a SwiftUI `Settings`
scene: the glass chrome macOS 26 draws comes from `.fullSizeContentView` in
the window's style mask, and a scene does not expose it — setting it
afterwards through an `NSViewRepresentable` does not hold, because SwiftUI
puts the window back the way it had it. So `SettingsWindowController` makes
the `NSWindow`. A window made in code is released when it closes, which
would leave the controller holding a freed one, so it sets
`isReleasedWhenClosed = false`.

## Dialog widths

**Dialogs come in three widths**, in `Views/DialogSize.swift`: 460 for one
question, 560 for one record or a plain list, 820 for a list beside its
detail. This app grew nine — 420, 460, 480, 500, 520, 560, 580, 620, 820 —
each picked by hand, so opening two sheets in a row slid the window sideways
under the pointer. **Width only**: height stays with each dialog, measured,
because a width that jumps between sheets is jarring and a height that does
is not — and both times a height was handed down rather than measured here,
it clipped the last row.

## Marks in a segment

**That mark has to be a character, not an SF Symbol.** A segment of a
`.pickerStyle(.segmented)` picker takes a label **string**, so an `Image`
interpolated into its `Text` has nowhere to live: it collapses to U+FFFC and
draws nothing. The trap is that accessibility reports the label as
`"Advanced ￼"`, so a probe reads back a mark that is not on the screen —
this was only caught by cropping the tab strip out of a screenshot and
looking. Written as an Image, the host editor's mark had never once
appeared.

## The group editor

**The group editor has the same two tabs**, but not the same line between
them: a group is never reached, so General is what the group *is* and who
the hosts under it log in as, and Advanced is what happens once you are on
one of them. Its Advanced says `•` when something over there is merely set,
which the host editor has no need of — the one thing groups are most used
for is a palette, and the `DisclosureGroup` this replaced decided whether to
open itself from the ssh options and the agent alone, never looking at the
palette. So a group that painted its hosts opened with the palette shut and
nothing to hint at it.

## Where a value comes from

The group editor says **where an inherited value comes from beside the
field**, not inside the placeholder. Folding both into one grey string
("deploy — from Production") meant the field had to be read to learn two
different things, and it left nothing to say when a value was inherited from
nowhere — which is how `—` ended up sitting there looking like a value. The
placeholder is now the inherited value or an example, and the source is a
caption of its own, which is what the host editor already did.

## Naming a stack

A button whose label is a stack has **no accessibility name**: these read as
"button 1, button 2, button 3". Name it with `.accessibilityLabel`, placed on
the button before the background and border wrap it in layers of their own.
Not `.accessibilityElement(children: .ignore)` — that names the row but
replaces the button's own element, and then pressing it does nothing at all.
The label lands in `AXAttributedDescription`, which AppleScript cannot read
back, so `description of button 1` still says "button".
