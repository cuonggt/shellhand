# The name, and what to charge

Decided 2026-10-18; revisited 2026-10-22 when the repository went public under
GPL-3.0-or-later.

**The name is Shellhand**, with the bundle ID `com.shellhand.Shellhand`, the
cask `cuonggt/tap/shellhand` and the update feed at `updates.shellhand.app`.
The trademark search and the domains under [Before shipping](#before-shipping)
are still to do, and so is the price.

## Why this name

- It means something: a *hand* is crew — deckhand, farmhand, a ship's hand. A
  shellhand is the one who works your shells. It sits in the same family as
  `bosun` without being a dictionary word, which is why it survived checks
  that killed every single word tried.
- It was free everywhere checked: `.com`, `.app` and `.dev`, both App Stores,
  Homebrew, GitHub, npm, and no command of that name on this Mac.
- A web search turned up no product called Shellhand or Shell Hand.
- It is easy to say, spell and search for, which nautical vocabulary mostly
  is not.

**This was not a trademark search.** Before shipping, search USPTO (classes 9
and 42) and EUIPO.

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

- Trademark: USPTO classes 9 and 42, and EUIPO.
- Register `shellhand.app`, then `.com` and `.dev`. Not urgent for the feed —
  a public repository can serve the appcast and the DMGs from GitHub Releases,
  so the URL compiled into the first build need not wait on a domain. It is
  permanent once a build ships, so choose it deliberately.
- Take the GitHub account `shellhand` the same day.
