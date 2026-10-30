# The OS marks: how their rules were found

Moved here word for word from `CLAUDE.md`, which keeps each rule in a line or
three and links to the story it came from. Where a story says "above" or
"below", it names a rule that stayed in `CLAUDE.md`.

## The OS marks

**A host is drawn with its operating system's own mark, learned on the first
connect.** `Core.osOf` opens a connection of its own, reads
`/etc/os-release` — a plain `KEY=value` file every modern Linux ships, so
the app can **read** the answer over SFTP rather than run a command for it,
which would mean bringing back the process machinery deleted as dead code —
and `OSRelease` parses it. `Views/HostIcon.swift` draws the mark where there
is one and `server.rack` where there is not.
**Nothing lists the distributions.** A mark is found by filename:
`os-ubuntu.svg` for a machine whose `ID` is `ubuntu`, so adding one is
dropping a file into `Shellhand/Resources/OSMarks` and removing one is
deleting it. `ID_LIKE` is the fallback, so a derivative that forgets `ID`
gets its family's mark; that is how Raspberry Pi OS draws Debian's without
one of its own. A distribution whose `ID` **is** its own does not fall back,
which is why `opensuse-leap` has a file rather than leaning on `opensuse`.
**30 marks ship: a tile in the distribution's colour carrying its own
logo.** The logos are Simple Icons', **CC0**, vendored in `tools/logos/` so
the generator runs offline and so what is composed can be read before it
ships — each was checked to be the single-path 24×24 silhouette that format
promises, and the generator refuses anything else rather than composing what
it did not expect. `tools/osmarks.swift` holds the table and is the only way
to change them, the arrangement `tools/icon.py` has for the app icon, with
`tools/osmarks-preview.swift` as the sibling of `icon-preview.sh`.
**CC0 covers the files and says nothing about the trademarks**, which is the
part worth keeping straight: a distribution's logo beside a server running
that distribution identifies the machine, which is nominative use and what
every hosting panel does. It is not branding, so these belong on a host row
and nowhere else — not the app icon, not a README header, not a website.
Policies differ and Canonical's is among the strictest, so a listing or an
OEM bundle is worth a read of each project's policy rather than an
assumption that CC0 settled it. `tools/logos/README.md` says all of this
where somebody changing a logo will meet it.
**The letter tile is still there and still earns its place.** Every mark was
one before the logos arrived, and a distribution with no logo falls back to
it — as **NetBSD does on purpose**, because its mark is a *wordmark*, and a
wordmark at 16pt is an unreadable smear rather than a small version of
itself. Fine linework is the softer version of the same problem: Kali's
dragon and the CentOS lattice go grey at a row's size and are carried by
their colour there. Both are judgements made with the contact sheet in
front of you, which is what it is for.
**Two things that generator settles rather than guesses, both measured.**
Apple's SVG support renders **no `<text>` at all** — checked with a white
glyph on an orange tile, every sampled pixel coming back orange — so the
letters are converted to outlines by CoreText at generation time. An SVG
naming a font would have drawn as an empty tile, silently, on any Mac
lacking it. And the **ink is chosen by contrast**, white or near-black
whichever measures higher against the tile: white on amber or a mid-green is
about 2.3:1 and unreadable at the size these are looked at. The threshold is
not a number that looked right — white gives 1.05/(L+0.05) and this
near-black 0.061, so they cross at L = 0.203, and the tool reports what each
mark measured. The lowest is 4.4:1, and the first pass — a threshold picked
by eye at 0.42 — left every green under 2.4:1.
**A mark is drawn at the full slot, and the plain glyph stands for a host
nobody has asked.** Which took three goes, and the two wrong ones are worth
keeping because each looked right on its own terms.
First the marks were shrunk to **0.9** of the slot, to match the drawn
height of `server.rack` — measured at 58 of 64 pixels. That is the wrong
target: the glyph is **wider than it is tall**, so matching its height left
the marks visibly narrower, and they read as small rather than as equal.
Then both were made tiles — a grey badge with the symbol on it — which does
make them weigh the same: measured, a mark inks **79%** of its slot against
line art's **36%**, and as badges all three came to 96%. It was asked for
and then asked back out, for a reason worth recording: a host nobody has
asked yet should look like an **absence**, not like a badge meaning
"unknown".
So they share the **slot and the size** and not the weight, and the weight
difference is accepted rather than engineered away. `Tests/HostIconTests.swift`
checks what is meant to hold: a mark is as wide as the glyph, both fill the
same slot, both grow when a card asks for 22 — and the unknown host is line
art, which is what stops the badge creeping back.
**A mark nobody can read is decoration, and for half a day these were.**
`HostIcon` set `.accessibilityHidden(true)` on both branches and carried no
tooltip, and nothing in the app named the operating system in words
anywhere — `host.os` appeared at exactly three places, all of them drawing
the icon. So a user meeting Kali's or CentOS's mark at a row's size had a
coloured tile and no way to find out what it meant, and a user on VoiceOver
had nothing at all. Hiding it was **right** while it was a fallback glyph
and wrong the moment it carried which operating system a machine runs; this
project had already written the rule down for itself — every icon-only
button gets a label, seventeen of them fixed in one pass — and it was
broken the same day the marks shipped.
It says `Host.osLabel` now, in three places that cannot drift because there
is one rule: the tooltip, the accessibility label and an **OS** row in the
inspector. With nothing known it stays decoration rather than announcing
"unknown" over the host's own name on every row — but the inspector row is
drawn even then, because a dash there is what explains the generic icon
beside the name.
**`OSRelease.name` was deleted for having no caller and restored to be
that caller**, which is worth recording rather than tidying away: the
deletion was right on the evidence of the morning, and `osName` is stored
beside `os` rather than derived from it because nothing here has a table of
distributions. "Ubuntu 22.04.3 LTS" cannot be made from "ubuntu", and
"Opensuse-leap" made from "opensuse-leap" would be worse than the id.
`window-check.sh` asserts the row is on screen, since a rule proves what
the string is and nothing else proves it is drawn.
Judged at **16pt in a real window**, not on the contact sheet: twelve hosts
across the distributions, with two controls that must stay plain — one never
asked and one whose `ID` nobody has drawn. A letter already taken gets two,
so two distributions are never one letter in two shades of a colour.
**Three measurements, because all three could have been assumed wrong.**
`NSImage(contentsOf:)` **does** read an SVG — `_NSSVGImageRep`, checked with
a real file — so the README's promise of svg/pdf/png in that order holds
rather than being a guess about ImageIO. XcodeGen **walks that folder and
adds each file individually**, so they land at the **top** of
`Contents/Resources`, which is exactly where
`url(forResource:withExtension:)` looks; added as a folder reference instead
they would be a directory down and nothing would be found. And a mark
dropped in really is found: proven by building with one in place and reading
it back out of the bundle.
**And proven on screen, which is the half a lookup cannot reach.** A mark
was bundled, a scratch store seeded with three hosts — one whose `os` names
it, one never asked, one asked with nothing bundled — and the window
photographed in both layouts: the marked host draws the artwork in the row,
the card and the sidebar, and both controls draw the plain glyph. The mark
was made **two-coloured on purpose**, and that is the assertion: a tinted or
template image would come back monochrome, and the inner square survives, so
it is drawn as somebody's artwork rather than as a glyph. The fallback sits
in the same box beside it, which is what the sizing is for.
**Getting that picture cost the trap worth writing down.** The first run
addressed the app as `process "Shellhand"` — and another copy was open, so
the name was ambiguous, the wrong window came forward, and
`screencapture -R` photographed **the user's real host list**. It passed its
own frontmost check, because the frontmost process really was named
Shellhand. `window-check.sh` refuses to run beside another copy for exactly
this reason; a one-off probe written beside it had no such guard. The cure
is to address by **`unix id`** — `first application process whose unix id is
<pid>` — and to compare the frontmost process's **unix id**, not its name,
before and after the capture. A name is not an identity when the thing you
are driving is a second copy of the thing already running.
**The guard for all of that is the folder's own `README.md`, which ships on
purpose.** Every other test here is pure, so all of them would go on passing
if the folder stopped reaching the bundle altogether — a dropped-in mark
would never be found, and the only symptom is the generic glyph, which is
also what a correct miss looks like. Nothing else could tell those two
apart. Checked the way round that matters: with the README moved out,
`theFolderIsBundled` fails and the other five pass. **Don't exclude it**
without replacing the guard.
**Once a day per host, which is `Host.shouldAskOS`.** Neither obvious
answer is right. Asking **once ever** — what shipped first — left a machine
rebuilt onto another distribution claiming what it used to be, with nothing
anywhere able to correct it, not the editor and not a reconnect. Asking on
**every connect** doubles the logins this app makes to somebody's machines,
for an icon. A day bounds the staleness and the cost together and needs no
button for anybody to find.
**`osSeen` records the asking, not the answering, and that is the whole
trick.** A host that cannot say — one taking only a password, a BSD with no
such file, a container with no sftp subsystem — has an empty `os` for ever,
so a schedule keyed on the answer would open a connection on every single
connect, for ever, for an icon it was never going to get. `learnOS` stamps
it whether or not the host answered.
**The first version of the rule had exactly that bug and a test caught it.**
It read `os.isEmpty || now - osSeen >= every`, because an empty `os` looks
like the obvious first condition — and that disjunct undoes the entire
mechanism. Never-asked is already covered without it: `osSeen` is 0 then,
which is further in the past than any interval. The stamp alone decides.
**A switch in Settings ▸ General stops the asking, and it outranks the
schedule.** `Host.askingSetting`, read through `Host.asks`, where nothing
stored means on. It is a required argument of `shouldAskOS`, so no caller
can ask without consulting it, and off means no host is due — not even
one never asked. Turning it off keeps the marks already learned. Asking
is a second login, quiet and promptless, and on a machine with login
alerts or a session recorder somebody sees it. **On by default was the
user's call**: every copy since 0.0.12 has asked, the marks are what the
README leads with, and the caption says plainly what it does for whoever
goes looking. Off was weighed for the launch — an ssh client logging in to
somebody's servers unasked is what a Hacker News thread picks at — and
cost the marks for nearly everybody. Checked the way round: with `allowed`
taken out of the rule, only the switched-off test fails.
Adding the field took the documented **three** edits again — model,
migration **v9**, and the hand-written row mapping — and the round trip
asserts the stamp as well as the answer, since nothing else would notice a
stamp that failed to persist. Everything about
it fails quietly and all the failures are ordinary: a host that only takes a
password cannot be reached this way at all, since `connect` fixes
`BatchMode=yes`; a BSD or a macOS has no such file; a container may have no
sftp subsystem. The cost of failing is a generic icon, which is already what
most hosts show.
**The wiring itself had no test, and that is the gap this project keeps
finding one layer up.** The read is held against OpenSSH's own server, the
parsing has eleven checks, the field round-trips through the store and the
schedule is checked to the hour — and `Core.osOf`, which connects, reads
and parses in one breath, had nothing, because testing it means connecting
to something. `Tests/LearnOSTests.swift` connects to macOS's own `sshd` and
proves the whole path: a host really does say what it is, and the id and
the name come back whole. Nothing had shown that before.
It cost two seams, and both follow one this app already has rather than
inventing anything: `osOf` takes a `path` the way `sshConfigHosts` does,
and `fixed` settings the way `connect` does.
**Even the refusal passes `fixed`, and that is not fussiness.** ssh reads
`~/.ssh/config` **before** it connects, so a test connecting to a port
nothing answers would still take whatever is written there — a `Host *`
with a `ProxyCommand` would run somebody's program on the way to a
connection that was never going to succeed. The first version of that test
left it out. Nothing in this suite connects without it, refusals included.
`sessions.open` has **one** caller, so wiring this into `connect(_:)` covers
every way of connecting — Return in the list, two clicks, ⌘↩, the
inspector, Quick Connect, a grid card — rather than the one that was being
looked at.
**The fallback has to be sized, and nearly was not.** The grid card drew its
glyph with `.font(.title3)`; replacing that with a `HostIcon` that only
*framed* the symbol would have made the card's icon **smaller** than before,
and a 22pt mark beside a body-sized glyph on the next card is exactly the
inconsistency the box is meant to prevent. Both branches draw into the same
box.
It cost `SFTPClient.contents(of:limit:)`, a bounded read into memory — a
different path through the protocol from `download`, with no local file, no
progress and a stop condition of its own, so it is held against OpenSSH's
own server rather than reasoned about. The limit is not decoration: the path
is one this app chose but the file behind it is on somebody else's machine
and nothing promises it is small. Adding `os` to `Host` took the documented
**three** edits — the model, migration **v8**, and the hand-written GRDB
`init(row:)` and `encode(to:)` — and the real store's timestamp is unchanged
across the run that proves it.
