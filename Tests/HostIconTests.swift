import AppKit
import SwiftUI
import Testing

@testable import Shellhand

/// That a host with a known operating system and one without look like the
/// same kind of thing.
///
/// A mark is a solid square and `server.rack` is wide line art, so "the same
/// size" is not something either of them can be given by setting one number
/// — it has to be **drawn and measured**, which is what this does. Left
/// alone, the mark filled its whole box and stood a point and a half taller
/// than the glyph, and a list where some hosts are known and some are not
/// looked ragged down the column.
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

    @Test("a bundled mark draws the same height as the plain glyph")
    func sameHeight() throws {
        let mark = try #require(ink(HostIcon(os: "ubuntu")))
        let glyph = try #require(ink(HostIcon(os: "")))
        #expect(abs(mark.height - glyph.height) <= 2,
                "mark \(mark.height)px against glyph \(glyph.height)px; re-measure HostIcon.drawn")
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
