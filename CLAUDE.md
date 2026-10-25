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
builder, the config, YAML and `ssh_config`, the script runner and SFTP. Everything above it — `Model/`, `Terminal/`, `Views/` — goes through
`Core`, an actor holding the store connection and the sessions, runs and
transfers that outlive the call that started them.

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

`Tests/` is the whole suite, and it covers `Core/` only. **Nothing checks the
app end to end.** Three shell harnesses once did — the terminal on a real pty,
the window from store to sidebar, SFTP against a loopback server — and they
were removed along with the loopback servers and the flags the app published
for them. So a change above `Core/` is judged by building it and using it,
which is what most of the warnings further down are about. The harnesses are
in the pre-reset bundle if they are ever wanted back, not in this
repository's history.

The app icon has tooling of its own, because an Icon Composer bundle cannot be
judged by reading its SVG — the squircle, the gradient, the shadow and the
specular are added by macOS when it is composited:

```bash
python3 tools/icon.py Shellhand/Resources/Shellhand.icon   # rewrite the bundle
./tools/icon-preview.sh /tmp/shellhand-icon                # render it small
```

`docs/app-icon.md` says why the format and the mark are what they are.

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
- ssh options are ordered by how specific they are, because ssh keeps the
  **first** value it is given for a setting: what a caller must not have
  overridden leads, then the host's own, then each
  group going up, then the config's, which apply to everything. A setting
  written against one machine beats the default written for all of them.
  Within one call, options passed as `extra` still come after the config's.
- Swift 6 language mode, the app target MainActor by default. The engine is
  `nonisolated` throughout — mark extensions of its types `nonisolated` too, or
  their members pick the default back up.
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
  under the pointer. It was also the third copy of it: the detail pane offers
  Connect under the host's own name, and the Host menu has ⌘↩.
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
  SFTP still goes through `AppActions`, because opening the window needs the
  store the host window holds — so **⌘B is dead while the SFTP window itself
  is in front**. Bring the host list forward and it works.
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
- The test bundle is **hosted by the app**, so running the suite launches it.
  With no `--db` that opened and migrated the real host list. `LaunchOptions`
  sends a run under XCTest to a store in the temporary directory; keep it that
  way, and check the real store's timestamp if you ever touch that code. It
  is the only reason `LaunchOptions` reads the environment at all.
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
  edit and no preference to put back. Ungated routes are still the cheapest
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

Release packaging (Sparkle, a notarized DMG, a Homebrew cask) is not set up
yet. Hopmeter's `scripts/release.sh` in `~/Projects/nettoolbox` is the model.
