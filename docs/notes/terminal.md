# The terminal: how its rules were found

Moved here word for word from `CLAUDE.md`, which keeps each rule in a line or
three and links to the story it came from. They stand in the order they stood
there, so "above" and "below" mean in this file, unless a story names a rule
that stayed in `CLAUDE.md`.

## The palette picker

**The palette is chosen from the inspector, not only from the editor.**
Asked for by the user: a quick way to pick a terminal's colours. It is the
same picker the editor's Advanced tab has, down to the sentence labelling
"inherit" — `Effective.inheritedPalette`, now a rule in `Model/` that both
read, because two copies of a sentence drift.
**It opens a dialog rather than dropping a menu down**, asked for after
Termius and right for the reason that picture makes obvious: **the name of
a palette says almost nothing.** "Gruvbox Dark" and "Tomorrow Night" are
both dark and neither name says which is warm. `TerminalMiniature` draws a
few bars in a palette's own colours, so the question is answered by looking.
**It replaced `PaletteSwatch`, the chart of all sixteen ANSI colours that
Settings used to show.** The chart answers "what is in this palette", which
is a fair question and not the one anybody is asking: what you want when
choosing is what a terminal will look like. Both existed for a few hours;
the chart is deleted, so there is one way a palette is drawn in this app.
**The one view whose whole job is to be looked at was the one nothing
could look at**, until `Tests/TerminalMiniatureTests.swift`. A dialog cannot be
opened from a script here — `click at` is inert — so `ImageRenderer` draws
the miniature into a bitmap instead and the pixels are read: every shipped
palette must appear on its own background, in its own green, in its own
text colour, and **two palettes must not draw the same picture**, which is
the one that would catch a swatch ignoring its argument.
**Compare like with like, not against the palette's own bytes.**
`ImageRenderer` puts everything through a colour-space conversion, so
Nord's `#2E3440` lands as `#363E4A` — plainly the same colour and not
equal. The first version asserted on the raw values and failed on every
palette. Rather than invent a tolerance, the expected colour is rendered
the same way and the match is exact again.
**Neither a `List` nor a `ScrollView` can be rendered this way** — a `List`
comes out as a "cannot render" sign and a `ScrollView` comes out blank — so
`PalettePicker.rows` is deliberately not private, the same seam
`TerminalSession.watch()` is left open for. The rows are a stack rather
than a `List` for a reason of their own: they carry their own selected
background, because a `List`'s selection would tint the very swatch being
judged.
**Choosing applies at once and the sheet stays open**, so two palettes can
be compared on the terminal behind rather than from memory — which is also
why the footer says Done and not Save, and why Escape leaves nothing
undone. `DialogSize.medium`, which the conventions give for a plain list.
**One control in a grid of facts**, which is a deliberate exception rather
than a drift: a palette is the setting people change most and the only one
whose effect they want to see at once, on the tab already open. Choosing
saves the host, and a save is what repaints the sessions already running —
`Sessions.repaint(from:)` on the host list changing, built for a group's
palette reaching the tabs beneath it. The host is read again from the
snapshot before saving, for the reason `learnOS` does it.

## The inset

**The terminal's text is inset 8pt and its background still runs edge to
edge.** Asked for by the user, after Termius, and the second half of that
sentence is the requirement: *"the terminal section should be as before,
just some padding inside"*. Three modifiers in `TerminalPane`, each doing a
job: `padding` insets the terminal, a `frame` with `maxWidth`/`maxHeight`
infinity and `.topLeading` makes what holds it fill the pane, and
`background` paints that whole area in the session's colour. Top-leading
because the terminal rounds to whole cells, and centred the leftover would
be split either side and the text would sit off its own inset.
**A container `NSView` was the first attempt and it is the wrong shape.**
A plain wrapper takes everything offered, so it painted over the **tab
strip** — the terminal does not fill the pane, it sizes itself to whole
cells, and that has to stay true. SwiftTerm offers nothing of its own here:
its only `padding` is a glyph-placement policy in fractions of a cell, for
fallback fonts.
**The colour comes from the palette, not from the view.**
`nativeBackgroundColor` is the obvious source and is wrong: read back it
answers **white** for a terminal that is plainly drawing black, which put a
white ring around the first working version. `TerminalSession.background`
is set in `apply(theme:)` from the palette this app asked for, and is black
for the **System** palette, which installs no colours of ours at all.
**Every step of that was found by photographing it, not by reading it.**
Sampling the pixels either side of the edge is what showed the ring was
white; painting it red for one build is what proved the modifier worked and
moved the suspicion to the colour. A screenshot at a glance would have
passed all three wrong versions — the black ring, the covered strip and the
white ring are each invisible until measured or compared against before.

## Option

**Option types characters unless Settings says Meta.** SwiftTerm's
`optionAsMetaKey` defaults to `true` and nothing here set it, so in every
release up to 0.0.11 ⌥ plus any key sent Esc and the bare key. On the many
layouts that put `@`, `|`, `{}` or `[]` on Option, those could not be typed
into a session at all. Found by reading SwiftTerm's `keyDown`, not from a
report: on a US keyboard nothing looks wrong. Off is the default, as in
Terminal.app, iTerm2 and Ghostty — the user's call — and Settings ▸
Terminal ▸ Keyboard turns Meta on.
**An open session follows the switch through
`UserDefaults.didChangeNotification`, not a notice Settings posts.** The
switch writing its key is then the whole of the wiring, with no second step
to forget — `confirmCloseLiveSession`, below, is what forgetting looked
like. It hears every other write too, so a session acts only when the
setting differs from the one it last took; otherwise a window saving its
frame would undo SwiftTerm's own ⌥⌘O, which flips one terminal. Both sides
name the key through `TerminalSession.optionAsMetaSetting`.
The tests post that notification rather than write the key, since the test
host's defaults are the user's own, and ask the terminal both ways round:
SwiftTerm's default would pass one of them.

## The font

**The terminal's font is a choice in Settings ▸ Terminal**: SF Mono — the
system's own monospaced face, and what nothing stored means — or any
monospaced family installed, a Nerd Font for a prompt that draws glyphs
included. `TerminalFont` decides, out of the session and the pane: what
the picker offers (monospaced families in reading order, the system's
hidden dot-families and a second SF Mono left out), and what a stored name
comes to, which is **SF Mono for a family not installed or not
monospaced** — the setting travels with a migrated Mac, and SwiftTerm lays
text on a grid of one cell width. The tests ask real fonts, since Menlo is
monospaced and Helvetica is not on every Mac.
Open sessions follow through the **same** defaults observer as the Option
key, widened to `takeSettings`, and keep the size they are at: ⌘+ may have
put a tab somewhere other than Settings' size, and a new font is no reason
to undo that. **Actual Size kept SwiftTerm's SF Mono until now** — harmless
while nothing else existed, and it would have thrown the choice away on
⌘0 — so it is Settings' size in the session's own family now. The list is
worked out once a run, so a font installed while the app is open is
offered from the next launch. Checked the way round that matters: with the
font taken out of `takeSettings`, only the test for following Settings
fails.

## Clear Scrollback

**Clear Scrollback is ⌥⌘K, in the Terminal menu** — Terminal.app's own
key for it. ⌘K, which clears in Terminal.app, iTerm2 and Ghostty, stays
Quick Connect's: the user's call. It drops every line above the screen and
keeps the screen, the vim in front of it included.
**It shrinks the history to nothing and back**, through the view's public
`changeScrollback`, because `Terminal.clearScrollback` is out of reach — the
view keeps its terminal internal. Feeding it `ESC [3J`, which is what a
shell's `clear` sends, was the obvious alternative and is worse twice over:
it acts on the buffer in front only, so nothing at all while vim has the
alternate screen, and it goes through the parser, where it could land in
the middle of an escape sequence the far end is half way through sending.
**Putting the size back needs the size**, and SwiftTerm will not say what
it is, so `TerminalSession.scrollback` now sets it at creation: 500, its
own default, so nothing changed by being named. The test fills a terminal
fed by hand, clears it, and feeds it again — checked the way round that
matters, with the size left at nothing only the "kept again" half fails.
**It is 10,000 now, and raising it was not the one-line change this note
once called it** — the watchdog had to stop reading the whole history
first; see its settling, further down.

## The local shell

**A local shell starts at home, and it took a user to notice.** A forked
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

## Blank, not empty

**A terminal that has heard nothing does not come back empty, and reading it
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

## Wrapped questions

**A host-key question that wrapped was not seen at all**, in every release
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

## Answered questions

**Accepting a new host key could bring the question straight back**, in
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

## The scrollback

**The scrollback is 10,000 lines, and what held it at 500 was the
watchdog, not memory.** Measured on a session fed by hand, at 80 and 200
columns, in a Debug build compiled with `-O`. Plain Debug overstated what
ships four to forty times, and a Release test host would start Sparkle
against the real preferences, since only `#if DEBUG` gates it — so this is
the stand-in, and an upper bound, keeping SwiftTerm's debug-only checks:

    lines     memory     watchdog look   search, no match   rewrap
    500       0.6–1MB    5–12ms          5–11ms             ~1ms
    10,000    8.5–16MB   90–214ms        83–210ms           10–14ms
    100,000   72–141MB   0.9–2.1s        0.8–2.1s           98–177ms

A line costs about 8 bytes a column. **The look was the problem**: every
200ms, on the main thread, for every ssh session, `screen` turned the
whole buffer into one string and `HostKey` split it into rows to find the
last few — so even at 500 lines a session cost 2.5–6% of the main thread,
idle or not. Find runs on Return, not on every keystroke, which is what
makes a tenth of a second at 10,000 lines acceptable.
**SwiftTerm 1.99 gives the app no part of the buffer.** The view keeps its
`Terminal` internal — `var terminal: Terminal!`, no `getTerminal()` — and
every public read on the view is the whole buffer. `Terminal` does publish
`getLine(row:)`, `bufferLine(atRow:)` and `getText(start:end:)`, and a
bounded read built on them was proposed and approved before anyone found
that nothing could reach them: **check the view, not the class, before
planning on SwiftTerm's API.** `getLine` would have been wrong anyway — it
counts from where the view is *scrolled*, so it reads old rows whenever
somebody has scrolled back.
**So the screen is read only while it can matter.**
`SessionProgress.watches` says yes while connecting, while a question is
up, and for `settling`, two minutes, after the session last came through;
then no. Every connect is a fresh session, so the history is short
whenever it is read. **Stopping at `.connected` would have broken jump
chains**: an answered question on screen reads as being through, so the
next hop asks after `.connected`, and so does a host behind a bastion
that prints a banner first. The two minutes are for those.
**What it gives up, decided rather than drifted into:** a host-key
question from something run inside a settled session — an `ssh` typed
there, `git` over ssh — is answered in the terminal, as in Terminal.app,
where this app's dialog used to pop over it. No test had pinned the old
behaviour; `lateQuestionIsLeft` pins the new one. `looks` counts the reads
beside `ticks`, so "the watchdog ran and read nothing" is a fact a test
can see. Checked the way round that matters, three ways: with the loop's
guard taken out, only the settled and late-question tests fail; with no
settling window, the jump chain's next hop, the just-through control and
the rule's own timing fail; with the scrollback back at 500, only the
long-history test fails, its screen starting at line 473.
