import AppKit
import SwiftUI
import Testing

@testable import Shellhand

/// That a host with a known operating system and one without look like the
/// same kind of thing.
///
/// **Size was the wrong thing to measure, and measuring it is what showed
/// that.** A mark and a bare `server.rack` were given matching bounding
/// boxes and still did not look alike, because a filled tile beside line art
/// never will: a mark inked **79%** of its slot and the symbol **36%**, so
/// making the mark smaller only made it small and still heavier.
///
/// Both are tiles now, so they match by construction rather than by tuning a
/// number — and what this checks is the thing that was wrong, which is how
/// much ink each one puts on the screen.
@MainActor
@Suite("a host's icon, known or not")
struct HostIconTests {
    /// The extent of what is actually drawn, in pixels, at 4x.
    private func ink(_ view: some View) -> (width: Int, height: Int, box: Int)? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 4
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

    /// How much of its slot a view inks, as a percentage.
    private func inked(_ view: some View) -> Double? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 8
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        var opaque = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh
            where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.35 {
                opaque += 1
            }
        }
        return Double(opaque) / Double(rep.pixelsWide * rep.pixelsHigh) * 100
    }

    @Test("a mark and an unknown host weigh the same")
    func sameWeight() throws {
        let mark = try #require(inked(HostIcon(os: "ubuntu")))
        let plain = try #require(inked(HostIcon(os: "")))
        #expect(abs(mark - plain) < 3, "mark \(Int(mark))% against plain \(Int(plain))%")
        // And both are tiles rather than one being line art: a bare symbol
        // inks about a third of its slot, which is the state this fixed.
        #expect(mark > 80, "a tile should fill its slot, not sketch it")
    }

    /// An intricate logo and a simple one weigh the same too, because what
    /// is being weighed is the tile and not the artwork on it.
    @Test("an intricate mark weighs no more than a simple one")
    func intricateIsNoHeavier() throws {
        let simple = try #require(inked(HostIcon(os: "ubuntu")))
        let busy = try #require(inked(HostIcon(os: "openbsd")))
        #expect(abs(simple - busy) < 3)
    }

    /// The slot has to stay the same whatever is in it, or the names beside
    /// the icons do not line up down the column — which is the thing a
    /// reader actually notices.
    @Test("both sit in a slot of the asked-for size")
    func sameSlot() throws {
        let mark = try #require(ink(HostIcon(os: "ubuntu")))
        let glyph = try #require(ink(HostIcon(os: "")))
        #expect(mark.box == glyph.box)
        #expect(mark.box == 64, "16pt at 4x")
    }

    /// A card asks for 22 rather than 16, so the size has to reach both
    /// branches and not just the glyph.
    @Test("asking for a bigger icon makes both bigger")
    func scalesTogether() throws {
        let small = try #require(ink(HostIcon(os: "ubuntu", size: 16)))
        let large = try #require(ink(HostIcon(os: "ubuntu", size: 22)))
        #expect(large.height > small.height)

        let plain = try #require(ink(HostIcon(os: "", size: 22)))
        #expect(abs(large.height - plain.height) <= 2)
    }
}
