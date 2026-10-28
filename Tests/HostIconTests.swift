import AppKit
import SwiftUI
import Testing

@testable import Shellhand

/// That a host with a known operating system and one without are drawn the
/// same size.
///
/// **They share the slot and the size, and not the weight**, which is settled
/// rather than accidental. A filled mark beside line art always reads
/// heavier, and two attempts to close that gap were both wrong: shrinking
/// the marks to the glyph's *height* only made them look small beside it,
/// since the glyph is wider than it is tall; and giving a host with no known
/// OS a tile of its own did make the two weigh the same, at the price of an
/// unasked host looking like a badge for "unknown" rather than an absence.
///
/// So what is checked here is what is meant to hold.
@MainActor
@Suite("a host's icon, known or not")
struct HostIconTests {
    /// The extent of what is actually drawn, in pixels, at 8x.
    private func ink(_ view: some View) -> (width: Int, height: Int, box: Int)? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 8
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        var minX = rep.pixelsWide, maxX = -1, minY = rep.pixelsHigh, maxY = -1
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let colour = rep.colorAt(x: x, y: y),
                      colour.alphaComponent > 0.1 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (maxX - minX + 1, maxY - minY + 1, rep.pixelsWide)
    }

    /// **The one that catches a shrunk mark**, which is what this was for a
    /// while: 0.9 of the slot, chosen to match the glyph's height, and
    /// visibly narrower than it.
    @Test("a mark is drawn as wide as the glyph it stands in for")
    func asWideAsTheGlyph() throws {
        let mark = try #require(ink(HostIcon(os: "ubuntu")))
        let glyph = try #require(ink(HostIcon(os: "")))
        #expect(mark.width == glyph.width,
                "mark \(mark.width)px against glyph \(glyph.width)px")
        #expect(mark.width == mark.box, "a mark fills its slot")
    }

    /// The slot has to stay the same whatever is in it, or the names beside
    /// the icons do not line up down the column — which is the thing a
    /// reader actually notices.
    @Test("both sit in a slot of the asked-for size")
    func sameSlot() throws {
        let mark = try #require(ink(HostIcon(os: "ubuntu")))
        let glyph = try #require(ink(HostIcon(os: "")))
        #expect(mark.box == glyph.box)
        #expect(mark.box == 128, "16pt at 8x")
    }

    /// A card asks for 22 rather than 16, so the size has to reach both
    /// branches and not just the glyph.
    @Test("asking for a bigger icon makes both bigger")
    func scalesTogether() throws {
        let small = try #require(ink(HostIcon(os: "ubuntu", size: 16)))
        let large = try #require(ink(HostIcon(os: "ubuntu", size: 22)))
        #expect(large.width > small.width)

        let plain = try #require(ink(HostIcon(os: "", size: 22)))
        #expect(large.width == plain.width)
    }

    /// A host nobody has asked yet draws the plain symbol, not a tile: an
    /// absence rather than a badge saying "unknown". Line art inks about a
    /// third of its slot where a filled mark inks nearly all of it, so the
    /// coverage is what tells the two apart.
    @Test("an unknown host is drawn as line art, not as a badge")
    func unknownIsNotABadge() throws {
        func inked(_ view: some View) -> Double {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 8
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return 0 }
            var opaque = 0
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh
                where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.35 {
                    opaque += 1
                }
            }
            return Double(opaque) / Double(rep.pixelsWide * rep.pixelsHigh) * 100
        }
        #expect(inked(HostIcon(os: "")) < 55, "the plain symbol should be line art")
        #expect(inked(HostIcon(os: "ubuntu")) > 80, "a mark fills its slot")
    }
}
