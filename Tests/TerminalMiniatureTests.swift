import AppKit
import SwiftUI
import Testing

@testable import Shellhand

/// That a palette's miniature actually draws that palette.
///
/// **This is a view, and this app's views are normally only checkable by
/// driving a window — which is how the miniature went unseen.** A sheet
/// cannot be opened from a script here (`click at` is inert, proven with a
/// control), so the one thing nobody could look at was the thing whose only
/// job is to be looked at.
///
/// `ImageRenderer` settles it without a window, a click or a screenshot: the
/// view is drawn into a bitmap and the pixels are read. What that can prove
/// is the half that matters — that the colours on screen are **this
/// palette's** and not a default, a blank box, or the same box for every
/// palette in the list.
@MainActor
@Suite("a palette drawn as a terminal")
struct TerminalMiniatureTests {
    private func pixels(of view: some View, scale: CGFloat = 2) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.nsImage,
              let data = image.tiffRepresentation
        else { return nil }
        return NSBitmapImageRep(data: data)
    }

    /// Every distinct colour in the render, so a palette can be checked
    /// against what it claims rather than against one sampled point — the
    /// bars move if the layout changes, and the point of this is the colours.
    private func colours(in rep: NSBitmapImageRep) -> Set<String> {
        var found: Set<String> = []
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else { continue }
                found.insert(String(
                    format: "%02X%02X%02X",
                    Int((c.redComponent * 255).rounded()),
                    Int((c.greenComponent * 255).rounded()),
                    Int((c.blueComponent * 255).rounded())))
            }
        }
        return found
    }

    /// The hex a colour comes out as **after the same rendering** the
    /// miniature goes through.
    ///
    /// Comparing against the palette's own bytes does not work and the
    /// reason is worth knowing: `ImageRenderer` puts everything through a
    /// colour-space conversion, so Nord's `#2E3440` lands as `#363E4A` —
    /// close, plainly the same colour, and not equal. Rather than invent a
    /// tolerance, the expected colour is rendered the same way, so like is
    /// compared with like and the match is exact again.
    private func rendered(_ rgb: RGB) -> String? {
        let swatch = Rectangle()
            .fill(SwiftUI.Color(nsColor: NSColor(rgb)))
            .frame(width: 8, height: 8)
        guard let rep = pixels(of: swatch, scale: 1) else { return nil }
        return colours(in: rep).first
    }

    @Test("a miniature is drawn in its own palette's colours")
    func drawsThePalette() throws {
        for name in Themes.names where name != Themes.systemName {
            let palette = try #require(Themes.named(name))
            let rep = try #require(pixels(of: TerminalMiniature(palette: palette)))
            let shown = colours(in: rep)

            let background = try #require(rendered(palette.background))
            #expect(shown.contains(background), "\(name) is not drawn on its own background")
            // The green and the foreground are the two longest bars, so they
            // are the two that cannot be missed by a sampling stride.
            let green = try #require(rendered(palette.ansi[2]))
            #expect(shown.contains(green), "\(name) is missing its green")
            let ink = try #require(rendered(palette.foreground))
            #expect(shown.contains(ink), "\(name) is missing its text")
        }
    }

    /// **The one that would catch a swatch ignoring its argument.** Every
    /// assertion above would still pass if the view drew one hard-coded
    /// palette, as long as that palette happened to be the one being asked
    /// for. Two palettes have to come out different.
    @Test("two palettes do not draw the same picture")
    func palettesDiffer() throws {
        let names = Themes.names.filter { $0 != Themes.systemName }
        try #require(names.count >= 2)
        var seen: [String: Set<String>] = [:]
        for name in names {
            let palette = try #require(Themes.named(name))
            let rep = try #require(pixels(of: TerminalMiniature(palette: palette)))
            seen[name] = colours(in: rep)
        }
        for (a, b) in zip(names, names.dropFirst()) {
            #expect(seen[a] != seen[b], "\(a) and \(b) draw the same picture")
        }
    }

    /// The System palette has nothing to ask, so it is drawn from stand-ins.
    /// It still has to draw *something*, and something dark.
    @Test("the system palette is drawn rather than left blank")
    func systemIsDrawn() throws {
        let rep = try #require(pixels(of: TerminalMiniature(palette: nil)))
        let shown = colours(in: rep)
        #expect(shown.contains("000000"), "the system miniature has no background")
        #expect(shown.count > 2, "the system miniature is a plain box")
    }
}
