#!/usr/bin/env python3
"""Write Shellhand's app icon.

The icon is an Icon Composer bundle — `icon.json` beside an SVG — rather than
an asset catalogue of ten PNGs, so what the repository carries is text that can
be read and diffed. macOS composites the rest: the squircle, the gradient from
the fill colour, the shadow, the specular highlight, and the dark and tinted
variants. See docs/app-icon.md for why.

The mark is a shell prompt: a chevron and the block cursor waiting after it.
Its parts are laid out from a measured total width so the composition is
centred by construction rather than by nudging a number until it looks right.

    python3 tools/icon.py Shellhand/Resources/Shellhand.icon

`tools/icon-preview.sh` renders whatever this writes at the sizes that decide
an icon.
"""

import json
import pathlib
import sys

CANVAS = 1024.0
MID = CANVAS / 2

# The mark, in canvas units. STROKE's round cap reaches half its width past
# each end of the chevron's path, which is why it counts towards the width.
#
# GAP is the number that was tuned, and it was tuned at 16pt rather than at
# 512: narrower than this and the cursor smears into the chevron's tip, which
# is invisible at any size where the icon looks finished. A heavier STROKE was
# tried for the same reason and made it worse — past about 110 the chevron's
# own notch fills in and the mark goes from a prompt to a blob.
STROKE = 108.0
REACH = 246.0          # the chevron's horizontal span, cap to cap excluded
RISE = 210.0           # how far each arm climbs from the tip
GAP = 170.0            # chevron's cap to the cursor's edge
CURSOR_W = 164.0
CURSOR_H = 236.0

# A blue-violet. Dark enough to hold a white mark at 16pt, and not the blue
# every other developer tool in the Dock is already wearing.
FILL = "extended-srgb:0.29000,0.24000,0.72000,1.00000"


def mark() -> str:
    """The prompt and its cursor, centred on the canvas."""
    width = (REACH + STROKE) + GAP + CURSOR_W
    left = (CANVAS - width) / 2
    # The path starts a cap's width in, so the cap lands on `left`.
    arm_x = left + STROKE / 2
    tip_x = arm_x + REACH
    cursor_x = tip_x + STROKE / 2 + GAP

    chevron = (
        f'<path d="M {arm_x:.1f} {MID - RISE:.1f} '
        f'L {tip_x:.1f} {MID:.1f} '
        f'L {arm_x:.1f} {MID + RISE:.1f}" '
        f'fill="none" stroke="#ffffff" stroke-width="{STROKE:.1f}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>'
    )
    cursor = (
        f'<rect x="{cursor_x:.1f}" y="{MID - CURSOR_H / 2:.1f}" '
        f'width="{CURSOR_W:.1f}" height="{CURSOR_H:.1f}" '
        f'rx="{CURSOR_W * 0.32:.1f}" fill="#ffffff"/>'
    )
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
        f'viewBox="0 0 1024 1024">{chevron}{cursor}</svg>\n'
    )


def document() -> dict:
    """The icon.json macOS composites the mark into.

    Translucency is off: a glassy mark loses the contrast that is the whole of
    legibility at 16pt, where the icon is fourteen pixels of squircle.
    """
    return {
        "fill": {"automatic-gradient": FILL},
        "groups": [
            {
                "layers": [{"image-name": "Mark.svg", "name": "Mark"}],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "translucency": {"enabled": False, "value": 0.5},
            }
        ],
        "supported-platforms": {"circles": ["watchOS"], "squares": ["iOS", "macOS"]},
    }


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: icon.py <destination.icon>")
    dest = pathlib.Path(sys.argv[1])
    (dest / "Assets").mkdir(parents=True, exist_ok=True)
    (dest / "Assets" / "Mark.svg").write_text(mark())
    (dest / "icon.json").write_text(json.dumps(document(), indent=2) + "\n")
    print(dest)


if __name__ == "__main__":
    main()
