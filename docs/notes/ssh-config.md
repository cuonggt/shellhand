# ssh's own config: how its rules were found

Moved here word for word from `CLAUDE.md`, which keeps each rule in a line or
three and links to the story it came from. Where a story says "above" or
"below", it names a rule that stayed in `CLAUDE.md`.

## ssh's own config

**The names in ssh's own config reach the resolver now, and for every
release up to this one they did not.** `Resolver.withAliases` has always
known what to do with them — a host whose own name matches a config entry
for the **same machine** is reached by that name, so the block written under
it applies, while one whose name goes to a **different** machine is reported
instead, since those settings are not this host's to take and a
`ForwardAgent` written for them would hand this machine your agent.
`SSHArgs` has always spelled the first, pinning the address with
`HostName=` so the alias decides only which settings apply and never which
machine is reached. `HostDetailView` has always drawn the second, a yellow
warning naming the entry. **Nothing ever handed the resolver any names**, so
`Core` built `Resolver(groups:hosts:)` and stopped: the warning could not
appear and the alias was always empty. Every piece had tests; what had none
was them being connected. This is `FilesModel.close()` again — a documented
capability with nothing calling it reads as working code.
**How it was found is worth more than the fix.** The dead-declaration sweep
this file prescribes counts a name's mentions *"anywhere in the app or the
suite"* — so a function only the **suite** calls reads as live, and
`withAliases`, `withProxies` and `Store.replaceAll` all sat in that blind
spot. The variant that finds them is narrower: declared under `Shellhand/`,
mentioned in `Tests/`, and nowhere else in `Shellhand/`. Run **both**. The
narrow one has a blind spot of its own, being token-based: a generic name is
drowned by ordinary English in the sources, which is how it missed
`OSRelease.name(from:)` — still uncalled, and mine.
**A `throws` that cannot throw is the same lie in a smaller place, and
`SSHConfigFile.parse` was one.** Nothing in it throws — an unreadable file
is an empty list, which is the right answer for having no config at all,
and an `Include` that loops is cut off by the depth — but the keyword made
`read` throw too, and three callers then wrote `try` or `try?` and read as
though they were handling a failure that could not happen. Dropped, with
the callers. It is the `async` wrapper's lesson in another key: the
difference between handling failure and looking as if you do.
`Store.replaceAll` went at the same time, superseded by `apply(_ plan:)`
and reachable only from its own test — the fourth round of leftovers, found
by the narrow sweep rather than the documented one.
**`configProxy` was the other half, and it is wired now too.** It had the
same shape with a different symptom: the resolver worked out what the config
would send a host through on **every resolve** and nothing read the answer,
so the inspector said *"Jump host: —"* for a host ssh was quietly taking
through a bastion. Not a broken connection — ssh applies its own config — but
a row stating the opposite of what happens, which is worse than a row saying
nothing. Both answers now come from **one parse**: `Core` holds the blocks
rather than a finished list, because `Host 10.0.1.*` cannot be answered
without knowing the address being asked about.
**A `ProxyCommand` gets a row of its own, and that is the point.** It
routes a connection too, but it is a command line and not a jump host —
`ssh -W %h:%p gateway`, or something that is not ssh at all — so putting
one in a field labelled "Jump host" would be a different wrong answer
rather than a right one. For a while it was reported nowhere and such a
host read as going straight there; now `Effective.configProxyCommand`
carries it and the inspector shows it **only when there is one**, since a
dash for every host would be a row of noise. `SSHConfigFile.route` answers
both from **one** walk of the blocks, because this is asked once per host
per snapshot and the measurement that made `glob` a scan says not to walk
them twice. `ProxyJump` wins where both are given, which is ssh's own rule
— *"this option takes precedence over the ProxyCommand directive if both
are specified"* — so a route never carries both and nothing above has to
know the precedence.
**A config block is only reached by name when ssh is handed that name**, and
ssh is handed the **address** unless the alias was adopted — which happens
only where the config's entry points at this same machine. So `Host web`
with no `HostName` does not reach a host of yours called `web` at another
address: the entry is reported as `aliasElsewhere` and its `ProxyJump` never
applies. A test asserting otherwise failed, correctly, and is kept with the
`HostName` that makes it true.
**And it was 1,268 times the cost of everything else, which is the part
worth remembering.** `glob` was a full dynamic-programming matrix —
correct, and allocating a nested array of (pattern × name) `Bool`s on every
pattern tried against every name. Nothing noticed for as long as its only
caller was an import somebody asks for; the moment the resolver began
asking what the config routes **each host** through, it became a walk over
every block for every host. A 500-host list against a 400-block config took
**5.1 seconds a snapshot**, and a snapshot happens on every refresh.
**Isolated by measurement rather than reasoning**: with the proxy lookup
taken back out the same list resolved in **4ms**, so the table was the whole
of it and nothing else in the resolve was implicated. A scan with one
backtrack point does the same job in **159ms** — 32× — and the shape is now
linear rather than quadratic in the pattern.
**The same read turned a latent config bug into a window that would not
open, and that is the second half of the same story.** `parse` capped
`Include` recursion at depth 8 — which terminates a cycle and does nothing
about its **width**. `Include conf.d/*` written inside a file that is
itself in `conf.d` is a plausible copy-paste, and it branches by however
many files are in that directory at every level: measured with the cap
alone, 29ms for two files, 346ms for three, 2.4 seconds for four, and
**48 seconds for six**. A real `conf.d` holds ten. That was survivable
while the only caller was an import somebody asks for; it is a startup hang
once the resolver reads the config.
**Each file is read once per parse now**, settled through
`resolvingSymlinksInPath` so two spellings are one file. That is not weaker
than reading it twice, which is the claim the fix rests on: a setting keeps
its **first** value, so a second copy of the same blocks could never win
anything, and the names it declares are the same names. 48 seconds became
about a millisecond.
**Three of the four tests pass without the fix**, and that is the point of
the one that does not: a config that includes itself and a pair that
include each other are both handled by the cap, so they are not the guard.
Only the branching one is — a cap is about depth and the bug is about
width, and a test for the shape you already handle proves nothing about the
shape you do not.
**The order of work is the lesson, not the algorithm.** `glob` had six
tests and **none of them backtracked**, which is exactly where a scan goes
wrong: a `*` has to give back what it took when what follows fails to line
up further along. So the hard cases went in **first**, against the old
matrix, where they all passed — that made them an oracle for the
replacement rather than a description of it. Writing them afterwards would
have pinned whatever the new code happened to do.
`Tests/ResolveCostTests.swift` is the guard, and deliberately far larger
than anybody's list in both directions: the question is whether the shape
is wrong, and a realistic list answers that too quickly to tell. It costs
about two seconds of the run.
**The row's own decision lives in `Effective.jumpHost`, not the view**, for
the reason every rule here does: a decision inside `HostDetailView` could
only be checked by driving the view, which this app cannot be. The resolver
tests prove the value is worked out; that one proves the inspector prefers
the host's own and falls back to the config's.
**Cached, because a resolver is built far more often than it looks** — every
snapshot, every argv, and every preview the editor asks for as a group is
picked. Parsing a config and every file it `Include`s on each of those is a
filesystem walk nobody asked for, so the read is kept against the file's
path, modification date and size. A file that is not there caches as "no
names" and re-reads the moment one appears.
**It cost a third redirect, and `TestRun` is where all three now live.** The
store goes to scratch for a run so the suite never edits the real list, and
this app's own config does too because its ssh options become every
connection's. Ssh's config had to join them the moment these names reached
the resolver: a run reading the real file would take whatever somebody
happens to have written there into every host the suite resolves, so a
`Host web` of theirs would quietly change what a test about a host called
`web` sees. The decision moved **into `Core`** because `Core` acts on two of
them and must not reach up into `App/`; `LaunchOptions` reads it from there,
so there is one copy rather than two to drift.
Checked the way round that matters: with the one line taken back out, the
two wiring tests fail on three expectations between them, and **the control
still passes** — a host the config does not name, reached exactly as before.
That control is the point, since a change that handed the resolver names
unconditionally would satisfy the other two and break every host nobody has
written a config entry for.
**One link the suite cannot reach, and it is the one that was broken
before.** Every test here runs with the path redirected, so all of them
would pass if the *unredirected* branch were changed to point anywhere —
and the feature would be inert again in exactly the way it just was.
Proving it needs reading the user's own `~/.ssh/config`, which is the one
thing this suite promises not to do. What is pinned instead is that the
other branch still names that file, absolute and ending `/.ssh/config`.
**If you touch that branch, prove it by hand.**
