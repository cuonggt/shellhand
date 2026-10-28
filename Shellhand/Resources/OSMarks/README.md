# Distribution marks

A host is drawn with a mark for its operating system when one is here, and
with a plain server glyph when there is not. Nothing in the code lists them:
dropping a file in is the whole of adding one, and deleting it is the whole of
removing one.

**These files are generated. Don't edit them here** — edit the table in
`tools/osmarks.swift` and run it:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift tools/osmarks.swift Shellhand/Resources/OSMarks tools/logos
```

## What a mark is

A rounded tile in the distribution's own colour carrying its own logo. The
logos come from [Simple Icons](https://simpleicons.org), vendored in
`tools/logos/` under CC0 — **see `tools/logos/README.md` for what that licence
covers and, more to the point, what it does not: these are trademarks, and
drawing one beside a server running that distribution is nominative use, not
branding.** Read that file before adding or moving one.

A distribution with no logo to hand falls back to a tile carrying its initial.
That is what every mark was before the logos arrived, and it is still the
right answer for some: **NetBSD's mark is a wordmark**, which at 16pt is an
unreadable smear rather than a small version of itself.

## Adding one

Add a row to the table in `tools/osmarks.swift` and run it again. The `id` is
what that distribution puts in its own `/etc/os-release`, and the filename is
that prefixed with `os-`:

```
os-ubuntu.svg
os-debian.svg
os-opensuse-leap.svg
```

`ID` is what to match, not the pretty name — `opensuse-leap`, not
"openSUSE Leap". `Core/OSRelease.swift` lowercases it, so the filename is
lowercase too. To find out what a machine calls itself, ask it:

```bash
ssh thehost 'grep ^ID= /etc/os-release'
```

Some ids are not the name: Oracle Linux says `ol`, and Pop!\_OS says `pop`.

A derivative that does not set its own `ID` is drawn with the mark of whatever
its `ID_LIKE` names, so a Debian derivative falls back to Debian's. A
distribution whose `ID` **is** its own, though, does not fall back — which is
why `opensuse-leap` has a file rather than leaning on `opensuse`.

## Judge it at 16pt

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift tools/osmarks-preview.swift Shellhand/Resources/OSMarks sheet.png
```

That sheet draws every mark at 48, 22 and 16 — a card's size and a row's size
— because **16 is where a mark fails** and it is where most of them are seen.
Fine linework goes grey there: Kali's dragon and the CentOS lattice are
carried by their colour at a row's size and only resolve on a card. That is a
judgement to make with the sheet in front of you, not from the full-size
artwork.

Two things the generator settles rather than guesses, both measured, both of
which would otherwise have shipped broken:

- **A letter has to be an outline.** Apple's SVG support renders no `<text>`
  at all, so an SVG naming a font would draw as an empty tile, silently, on
  any Mac lacking it. The letters are CoreText outlines.
- **The ink is chosen by contrast**, white or near-black whichever measures
  higher against the tile. White on amber or a mid-green is about 2.3:1 and
  unreadable at this size. The generator prints what each mark measured; the
  lowest is 4.4:1.

It does honour `transform`, checked the same way, which is what lets a
24-unit logo drop into a 64-unit tile without rewriting its path data.

## Hand-made marks still work

**SVG, PDF and PNG** are all read, tried in that order, so a file dropped in
by hand is found exactly as a generated one is — the code knows nothing about
the generator. Square artwork at any size: it is drawn at about 16pt in a row
and 22pt on a card, and a rectangular wordmark will look wrong at both, for
the reason NetBSD's does.
