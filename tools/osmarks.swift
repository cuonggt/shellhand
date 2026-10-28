// Writes the distribution marks in Shellhand/Resources/OSMarks.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     xcrun swift tools/osmarks.swift Shellhand/Resources/OSMarks
//
// These are **our own marks, not anybody's logo.** Every distribution's real
// mark is a trademark with its own usage policy, several of them restricting
// redistribution, so none of them is here and none should be added: what ships
// is a plain tile carrying the distribution's initial, in a colour the
// distribution is known by. That is nominative — it says which machine you are
// looking at — and it is drawn here rather than traced from anything.
//
// The geometry lives in this file for the reason `tools/icon.py` does: there
// is nowhere else to change it, so a mark cannot drift from the system.
//
// **A letter has to be a path.** Apple's SVG support renders no `<text>` at
// all — measured, with a white glyph coming back the colour of its own
// background — so the letters are converted to outlines here, at build time,
// where the font is certain to be present. An SVG naming a font would render
// as an empty tile on a Mac that lacked it, and silently.

import AppKit
import CoreText

struct Mark {
    let id: String      // the `ID` in that distribution's own /etc/os-release
    let hex: String     // a colour it is known by, not a logo
    let letters: String // one letter, or two where one would collide
}

// Ordered as a person would think of them: the common server distributions
// first, then the rest. Two letters only where a single one is taken by
// something somebody is more likely to be looking at.
let marks: [Mark] = [
    Mark(id: "ubuntu", hex: "E95420", letters: "U"),
    Mark(id: "debian", hex: "D70A53", letters: "D"),
    Mark(id: "fedora", hex: "3C6EB4", letters: "F"),
    Mark(id: "rhel", hex: "EE0000", letters: "RH"),
    Mark(id: "centos", hex: "932279", letters: "C"),
    Mark(id: "rocky", hex: "10B981", letters: "R"),
    Mark(id: "almalinux", hex: "1F6FEB", letters: "AL"),
    Mark(id: "oracle", hex: "C74634", letters: "O"),
    Mark(id: "amzn", hex: "FF9900", letters: "AZ"),
    Mark(id: "alpine", hex: "0D597F", letters: "AP"),
    Mark(id: "arch", hex: "1793D1", letters: "A"),
    Mark(id: "opensuse", hex: "73BA25", letters: "S"),
    Mark(id: "opensuse-leap", hex: "73BA25", letters: "S"),
    Mark(id: "opensuse-tumbleweed", hex: "5FA319", letters: "S"),
    Mark(id: "sles", hex: "0C322C", letters: "SE"),
    Mark(id: "kali", hex: "557C94", letters: "K"),
    Mark(id: "linuxmint", hex: "3EA055", letters: "M"),
    Mark(id: "manjaro", hex: "35BF5C", letters: "MJ"),
    Mark(id: "gentoo", hex: "54487A", letters: "G"),
    Mark(id: "void", hex: "478061", letters: "V"),
    Mark(id: "nixos", hex: "5277C3", letters: "N"),
    Mark(id: "raspbian", hex: "C51A4A", letters: "RP"),
    Mark(id: "freebsd", hex: "AB2B28", letters: "B"),
    Mark(id: "openbsd", hex: "B58900", letters: "OB"),
    Mark(id: "netbsd", hex: "CC4400", letters: "NB"),
    // The fallback a derivative reaches through its own `ID_LIKE`, and the
    // answer for anything that only says it is Linux.
    Mark(id: "linux", hex: "4A4A4A", letters: "L"),
]

// MARK: the letter, as an outline

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

/// Relative luminance, so the letter is chosen rather than assumed.
///
/// Half of these colours are light enough that a white letter on them reads
/// poorly at the size this is actually looked at — amber and the greens
/// especially, where white measures about 2.3:1 — and picking by eye is how
/// one of them ends up illegible.
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
let face = font(48)

for mark in marks {
    // One letter gets a taller, narrower box than two; the aspect is kept
    // either way, so a wide pair simply lands shorter.
    let box = mark.letters.count > 1
        ? CGRect(x: 10, y: 20, width: 44, height: 24)
        : CGRect(x: 17, y: 15, width: 30, height: 34)
    // White gives 1.05/(L+0.05) and this near-black 0.061, so they cross at
    // L = 0.203 — the threshold is where the better of the two changes, not a
    // number that looked about right. Every mark is reported with what it
    // ended up measuring.
    let light = luminance(mark.hex)
    let onWhite = 1.05 / (light + 0.05)
    let onInk = (light + 0.05) / (luminance("1C1C1E") + 0.05)
    let ink = onInk > onWhite ? "1C1C1E" : "FFFFFF"
    let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
          <rect width="64" height="64" rx="14" fill="#\(mark.hex)"/>
          <path d="\(data(outline(mark.letters, face), in: box))" fill="#\(ink)"/>
        </svg>

        """
    let path = into + "/os-" + mark.id + ".svg"
    try! svg.write(toFile: path, atomically: true, encoding: .utf8)
    print(String(format: "os-%@.svg  %@ on #%@, ink #%@ at %.1f:1",
                 mark.id, mark.letters, mark.hex, ink, max(onWhite, onInk)))
}
print("\(marks.count) marks written into \(into)")
