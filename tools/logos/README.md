# Logo sources

The distribution logos `tools/osmarks.swift` composes into the marks in
`Shellhand/Resources/OSMarks`. Vendored rather than fetched, so the generator
runs offline and so what gets composed can be read before it ships.

## Where they came from

[Simple Icons](https://simpleicons.org) 13.15.0, taken from
`cdn.jsdelivr.net/npm/simple-icons@13.15.0/icons/<slug>.svg`. `LICENSE.md`
beside this file is theirs, unaltered: the icon files are **CC0 1.0**, so no
attribution is required and this note is here because provenance is worth
recording anyway.

Each file is a `<title>` and a single `<path>` on a 24×24 viewBox, with no
fill — they are silhouettes meant to be coloured by whoever uses them. Every
file here was checked to be exactly that shape before being vendored, and the
generator refuses a file that holds anything else rather than composing
something it did not expect.

## What the licence does not cover

CC0 waives copyright in the *files*. It says nothing about **trademarks**, and
every one of these marks is somebody's: Canonical's, Red Hat's, the Debian
project's, and so on. Drawing a distribution's logo beside a server running
that distribution is nominative use — it identifies the machine, which is the
whole job, and is what every hosting panel and server dashboard does. It is
not an endorsement and must never be presented as one.

Two things follow for anybody shipping this app:

- **Don't use these marks to brand anything.** They belong on a host row and
  nowhere else — not in the app icon, not in a README header, not on a
  website for this app.
- **Policies differ and some are strict**, Canonical's among the strictest.
  If this is ever distributed somewhere that cares — an app store listing, a
  bundled OEM build — that is worth a read of each project's trademark policy
  rather than an assumption that CC0 settled it.

Removing a logo is deleting its row from the table in `tools/osmarks.swift`
and re-running it; the distribution then falls back to a tile carrying its
initial, which needs nobody's permission.

## Updating them

```bash
curl -sS -o tools/logos/<slug>.svg \
  "https://cdn.jsdelivr.net/npm/simple-icons@13.15.0/icons/<slug>.svg"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift tools/osmarks.swift Shellhand/Resources/OSMarks tools/logos
```

Then look at the result at the size it is seen, which is 16pt and not 64:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift tools/osmarks-preview.swift Shellhand/Resources/OSMarks sheet.png
```

**Not every logo survives 16pt**, and that is the one thing this step is for.
NetBSD's is a *wordmark*, which at 16pt is an unreadable smear rather than a
small version of itself, so it uses the letter fallback instead. Anything with
very fine linework — Kali's dragon, CentOS's lattice — goes grey at a row's
size and is carried by its colour there; that is a judgement to make with the
sheet in front of you, not from the full-size artwork.
