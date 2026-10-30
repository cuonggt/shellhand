# Releases: how their rules were found

Moved here word for word from `CLAUDE.md`, which keeps each rule in a line or
three and links to the story it came from. They stand in the order they stood
there, so "above" and "below" mean in this file, unless a story names a rule
that stayed in `CLAUDE.md`. The last section is every release's own record,
from the first that proved an update end to end.

## The CDN

**The feed is served through a CDN that caches it for five minutes, so
pushing the appcast does not change what Sparkle sees.**
`raw.githubusercontent.com` answers with `cache-control: max-age=300`, so
for up to five minutes afterwards the live feed goes on naming the
**previous** version. Measured on 0.0.8: the appcast was pushed, `main`
held it, and the feed still offered 0.0.7 at `source-age: 267`; it turned
over about three minutes later, so the window is real but short. Checked
straight after publishing that reads exactly like a push that did not
land, and the next move looks like pushing again. Ask what `main` holds
instead — the blob sha through the API, against
`git rev-parse HEAD:appcast.xml` — which is the same question with no
cache in front of it. A cache-busting query string would dodge it and
prove nothing, since Sparkle asks the plain URL. Harmless in itself: an
app checking inside that window hears on its next check.
**Two corrections from 0.0.9, both of which had been read the wrong way.**
The **tap's cask is behind the same cache** — served from
`raw.githubusercontent.com` too — and on 0.0.8 it looked instant, which
read as casks being exempt. They are not. The rule is **per path, and only
for a path something fetched recently**: on 0.0.8 nothing had asked for the
cask before the push, so there was nothing cached to serve; on 0.0.9 the
previous release's own verification had warmed it, and it served 0.0.8 for
minutes after 0.0.9 was pushed. So a verification that passes straight
after a push may only mean that nobody had looked before — which is the
weaker claim. Both turned over about 200 seconds after the push on 0.0.9,
measured. **On 0.0.10 both came back at `source-age 0` at once**, which is
the same rule from the other side: nothing had asked for either path for
hours, so there was no stale copy to serve. An instant verification is not
evidence that caching is absent — only that nobody had looked lately.

## The appcast

**The appcast is written from a folder, so the folder has to hold every
version still being offered.** `generate_appcast` does not amend an
appcast; it rewrites it from the DMGs it is given, so a folder holding only
the new one produces a feed that has forgotten every earlier release. The
DMGs live in the GitHub releases, so the script fetches the past ones back
before generating. One `--download-url-prefix` covers the whole folder while
GitHub puts each version behind a tag of its own, which is why the enclosure
URLs are rewritten per version straight afterwards, from the version in each
filename.
**It also prunes, and 0.0.4 was the first release with enough history to
show it.** `generate_appcast` retired `Shellhand-0.0.1.dmg` into
`build/updates/old_updates` by itself — nothing here passes
`--maximum-versions` — so the feed carries the most recent few rather than
every release ever made, and 0.0.4's appcast lists three items, not four.
That is harmless: Sparkle offers the newest item, an app never needs a feed
entry for the version it is already on, and the retired DMG is still served
from its own GitHub release. Worth knowing before it looks like a version
has gone missing.
**And it orders and prunes by the integer build, not by the version
string** — which 0.0.10 was the first release able to show, since `0.0.10`
sorts **below** `0.0.9` as text. Had anything compared the short version as
a string the feed would have offered the wrong release, and an app on 0.0.9
would never have seen anything newer. It does not: the feed came out builds
10, 9, 8, newest first, with 0.0.7 retired and 0.0.8 kept. Checked rather
than reasoned, because the appcast step is skipped in a dry run and this was
the one release where a string comparison could have surfaced.

## notarytool's retries

**notarytool words a timed-out upload more than one way, and matching one of
them is as good as no retry at all.** The retry loop tested for the literal
string `timed out`. 0.0.4's run printed *"The request timed out"* and
recovered, which looked like proof the loop worked; 0.0.5's printed
`Error: HTTPClientError.connectTimeout` from the same flapping route, which
contains no such phrase, so it gave up after **one** attempt and threw a
whole signed build away. It matches a transport pattern now
(`timed out|timeout|httpclienterror|could not connect|connection
(lost|refused|reset)`, case-insensitively) and echoes what notarytool
actually said, so the next wording is visible rather than silent. A rejection
from Apple is about the thing being shipped and reads nothing like these, so
widening this does not risk retrying a real refusal. The second run then went
through on the first attempt, which is what a flapping route looks like.
**0.0.9 is where that widening paid for itself**, and it needed both halves
of it: **six** failed attempts in one run, three per submission, in **two**
wordings — `_kCFStreamErrorDomainKey=4` for the app and
`HTTPClientError.connectTimeout` for the DMG, the second being the exact one
that cost 0.0.5 a signed build. Matching either alone would have thrown this
release away twice. The echo is worth as much as the retry: both wordings are
in the log, so the pattern can be widened again from evidence rather than
from a guess at what Apple might say next.

## Every release

**0.0.1 through 0.0.12, and then 0.1.0 and 0.1.1, are out**, each tagged at
the commit its DMG was built from, with the appcast on `main` and the cask in
`cuonggt/homebrew-tap` — whose clone on this Mac is Homebrew's own, under
`/opt/homebrew/Library/Taps`; see 0.0.12 for what it needs before a cask is
copied in.
The notarytool profile `Shellhand` is stored, the EdDSA key is backed up off
this disk, and release notes live at `docs/release-notes/<version>.md` —
write one per version or the update window comes up blank.

**Updating is proven.** An installed 0.0.1 found 0.0.2 on the live feed,
offered it with the release notes carried inside the appcast, downloaded it,
checked the EdDSA signature and installed it — and what landed verifies,
staples and passes Gatekeeper. 0.0.2 was cut for that purpose and earned it
twice over: it also exposed the delta bug above, which is unreachable on a
first release because there is no earlier version to make a delta against.
An installed 0.0.3 then took 0.0.4 the same way, from the menu item: what
landed is 0.0.4 (4), hardened, secure-timestamped, stapled, accepted by
Gatekeeper and verifying `--deep --strict`, with Sparkle relaunching the app
on a new pid and `brew info` dropping its upgrade arrow once the app matched
the cask. **But nobody was asked**, because this machine carries
`SUAutomaticallyUpdate = 1` while the shipped `Info.plist` sets neither that
key nor `SUEnableAutomaticChecks`. So that run proves the feed, the signature
and the install, and says **nothing** about the dialog a new user meets — the
"offered with the release notes, then installed on a click" half is still
proven only by 0.0.2.
**0.0.6 did it again, unasked and unwatched.** It was published, and minutes
later the installed copy at `/Applications/Shellhand.app` had replaced itself
— bundle mtime 06:34:24, its process started 06:34:26 — reporting 0.0.6 (6),
hardened, carrying the release build's own `Timestamp=27 Oct 2026 at
06:11:12`, `stapler validate` intact and Gatekeeper calling it a *Notarized
Developer ID*. Sparkle will not install an update whose EdDSA signature does
not check out, so that path is proven for 0.0.6 end to end: feed, signature,
download, install, relaunch. `brew list --cask --versions` still says
**0.0.1**, which is `auto_updates true` working as intended rather than a
discrepancy to fix. And **nobody was asked**, again, because this machine
carries `SUAutomaticallyUpdate = 1` — so the dialog a new user meets is
*still* proven only by 0.0.2, and no amount of updating on this Mac will
change that. Put the key aside first or it proves nothing — which was done
for 0.0.8, below.
**0.0.7 had not reached this machine's copy an hour after it went out — and
then it arrived at an hour and a quarter, which killed the explanation.** The
release was published at 10:49:45 on 2026-10-27 and the feed naming it pushed
at 10:50:06. The copy in `/Applications` had been relaunched at 09:02, Sparkle
looked then (`SULastCheckTime` 09:02:46 local), found 0.0.6 current, and —
with no `SUScheduledCheckInterval` set — was taken to be waiting its default
of a day. It was not. At **12:04:42** the bundle replaced itself with 0.0.7
and relaunched on a new pid at 12:04:44: hardened, stapled, Gatekeeper calling
it a *Notarized Developer ID*, carrying 0.0.7's own build timestamp. So 0.0.7
is proven end to end here as well — feed, signature, download, install,
relaunch — and **nobody was asked**, for the third time.
**What was wrong is the model, not the observation**, and this file has
already warned twice about building one from a single sighting. **Then it was
done again, in this very paragraph, within the hour** — which is why the
mistake is left in rather than tidied away. The first version of these lines
read *"Sparkle checks shortly after a launch, since the relaunch at 12:04:44
was followed by a check at 12:04:55"*, and reasoned on to a relaunch somewhere
between 09:02 and 12:04. That is one correlated pair turned into a rule, and
it is **false**: the same copy was quit and relaunched twice that afternoon
and `SULastCheckTime` stayed at 15:56:34 through both. The 12:04:55 check
followed an **update install**, which is not an ordinary launch. Nothing
replaces it — no account of when Sparkle looks is established here, and with
`SUScheduledCheckInterval` unset its documented default of a day is the only
answer anybody has. **Don't predict when a release will reach an installed
copy.** What is safe is the pair of bounds, both now seen on this Mac: a copy
may take one within ten minutes, and a copy that has just checked may not
hear for a day. The consequence is the certainty — an install relaunches the
app under whatever sessions are open — which is why **Check for Updates… is
still not triggered from here**. That is the user's call, and this arrival
shows it can happen without anyone making it.
What 0.0.7 shipped is the host-key fix — a question answered on a quiet
server no longer comes straight back, and a second Accept no longer types
`yes` into the shell — with the descriptor leak into terminals behind it.
**0.0.8 went out seven seconds after that install finished**, published at
12:04:49 at `8c83bb3` — close enough to be worth saying plainly: the copy
took 0.0.7, not 0.0.8, from the feed as it then stood. It leads with the folder
fix — a folder from a host arrived without its empty folders, and an empty
folder arrived as nothing while the transfer reported success — and carries
the two host-key ones behind it, a question wrapped across a narrow window
going unasked and an answered one coming back for an instant. The suite went
448 → 459. Verified before publishing and again after: `stapler validate` and
Gatekeeper on the DMG and on the app inside it, the DMG fetched back from
GitHub hashing to the digest in the cask, every appcast URL answering 200 with
the length the feed claims, all three items' notes byte-identical to their
`docs/release-notes` files, and the signature **reproduced** by re-signing the
DMG — Ed25519 is deterministic, so that is a check and not a second guess.
**And it arrived here nine minutes later**, unasked, which is the fourth time
running. The copy in `/Applications` replaced itself at 12:14:03 and
relaunched at 12:14:05, `SULastCheckTime` 12:14:04, carrying `Timestamp=27 Oct
2026 at 11:59:10` — the same secure timestamp read out of the DMG's own app
before publishing, so it is that build rather than a version string taken on
trust. The feed had turned over about three minutes after the push, and the
copy had it some seven minutes after that. So 0.0.8 is proven end to end as
well: feed, signature, download, install, relaunch. It is the sharpest
arrival yet, and it is what tightened the bound above from an hour to ten
minutes — written the same morning, on one sighting, and already too loose.
**The dialog a new user meets is proven now, on 0.0.8 — and it needed no
release.** Every version's DMG is still on disk, so the experiment is to
`ditto` **0.0.7** from `build/release/0.0.7/` over `/Applications`, put
`SUAutomaticallyUpdate` aside, and let the live feed — already offering 0.0.8
— do the rest. Sparkle's default is to **ask**, so an install that happens at
all has been through the dialog. It was, with the **release notes shown**:
offered, installed on a click, relaunched at 15:56:34 on 2026-10-27 as
0.0.8 (8) carrying `Timestamp=27 Oct 2026 at 11:59:10` — the same secure
timestamp as the app inside the published DMG, so it is that build —
hardened, verifying `--deep --strict`, stapled and accepted by Gatekeeper.
One release now holds the whole path instead of it being split across two:
feed, signature, the notes in the dialog, a click, install, relaunch.
**Nothing was published to do it and the app ended where it started**, which
is what makes it repeatable. The costs are the two to know about: quitting the
app drops any live session it is holding — check `pgrep -P <pid>` first, and
`lsof -a -p`, because `lsof` ORs its selectors without `-a` and will otherwise
list the whole machine's sockets — and borrowing the preference domain has a
trap of its own, noted above.

**0.0.9 carries the two transfer fixes that 0.0.8's folder work turned up**,
published at `bc3f309` and live on every surface — release, feed, cask and
tap. It leads with symlinks: left behind entirely coming down, and going up
turned into a copy of the target's bytes, an empty folder, or nothing at all.
Behind it is the folder whose `mkdir` was refused and said nothing about it.
The suite went 459 → 466. Verified the same way as 0.0.8, before publishing
and again after: `stapler validate` and Gatekeeper on the DMG and on the app
inside it, the DMG fetched back from GitHub hashing to the cask's digest,
every appcast URL answering 200 with the length the feed claims, all three
items' notes byte-identical to their `docs/release-notes` files, and the
signature reproduced by re-signing. **The `mkdir` fix waited a release on
purpose** — one conditional fix is a thin release, and holding it until the
symlink work gave it company made a note about one thing rather than two.

**0.0.10 is the host window's shape rather than a fix**, published at
`87ba111` and live on release, feed, cask and tap. Picking a host no longer
takes the list away: the list stays with the host highlighted, its details
moved to the inspector, and where the pane is **looking** came apart from what
is **selected** — see the `Browsing` note above, and do not put them back
together. The suite went 466 → 479. Verified the way 0.0.8 and 0.0.9 were,
before publishing and again after, with the one addition this release needed:
the feed's ordering, since `0.0.10` sorts below `0.0.9` as a string.
**What it cost to get right is worth more than the feature.** A double-click
to connect went in, was made a `simultaneousGesture` to stop it taking the
click, and came out altogether a day later because it made **every** single
click wait out the system's double-click interval. No probe here could have
seen that — a synthetic click does nothing in this app, proven with a control
— and a user felt it on the first click. Ask for a hand on the mouse when the
question is only answerable by one.

**0.0.11 finished what 0.0.10 started**, published at `3f8e02d` and live on
release, feed, cask and tap. Clicking a host opens the panel on the right, two
clicks connect, a right-click gives the sidebar's own menu acting on the host
clicked rather than the one selected, the arrow keys reach the list in rows or
cards with Return connecting, and a file dropped from Finder that cannot be
copied says so. The suite went 479 → 495. Verified the way the last three
were, and Apple's notary route was flapping again — a credentials check timed
out and answered on retry, and the DMG's submission needed one attempt before
it went through, which is the widened pattern earning its place for the second
release running.
**Every one of those five came from somebody using the app**, not from a test
or a sweep: the layout change shipped in 0.0.10 and the gaps in it showed up
within a day of real use. The double-click alone took three attempts — see
the pane's own note — and two of them were handed over as done before a hand
on the mouse said otherwise. **The suite is 495 checks and it could not have
found any of this.** That is not an argument against the suite; it is the
reminder that what it covers and what a user meets are different sets, and
this release is entirely the second one.

**0.0.12 is the first release that reads your machines and your ssh config,
not only your list**, published at `86b345d` and live on release, feed, cask
and tap. It leads with the marks: a host is drawn with its distribution's own
logo — 30 of them, generated by `tools/osmarks.swift` from the CC0 sources in
`tools/logos/` — learned by reading the host's own `/etc/os-release` over a
connection of its own, and asked again once a day so a rebuilt machine
corrects itself. Then what ssh's own config does to a host, all of it built,
drawn and tested in earlier releases and never handed anything to work with:
the clash warning fires, the jump host row stops saying a host has none while
ssh takes it through a bastion, a `ProxyCommand` gets a row of its own, and a
host named for an entry on the same machine is reached by that name. Behind
those, four fixes — Option types characters, with Meta a switch in Settings;
closing, reconnecting or quitting asks before it drops a live session; an
`Include` that branches back into its own folder no longer holds the welcome
and the import up for a minute; and a local shell opened on a fresh install is
no longer hidden behind the welcome — with the palette picker in the inspector
and the inset terminal beside them. The suite went 495 → 570.
Verified the way 0.0.8 to 0.0.11 were. **Before publishing:** Gatekeeper,
`codesign --deep --strict` and `stapler validate` on the app **inside** the
DMG as well as the one in the build products; the DMG's staple; all three feed
items' notes identical to their `docs/release-notes` files; the 0.0.12 item's
length equal to the DMG's size; and the signature reproduced by re-signing.
**After:** every appcast URL answering 200 at the length the feed claims; the
DMG fetched back from GitHub hashing to the digest in **both** casks, this
repository's and the tap's as GitHub serves it; the feed's blob on `main`
matching the local one through the API; and the release page's notes identical
to the file. Apple's notary route held this time — both submissions went
through on the first attempt — and the CDN in front of the feed had nothing
cached, serving 0.0.12 at `source-age 0`: nobody had asked lately, which is the
0.0.10 rule again.
**Hash the DMG as it streams, not from a saved copy.** The first after-check
deleted a scratch folder and wrote the DMG to disk, and it was refused;
`curl -sL <url> | shasum -a 256` asks the same question and needs neither.
**The tap is Homebrew's own clone, at
`/opt/homebrew/Library/Taps/cuonggt/homebrew-tap`, and it was three commits
behind its remote**: 0.0.9 to 0.0.11 had been committed outside it, so a cask
copied straight in would have been committed on a stale base. Fetch and
`git merge --ff-only origin/master` first; once the cask is copied in, the diff
should be the `version` and the `sha256` and nothing else. Every cask update
has used the message "Update the shellhand cask to <version>".
**Two of its fixes came from reading, not from use and not from the suite.**
The close switch had done nothing since 0.0.1 and Option had been Meta in every
release, and neither showed from where anybody stood: the suite presses no
keys and reads no preferences, and on a US keyboard Option-as-Meta looks like a
feature. A review that grepped one preference key and read SwiftTerm's
`keyDown` found both in one sitting. And the drive that proved the closing
questions on screen corrected a claim the code and this file had both just
made — that ⌘W with the Hosts tab in front closes the window. It closes
nothing.

**0.1.0 is what people expect of a terminal before they expect anything
new**, published at `00c7b77` and live on release, feed, cask and tap. It
leads with Quick Connect reaching machines that are not in the list —
`user@host:port`, a bare host, `[v6]:port` or an `ssh://` link, offered as one
more row and opened as a `Host` with an empty id, so nothing is saved. Then
the tabs: ⇧⌘] and ⇧⌘[, and ⌃⇥ and ⌃⇧⇥, step through the strip, ⌘T opens
another of the session in front rather than the host selected, and a tab has
a menu of its own. Behind those, the terminal's font can be any monospaced
family installed, Clear Scrollback is on ⌥⌘K, Export… and a Help menu are
where people look for them, and the inspector's destination has a line of its
own instead of breaking inside an address. The suite went 570 → 622.
Verified the way 0.0.12 was, and everything passed both times. **Before
publishing:** Gatekeeper, `codesign --deep --strict` and `stapler validate`
on the app **inside** the DMG as well as the one in the build products; the
DMG's staple; all three feed items' notes identical to their
`docs/release-notes` files; the 0.1.0 item's length equal to the DMG's size;
the signature reproduced by re-signing; and the cask's digest the DMG's.
**After:** every appcast URL answering 200 at the length the feed claims; the
DMG streamed back from GitHub hashing to the built one and to **both** casks,
this repository's and the tap's as GitHub serves them, which say 0.1.0 and
are the same file; the feed's blob on `main` matching the local one through
the API; and the release page's notes byte-identical to the file. Both
notarizations went through on the first attempt again, the CDN had nothing
cached for the feed or the tap's cask and served 0.1.0 at `source-age 0`, and
the tap's clone was level with its remote this time — 0.0.12 was committed
from it — so the cask went straight in, its diff the `version` and the
`sha256` and nothing else.
**The first version past 0.0.x, and nothing in the pipeline leaned on the old
shape**: the per-version rewrite put `Shellhand-0.1.0.dmg` under `v0.1.0`,
and the feed came out by build — 13, 12, 11 — with 0.0.10 retired as old
versions are. As text `0.1.0` sorts above `0.0.12` anyway, so this release
could not have caught a string comparison; 0.0.10 was the one that could, and
it held.
**`gh … --jq .body` reads one line longer than the notes it came from**, and
that is the check, not the release. The body keeps the file's own final
newline and `--jq` prints one more, so a `cmp` against the file fails on a
blank last line that nobody wrote. Compare the exact string instead — `body`
out of `gh api repos/cuonggt/shellhand/releases/tags/v<version>`, read as JSON
— which came back identical, 2,954 characters each.
**The copy in `/Applications` was still on 0.0.11 half an hour later**, and
that was no delivery failing: its `SULastCheckTime` was 23:26 on 28 October,
before 0.0.12 went out at 10:18 the next morning, so it had not looked since
either release existed. Nothing here asked it to, which is still the rule.

**0.1.1 is the first release from the list for a second user, and most of it
is things that used to fail without a word**, published at `4a1a8a3` and live
on release, feed, cask and tap. A terminal keeps 10,000 lines, which waited
on the watchdog reading the screen only around connecting — see its note
above, and the jump-chain catch that shaped it. A settings file that cannot
be used is named by an alert when the window opens, where every release before
ignored it, and a YAML import with a mistake in it is refused with the line
and column instead of arriving as an empty list. Settings ▸ General has a
switch for asking hosts what they run, on as before, and Report a Problem…
opens the issue form, with Discussions on for questions. The suite went
622 → 643.
Verified the way 0.1.0 was, and everything passed both times. **Before
publishing:** the script's own checks — signed, timestamped, universal, 0.1.1
(14), both notarizations accepted on the first attempt, Gatekeeper accepting
the app and the DMG — and on top of them Gatekeeper, `codesign --deep
--strict` and `stapler validate` on the app **inside** the DMG; the DMG's
staple; all three feed items' notes identical to their files, each served
from its own release; the 0.1.1 item's length equal to the DMG's size; the
signature reproduced by re-signing; and the cask's digest the DMG's.
**After:** every appcast URL answering 200 at the length the feed claims; the
DMG streamed back from GitHub hashing to the built one and to **both** casks,
which say 0.1.1 and are the same file; the feed's blob on `main` matching the
local one through the API; and the release page's notes byte-identical to the
file, compared as JSON this time. The CDN had nothing cached for either path
again, and the tap's clone was level with its remote, so the cask went
straight in, its diff the `version` and the `sha256`.
**Warnings, and one false alarm, none of them the release's.**
`generate_appcast` printed ten "failed to move" warnings: it retires every DMG
past the feed's few into `build/updates/old_updates`, and copies of them from
earlier runs sit both there and in the folder, so every move collides. It is
local housekeeping, and the feed checked out. The false alarm was the
pre-publish check calling the signature mismatched when it was identical:
**a base64 signature ends in `=`, so a greedy `sed 's/.*="//'` runs on to its
padding and leaves nothing.** Anchor the extraction at the attribute's name.
It is the `--jq` lesson in another key — when a check fails, read both values
before believing either.
**One thing it ships is still unseen working**: the issue form's version
fields arriving filled in rests on GitHub's documentation, since nothing here
could open the page signed in. The Hosts section was looked at after
publishing, on a scratch copy opened with `open -g` and Settings opened by
AXPress on its menu item: the switch, its caption and the corrected "read
each time Shellhand opens" all read back, and the window photographed as
built. **System Events would not name that window**: matching `name of` it
against "General" found nothing and `size of` it failed, while
`value of attribute "AXTitle"` said "General". Find a Settings window by
that attribute or by what it holds.
**The copy in `/Applications` still has 0.0.11, and that is no puzzle any
more**: it is not running, and Sparkle only looks while the app is open — its
`SULastCheckTime` was still 23:26 on 28 October after 0.1.1 went out.
