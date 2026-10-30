// Writes the website's images into site/images from the two pictures the
// project already has: the README's screenshot and the rendered app icon.
//
//   ./tools/icon-preview.sh /tmp/shellhand-icon
//   xcrun swift tools/site-images.swift /tmp/shellhand-icon
//
// Run from the repository root, after the README's picture is retaken or the
// icon changes, so that the site never shows a different window from the
// README. The icon comes from icon-preview.sh rather than the bundle's SVG
// because the squircle, the gradient and the shadow are macOS's half of it.
//
// The screenshot goes out as AVIF at two widths, which every current browser
// reads, with a PNG at the smaller width for one that does not. og.png is the
// card a link to the site unfurls into.
import AppKit
import ImageIO

let iconDir = CommandLine.arguments.dropFirst().first ?? {
    FileHandle.standardError.write(Data("usage: site-images.swift <icon-preview output dir>\n".utf8))
    exit(1)
}()
let out = URL(fileURLWithPath: "site/images", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func load(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fatalError("cannot read \(path)") }
    return image
}

func scaled(_ image: CGImage, width: Int) -> CGImage {
    let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

func write(_ image: CGImage, _ name: String, as type: String, quality: Double? = nil) {
    let url = out.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, type as CFString, 1, nil)
    else { fatalError("cannot write \(type)") }
    var options: [CFString: Any] = [:]
    if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("cannot finish \(name)") }
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("\(name)  \(image.width)x\(image.height)  \(size / 1024) KB")
}

// The icon, at the sizes the page draws it: 32 and 128 points, twice over.
for size in [64, 256] {
    write(load("\(iconDir)/Shellhand-\(size).png"), "icon-\(size).png", as: "public.png")
}
write(load("\(iconDir)/Shellhand-32.png"), "favicon-32.png", as: "public.png")

// The window. Text is what a screenshot is made of, so the quality is kept
// high enough that the small type in the inspector stays sharp.
let shot = load("docs/screenshot.png")
write(shot, "screenshot-\(shot.width).avif", as: "public.avif", quality: 0.82)
let half = scaled(shot, width: shot.width / 2)
write(half, "screenshot-\(half.width).avif", as: "public.avif", quality: 0.82)
write(half, "screenshot-\(half.width).png", as: "public.png")

// The card: the icon and the name above the window, which runs off the bottom.
let card = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 630, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
card.size = NSSize(width: 1200, height: 630)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: card)
let ground = NSColor(srgbRed: 0x0B / 255, green: 0x0C / 255, blue: 0x12 / 255, alpha: 1)
ground.setFill()
NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
NSGradient(
    starting: NSColor(srgbRed: 0x5B / 255, green: 0x55 / 255, blue: 0xC2 / 255, alpha: 0.35),
    ending: ground.withAlphaComponent(0)
)!.draw(fromCenter: NSPoint(x: 600, y: 560), radius: 0,
        toCenter: NSPoint(x: 600, y: 560), radius: 620, options: [])

NSImage(cgImage: load("\(iconDir)/Shellhand-256.png"), size: .zero)
    .draw(in: NSRect(x: 56, y: 630 - 48 - 104, width: 104, height: 104))
NSAttributedString(string: "Shellhand", attributes: [
    .font: NSFont.systemFont(ofSize: 54, weight: .bold),
    .foregroundColor: NSColor.white,
]).draw(at: NSPoint(x: 172, y: 630 - 116))
NSAttributedString(string: "A native SSH client for macOS. Free and open-source.", attributes: [
    .font: NSFont.systemFont(ofSize: 25, weight: .regular),
    .foregroundColor: NSColor(srgbRed: 0xA0 / 255, green: 0xA5 / 255, blue: 0xB8 / 255, alpha: 1),
]).draw(at: NSPoint(x: 174, y: 630 - 154))

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.set()
let width = 1088.0
let height = width * Double(shot.height) / Double(shot.width)
NSImage(cgImage: shot, size: .zero)
    .draw(in: NSRect(x: (1200 - width) / 2, y: 630 - 200 - height, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
write(card.cgImage!, "og.png", as: "public.png")
