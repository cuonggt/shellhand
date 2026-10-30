# Cuts and sweeps: how their rules were found

Moved here word for word from `CLAUDE.md`, which keeps each rule in a line or
three and links to the story it came from. They stand in the order they stood
there, so "above" and "below" mean in this file, unless a story names a rule
that stayed in `CLAUDE.md`.

## The cut's leftovers

**The cut left two engines behind with nothing calling them, and they are
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

## Sweeps

**A sweep for declarations nothing calls found four more, and `checkPort`
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

## The published history

**The published history is one commit, and what came before it is in a
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
