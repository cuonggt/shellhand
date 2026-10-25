# The name, and what to charge

Decided 2026-10-18; revisited 2026-10-22 under GPL-3.0-or-later, and again on
2026-10-25 when the repository was actually made public.

**The name is Shellhand**, with the bundle ID `com.shellhand.Shellhand` and
the cask `cuonggt/tap/shellhand`. The trademark search, the domains and the
update feed's host are still to do, and so is the price — see
[Before shipping](#before-shipping).

## Why this name

- It means something: a *hand* is crew — deckhand, farmhand, a ship's hand. A
  shellhand is the one who works your shells. It sits in the same family as
  `bosun` without being a dictionary word, which is why it survived checks
  that killed every single word tried.
- It was clear on every register checked at the time — the domains, both App
  Stores, Homebrew, GitHub, npm — and there is no command of that name on
  this Mac.
- A web search turned up no product called Shellhand or Shell Hand.
- It is easy to say, spell and search for, which nautical vocabulary mostly
  is not.

## What the registers say

Searched 2026-10-25 through [TMview](https://www.tmdn.org/tmview/), which
covers EUIPO, the USPTO, WIPO and the national offices in one query.

- **`shellhand` returns nothing.** No mark of that name, in any class, at any
  participating office. The instrument was checked rather than trusted: the
  same search for `shellfire` returns three marks across Italy, Vietnam and
  the USPTO, and it matched `CHELLFIRE` too, so it is doing fuzzy matching and
  a zero means zero.
- **`shell hand` as two words returns 24**, every one of them a loose match
  holding both words separately — `THE HAND SHELL`, `NUTSHELL HANDBOOK`,
  `HANDCRAFTED SOLID-SHELL` and so on. Fifteen have ended and two expired.
  None is a unitary Shellhand.
- **One live mark is worth knowing about: `HANDYSHELL`**, USPTO 85954312,
  registered, **class 9**, owned by Speculative Product Design LLC — the same
  two elements the other way round. Their class 9 is phone cases, not
  developer tools. Whether that distance is enough is a lawyer's question,
  not one this file can answer.
- Nothing turned up in **class 42** at all.

**This is still not a clearance search, and none of it is legal advice.** It
is a knockout search for an identical or near-identical name. It does not
cover phonetic equivalents, unregistered common-law rights, or anyone's
judgement about likelihood of confusion — and TMview says itself that it is
not an official register and carries no legal effect.

**The SHELL element was not assessed.** That is the one structural question
left and it wants an attorney, because it cuts both ways: in computing a
shell is a command interpreter and the word is close to descriptive, while
SHELL is also among the most broadly protected marks there is. A coined
unitary word for an SSH client is a long way from fuel, but "a long way" is
exactly the kind of judgement worth paying for before the name is on
something harder to change than a GitHub release.

## Names already ruled out

Worth keeping so they are not revisited:

- **Berth** — already an SSH client: "Berth: SFTP, SSH & Terminal" is on the
  Mac App Store, so anything built on *berth* now reads as derivative.
- **Bollard**, **Gangway**, **Hawser**, **Capstan** — each is a well-starred
  project already, and Capstan is also a tape-drive part.
- **Deckhand**, **Fairlead**, **Windlass**, **Mooring** — clean on the stores
  and Homebrew, but all three domains are registered for each, which is true
  of nearly every dictionary word.
- **Shellcleat**, **Hostcleat** — clean, but read as sports shoes to anyone
  outside sailing. **Hostberth** is clean on the registers and spent
  conceptually, next to Berth. **Shellport** is flat and its namespaces are
  gone.

## What the name touches

Cheap now, expensive after a release:

- The repository, and the Xcode project, scheme and target.
- `PRODUCT_BUNDLE_IDENTIFIER`. Changing it cost only test data, which would
  not have been true once anything had been granted to it.
- `~/Library/Application Support/Shellhand/`, where the host list lives, and
  the defaults domain behind `@AppStorage`.
- The Homebrew cask, the Sparkle feed URL and where `SUPublicEDKey` lives.

## Pricing — still to decide

Not settled. The shape under consideration is a paid app with a trial: a
one-off price carrying a year of updates, then a smaller renewal to keep
getting them, sold through a merchant of record. Nothing here costs money to
run, so there is no subscription to fund — only the work.

**What GPL-3.0 moves.** Selling builds is untouched: the licence asks that
whoever receives a binary can get the source, which they can, and nothing in
it asks for a price of zero. Two things do change.

- The **Mac App Store is out** as a channel while the app is only GPL —
  Apple's terms and the licence do not agree. Getting it back means
  dual-licensing, which is possible only because the copyright is held by one
  person.
- Anyone can build the app from source. So **what is sold is the notarized,
  signed, Sparkle-updated build** and the support behind it, not access to the
  code. The price has to live in the polish and the convenience, which is an
  argument for finishing release packaging before thinking about a number.

## Before shipping

- Trademark: the register search is done and clean (see above). What is left
  is an attorney on the SHELL element and on classes 9 and 42 — **and this is
  now overdue**, because 0.0.1 and 0.0.2 have already shipped under the name.
- Secure the name's domains and namespaces. **Which ones, and where each
  stands, are deliberately not in this file**, because the repository is
  public and a list of what is still unclaimed is a list of what to take.
- The update feed can wait on none of it: a public repository serves the
  appcast and the DMGs from GitHub Releases, so the URL compiled into the
  first build need not wait on a domain. That URL is permanent once a build
  ships, so choose it deliberately.
