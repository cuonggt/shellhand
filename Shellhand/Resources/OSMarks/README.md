# Distribution marks

A host is drawn with its operating system's own mark when one is here, and
with a plain server glyph when there is not. Nothing in the code lists them:
dropping a file in is the whole of adding one, and deleting it is the whole of
removing one.

## Adding one

Name the file after the `ID` the distribution puts in its own
`/etc/os-release`, prefixed with `os-`:

```
os-ubuntu.svg
os-debian.svg
os-fedora.png
os-alpine.pdf
```

`ID` is what to match, not the pretty name — `opensuse-leap`, not
"openSUSE Leap". `Core/OSRelease.swift` lowercases it, so the filename is
lowercase too. To find out what a machine calls itself, ask it:

```bash
ssh thehost 'grep ^ID= /etc/os-release'
```

A derivative that does not set its own `ID` is drawn with the mark of
whatever its `ID_LIKE` names, so Raspberry Pi OS falls back to Debian's
without needing one of its own.

**SVG, PDF and PNG** are all read, tried in that order, so a vector is
preferred where you have one. Square artwork at any size: it is drawn at
about 16pt in a row and 24pt on a card, and a rectangular wordmark will look
wrong at both.

## Why there are none here yet

These are **trademarks**, each with its own usage policy, and several —
Canonical's among them — restrict redistribution in a way that is a decision
for whoever ships this app rather than something to settle by downloading an
SVG. The code is built so that decision can be made later, or differently per
distribution, without touching it.

## This file ships, on purpose

It is copied into the app bundle along with the marks, and that is what
`OSMarkTests.theFolderIsBundled` asserts on. Every other test of this
convention is pure, so all of them would go on passing if this folder stopped
reaching the bundle at all — a dropped-in mark would simply never be found,
and the only symptom is the generic glyph, which is also what a correct miss
looks like. Leaning the guard on this file costs a kilobyte of text inside the
app and is the one thing that can tell those two apart. **Don't exclude it
from the resources phase** without replacing the guard.
