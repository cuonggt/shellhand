# Distribution marks

A host is drawn with a mark for its operating system when one is here, and
with a plain server glyph when there is not. Nothing in the code lists them:
dropping a file in is the whole of adding one, and deleting it is the whole of
removing one.

## These are ours, not anybody's logo

Every distribution's real mark is a **trademark** with its own usage policy,
and several — Canonical's among them — restrict redistribution in a way that
is a decision for whoever ships an app rather than something to settle by
downloading an SVG. So none of them is here, and none should be added.

What ships instead is a plain tile carrying the distribution's initial, in a
colour that distribution is known by. It says which machine you are looking
at, which is the whole job, and it is drawn rather than traced.

**They are generated, not hand-written.** `tools/osmarks.swift` holds the
table — id, colour, letters — and is the only way to change them, the same
arrangement `tools/icon.py` has for the app icon:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift tools/osmarks.swift Shellhand/Resources/OSMarks
```

Two things that tool settles rather than guesses. **A letter has to be an
outline**: Apple's SVG support renders no `<text>` at all — measured, with a
white glyph coming back the colour of its own background — so an SVG naming a
font would draw as an empty tile, silently, on any Mac that lacked it. And the
**ink is chosen by contrast**, white or near-black whichever measures higher
against the tile, because white on amber or on a mid-green comes out around
2.3:1 and unreadable at the size these are looked at. Every mark is reported
with what it measures; the lowest is 4.4:1.

Judge a change at the size it is seen, not at 64:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift tools/osmarks-preview.swift Shellhand/Resources/OSMarks sheet.png
```

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

A derivative that does not set its own `ID` is drawn with the mark of whatever
its `ID_LIKE` names, so Raspberry Pi OS falls back to Debian's. A distribution
whose `ID` is its own, though, does **not** fall back — which is why
`opensuse-leap` has a file of its own rather than leaning on `opensuse`.

A letter that is already taken gets two, so that two distributions are never
the same letter in two shades of one colour.

## Hand-made marks still work

**SVG, PDF and PNG** are all read, tried in that order, so a file dropped in
by hand is found exactly as a generated one is — the code knows nothing about
the generator. Square artwork at any size: it is drawn at about 16pt in a row
and 22pt on a card, and a rectangular wordmark will look wrong at both. A mark
that is somebody's trademark should not be one of them, for the reason above.
