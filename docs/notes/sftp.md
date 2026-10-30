# SFTP: how its rules were found

Moved here word for word from `CLAUDE.md`, which keeps each rule in a line or
three and links to the story it came from. They stand in the order they stood
there, so "above" and "below" mean in this file, unless a story names a rule
that stayed in `CLAUDE.md`.

## The scripted server

**The SFTP conversation is checked against a server written in Swift, in
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

## The hang that roamed

**Both suites that reach that server carry a one-minute time limit, and an
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

## The request deadline

**An SFTP request has a deadline now, and the app needed one more than the
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

## The stall: a reproducer

**The stall has a reproducer now: about one conversation in 2,500.**
`Tests/SFTPStallHunt.swift` ran the minimal conversation 20,000 times with
16 in flight and a five-second deadline on each: roughly six stalls in
seven seconds, where a suite run bought one sighting every few runs.
**It is gone** — deleted in `cdf1317`, the commit that explained the stall,
and replaced by `Tests/SFTPChurnTests.swift`, which runs the same
conversations as a guard rather than a hunt. This file went on telling
people to enable a file that no longer existed; recover it from that commit
if a hunt is ever wanted again.
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

## The stall: a flawed test

**The descriptor-reuse theory was tested and the test was flawed. Read this
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

## The stall: explained

**The stall is explained: it was this harness, not the engine.**
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

## The real server

**The SFTP conversation is held against OpenSSH's own server too**, in
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

## Empty files

**An empty file could not be carried, in every release up to 0.0.3.**
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

## Empty folders

**An empty folder could not be carried down either, in every release up to
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

## Symlinks

**A symlink is carried as a symlink now; the two directions used to disagree
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

## Testing the file panes

**`Model/Files.swift`'s orchestration is testable because a local pane needs
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

## One open or two

**`FilePlace.opens` exists so that one open can be told from two.** The
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

## Closing the window

**The SFTP window closes its sessions now, and for weeks it did not.**
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

## Replacing

**Carrying a file onto one already there asks first.** It used to destroy
it silently, three ways: a download's `FileManager.createFile` truncates, a
copy between two local panes removed the destination outright, and an
upload's open-for-write truncates on the server. A fourth went the other
way — a drop from Finder onto an existing name did nothing at all, because
`copyItem` throws there and the `try?` swallowed it. None of the four said
anything, and none could be undone.
**That `try?` outlived the fix by months, and is gone now.** The replace
question stopped the clash, which is what the fourth case was about — but
the `try?` itself stayed, so every *other* way a local copy can fail went on
being swallowed: no permission on the destination, a full disk, the source
gone between the drop and the copy. Nothing was filed, nothing was said, and
the pane redrew without the file, which reads as a drop nobody asked for.
**What makes it plainly wrong rather than a judgement call is that the pane
beside it already did it properly**: `copyLocally`, forty lines down, caught
a refused `copyItem` and filed a failed transfer. One operation, two
answers to failure. Both go through `copyOnThisDisk` now — two copies of a
decision is how they drifted, exactly as two copies of a write loop let the
harness keep a bug the engine had already had fixed.
The remove before the copy stays a `try?` on purpose: the replace question
has been answered by the time anything reaches there, and a remove that
fails because there was nothing to remove is not a failure — one that fails
for a real reason surfaces as the copy failing a line later.
Found by sweeping every `try?` in the app, which is the same habit that
turned up the upload `mkdir`; **44 of them, and this was the one that
mattered.** (That 44 counted *lines mentioning* `try?`, prose included —
there are 42 real ones today against 6 comments talking about them. Count
the code, not the grep, before reading anything into the number moving.) Pinned with the destination made unwritable, which is how a disk
actually refuses, and with a control that an ordinary drop still lands
quietly — a transfer row for an instant local copy would be noise.
**One other was weighed and deliberately left, so the next sweep need not
do it again.** `HostStore.preview(of:)` swallows a failed
`Core.preview(db:host:)` into an empty `HostPreview`, and the view draws an
empty one as *"Working it out…"* — so a failure is indistinguishable from
still loading, for ever. That reads like the same bug, and it is not.
`Core.preview` can only throw from `store(db).snapshot()`, which is the
identical call `refresh()` makes; `refresh` catches it into `lastError` and
`ContentView` puts it up as a **modal alert**. So the condition already has
a louder voice than a second report would be, and the only gap is the window
between a `refresh` that worked and a `preview` that did not — which the
watcher closes at the next external change. Reporting here would be a second
alarm for a fire already ringing. **Left on purpose; the spinner is the
symptom, the alert is the message.**

## A pane's places

**A file pane's derived values live in `Model/Places.swift`**, because a
`FilePlace` only reaches its states by connecting to something: asking "what
does a pane pointed nowhere call itself" would otherwise mean opening an
SFTP session to find out. `FilePlace` and `ReplaceQuestion` delegate.
`isLocal` is the one worth knowing about. It reads like a label and is not:
`FilesModel` hands it to `Replacing.clashes` as `caseInsensitive`, because
this disk is and a server's usually is not. And an **unpointed** pane is not
local — the same `chosen` flag that stops it calling itself "This Mac" —
so the three states are pinned rather than the two that are obvious.

## Opened once

A file session is opened **once** per pane, guarded by a flag set before the
first await. Checking only whether the session exists let two opens through
together: the second one's walk to the home directory landed after the first
had navigated away, so a download went to the wrong folder with the job
reporting success. The `.task` that used to re-run on every tab switch is a
window's now and runs once, but the guard stays — it is cheap, and what it
protects against is a race rather than a particular way of re-entering.

## A window, one at a time

**SFTP is a window, and one at a time.** A window because it can sit beside
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
