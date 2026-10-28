// Writes the distribution marks in Shellhand/Resources/OSMarks.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     xcrun swift tools/osmarks.swift Shellhand/Resources/OSMarks
//
// Each mark is a rounded tile in the distribution's own colour carrying its
// own logo. The logos come from **Simple Icons**, whose files are CC0 1.0 —
// vendored in `tools/logos/` so this runs offline and so what is composed can
// be read rather than taken on trust. `tools/logos/LICENSE.md` is theirs;
// `tools/logos/README.md` says what the trademarks mean for anybody shipping
// this.
//
// A distribution with no logo to hand falls back to a tile carrying its
// initial, which is what every mark was before the logos arrived. That path
// is kept because the next distribution somebody wants may not be in the set.
//
// The geometry lives in this file for the reason `tools/icon.py` does: there
// is nowhere else to change it, so a mark cannot drift from the system.
//
// Two things measured rather than assumed, each of which would have shipped
// broken. Apple's SVG support renders **no `<text>`** at all — a white glyph
// came back the colour of its own background — so a letter is converted to an
// outline here, at generation time, where the font is certain to be present.
// It does honour **`transform`**, checked the same way with a scaled square
// landing where it was told, which is what lets a 24-unit logo be dropped
// into a 64-unit tile without rewriting its path data.

import AppKit
import CoreText

struct Mark {
    /// The `ID` in that distribution's own /etc/os-release.
    let id: String
    /// A file in `tools/logos`, or empty to fall back to `letters`.
    let logo: String
    /// The colour that distribution is known by: Simple Icons' own value,
    /// which is the brand's rather than something picked by eye.
    let hex: String
    /// Only used when there is no logo.
    var letters: String = ""
}

let marks: [Mark] = [
    Mark(id: "ubuntu", logo: "ubuntu", hex: "E95420"),
    Mark(id: "debian", logo: "debian", hex: "A81D33"),
    Mark(id: "fedora", logo: "fedora", hex: "51A2DA"),
    Mark(id: "rhel", logo: "redhat", hex: "EE0000"),
    Mark(id: "centos", logo: "centos", hex: "262577"),
    Mark(id: "rocky", logo: "rockylinux", hex: "10B981"),
    Mark(id: "almalinux", logo: "almalinux", hex: "1F2937"),
    // Oracle Linux says `ol`, which is the one id here nobody would guess.
    Mark(id: "ol", logo: "oracle", hex: "C74634"),
    Mark(id: "oracle", logo: "oracle", hex: "C74634"),
    Mark(id: "amzn", logo: "amazonwebservices", hex: "232F3E"),
    Mark(id: "alpine", logo: "alpinelinux", hex: "0D597F"),
    Mark(id: "arch", logo: "archlinux", hex: "1793D1"),
    // Leap and Tumbleweed each carry their own `ID`, and an `ID` of a
    // distribution's own never falls back to its family — so they need files
    // rather than leaning on `opensuse`.
    Mark(id: "opensuse", logo: "opensuse", hex: "73BA25"),
    Mark(id: "opensuse-leap", logo: "opensuse", hex: "73BA25"),
    Mark(id: "opensuse-tumbleweed", logo: "opensuse", hex: "5FA319"),
    Mark(id: "sles", logo: "suse", hex: "0C322C"),
    Mark(id: "kali", logo: "kalilinux", hex: "557C94"),
    Mark(id: "linuxmint", logo: "linuxmint", hex: "86BE43"),
    Mark(id: "manjaro", logo: "manjaro", hex: "35BF5C"),
    Mark(id: "gentoo", logo: "gentoo", hex: "54487A"),
    Mark(id: "void", logo: "voidlinux", hex: "478061"),
    Mark(id: "nixos", logo: "nixos", hex: "5277C3"),
    Mark(id: "raspbian", logo: "raspberrypi", hex: "A22846"),
    Mark(id: "freebsd", logo: "freebsd", hex: "AB2B28"),
    Mark(id: "openbsd", logo: "openbsd", hex: "F2CA30"),
    // NetBSD's mark is a **wordmark**, and a wordmark is not an icon: at 16pt
    // it is an unreadable smear rather than a small version of itself. This
    // is the one the letter fallback exists for.
    Mark(id: "netbsd", logo: "", hex: "CC4400", letters: "NB"),
    Mark(id: "elementary", logo: "elementary", hex: "64BAFF"),
    Mark(id: "zorin", logo: "zorin", hex: "15A6F0"),
    Mark(id: "pop", logo: "popos", hex: "48B9C7"),
    // The fallback a derivative reaches through its own `ID_LIKE`, and the
    // answer for anything that only says it is Linux.
    Mark(id: "linux", logo: "linux", hex: "FCC624"),
]

// MARK: a vendored logo

/// The one path out of a Simple Icons file.
///
/// Those files are a `<title>` and a single `<path>` by their own rule, and
/// the vendoring step checked that every file here is exactly that — so this
/// refuses rather than guessing if one ever is not.
func logo(_ name: String, in directory: String) -> String {
    let file = directory + "/" + name + ".svg"
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
        fatalError("no logo at \(file)")
    }
    let paths = text.ranges(of: try! Regex(#"d="[^"]+""#))
    guard paths.count == 1 else {
        fatalError("\(name).svg holds \(paths.count) paths, expected exactly 1")
    }
    return String(text[paths[0]].dropFirst(3).dropLast())
}

// MARK: a letter, as an outline

func font(_ size: CGFloat) -> CTFont {
    for name in ["HelveticaNeue-Bold", "Helvetica-Bold"] {
        let f = CTFontCreateWithName(name as CFString, size, nil)
        if (CTFontCopyPostScriptName(f) as String) == name { return f }
    }
    return CTFontCreateUIFontForLanguage(.system, size, nil)!
}

func outline(_ letters: String, _ font: CTFont) -> CGPath {
    let chars = Array(letters.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    guard CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count) else {
        fatalError("no glyph for \(letters)")
    }
    var advances = [CGSize](repeating: .zero, count: glyphs.count)
    CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)

    let whole = CGMutablePath()
    var x: CGFloat = 0
    for (i, glyph) in glyphs.enumerated() {
        if let one = CTFontCreatePathForGlyph(font, glyph, nil) {
            whole.addPath(one, transform: CGAffineTransform(translationX: x, y: 0))
        }
        x += advances[i].width
    }
    return whole
}

/// The outline as SVG path data, scaled to sit inside `box` and flipped:
/// glyphs are drawn with y upward from a baseline and SVG counts downward.
///
/// The points are mapped one at a time rather than by concatenating
/// transforms, because the order a `CGAffineTransform` composes in is the
/// easiest thing here to get quietly backwards.
func data(_ path: CGPath, in box: CGRect) -> String {
    let bounds = path.boundingBoxOfPath
    let scale = min(box.width / bounds.width, box.height / bounds.height)
    func place(_ p: CGPoint) -> String {
        String(format: "%.2f %.2f",
               (p.x - bounds.midX) * scale + box.midX,
               box.midY - (p.y - bounds.midY) * scale)
    }
    var d = ""
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: d += "M\(place(points[0])) "
        case .addLineToPoint: d += "L\(place(points[0])) "
        case .addQuadCurveToPoint: d += "Q\(place(points[0])) \(place(points[1])) "
        case .addCurveToPoint:
            d += "C\(place(points[0])) \(place(points[1])) \(place(points[2])) "
        case .closeSubpath: d += "Z "
        @unknown default: break
        }
    }
    return d.trimmingCharacters(in: .whitespaces)
}

// MARK: which ink the tile can carry

/// Relative luminance, so the mark on the tile is chosen rather than assumed.
///
/// Several of these colours are light enough that white on them reads poorly
/// at the size this is actually looked at — amber and the greens especially,
/// where white measures about 2.3:1 — and picking by eye is how one of them
/// ends up illegible.
func luminance(_ hex: String) -> CGFloat {
    let n = UInt32(hex, radix: 16) ?? 0
    func part(_ shift: UInt32) -> CGFloat {
        let c = CGFloat((n >> shift) & 0xFF) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * part(16) + 0.7152 * part(8) + 0.0722 * part(0)
}

// MARK: writing them out

let into = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Shellhand/Resources/OSMarks"
let sources = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "tools/logos"
let face = font(48)

// How much of the 64-unit tile the logo fills. Enough to read at 16pt, with
// room left so the rounded corners do not clip a wide mark.
let inner: CGFloat = 38
let offset = (64 - inner) / 2
let scale = inner / 24

for mark in marks {
    // White gives 1.05/(L+0.05) and this near-black 0.061, so they cross at
    // L = 0.203 — the threshold is where the better of the two changes, not a
    // number that looked about right. Every mark is reported with what it
    // ended up measuring.
    let light = luminance(mark.hex)
    let onWhite = 1.05 / (light + 0.05)
    let onInk = (light + 0.05) / (luminance("1C1C1E") + 0.05)
    let ink = onInk > onWhite ? "1C1C1E" : "FFFFFF"

    let drawn: String
    if mark.logo.isEmpty {
        let box = mark.letters.count > 1
            ? CGRect(x: 10, y: 20, width: 44, height: 24)
            : CGRect(x: 17, y: 15, width: 30, height: 34)
        drawn = """
            <path d="\(data(outline(mark.letters, face), in: box))" fill="#\(ink)"/>
            """
    } else {
        drawn = """
            <g transform="translate(\(offset) \(offset)) scale(\(scale))">\
            <path d="\(logo(mark.logo, in: sources))" fill="#\(ink)"/></g>
            """
    }

    let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
          <rect width="64" height="64" rx="14" fill="#\(mark.hex)"/>
          \(drawn)
        </svg>

        """
    try! svg.write(toFile: into + "/os-" + mark.id + ".svg", atomically: true, encoding: .utf8)
    print(String(format: "os-%@.svg  %@ on #%@, ink #%@ at %.1f:1",
                 mark.id, mark.logo.isEmpty ? mark.letters : mark.logo,
                 mark.hex, ink, max(onWhite, onInk)))
}
print("\(marks.count) marks written into \(into)")
