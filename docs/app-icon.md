# The app icon

Shellhand ships an **Icon Composer bundle** — `Shellhand/Resources/Shellhand.icon`
— rather than a classic `AppIcon.appiconset` of ten PNGs.

## Why that format

macOS 26 introduced the layered `.icon` alongside the asset catalogue, and the
question was whether a `.icon` can be produced and kept without the GUI app.
It can.

`xcrun ictool` is in the Xcode toolchain (`Developer/usr/bin/ictool`, Xcode
27.1 here). It is an `actool` sibling — same plist in, same plist out — and it
compiles a bundle on its own:

```bash
xcrun ictool --compile <out-dir> --platform macosx \
  --minimum-deployment-target 26.0 --app-icon Shellhand Shellhand.icon
```

A `.icon` is a directory holding `icon.json` and an `Assets/` folder of SVGs.
Nothing about it is binary, so `tools/icon.py` writes it and git can diff it,
which is the whole reason to prefer it: an appiconset is ten PNGs that no one
can review, and changing the mark means re-exporting all ten at the right
sizes and hoping.

The deployment target is macOS 26.0 and nothing older, so there is no system
that needs the flat icon as well. In exchange the system composites the
squircle, the gradient from one fill colour, the shadow, the specular
highlight, and the dark and tinted variants — none of which an appiconset
gets. On Tahoe an app with a flat icon looks like an app that was not
updated.

What is *not* available from the command line: `--export-preview` exists
inside `IconComposerFoundation.framework` but `ictool` does not register it,
so previewing belongs to the GUI. `tools/icon-preview.sh` gets around that by
compiling the bundle into a stub app and asking `NSWorkspace` for that app's
icon — which is the image Finder and the Dock will draw, so it is the more
honest check anyway.

## The mark

A shell prompt: a chevron, and the block cursor waiting after it. The app puts
a prompt on a machine that is somewhere else, and that is the thing it draws.

Four directions were drawn and rendered before this one was picked, and the
judging was done at 16, 32 and 128 rather than at 512, because 16pt is where
an icon fails and a mark that works at 512 tells you nothing about it:

- **A bare chevron** reads perfectly at 16pt and says nothing. It is the
  disclosure arrow in every sidebar and the Next button in every wizard.
- **A chevron reaching a round node** — a prompt and the host it reaches — was
  the best idea and the worst render: two small shapes at 16pt merge into one
  blob with no reading at all.
- **Three stacked chevrons**, for forwarding, came out as a media player's
  fast-forward.
- **A chevron joined to a node by a line** turned into a tuning fork, and at
  16pt into a smear.

The chevron and block cursor won because it is specifically a terminal rather
than generically an arrow, and because the cursor's vertical mass survives
being three pixels wide where a circle of the same area did not.

The geometry lives in `tools/icon.py` as named numbers, laid out from a
measured total width so the composition is centred by construction. `GAP` is
the one that was tuned, and it was tuned at 16pt: narrower and the cursor
smears into the chevron's tip. A heavier stroke was tried for the same reason
and made it worse — past about 110 units the chevron's own notch fills in and
the prompt becomes a blob.

The fill is a blue-violet. It is the darkest of the four colourways tried,
which is what holds a white mark at 16pt, and it is not the blue that every
other developer tool in the Dock is already wearing.

## Changing it

```bash
python3 tools/icon.py Shellhand/Resources/Shellhand.icon   # rewrite the bundle
./tools/icon-preview.sh /tmp/shellhand-icon                # look at it small
```

The preview writes PNGs from 16 to 512, a contact sheet of the small sizes at
true scale on a light and a dark ground, and a loupe — 16 and 32 blown up with
the pixels kept square, since smoothing a 16pt icon makes it look better than
it is. Judge on the loupe.

`tools/icon-preview.sh` takes a second argument, so a candidate elsewhere can
be rendered without touching the committed one.
