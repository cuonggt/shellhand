import AppKit

// Render a built .app's icon at the sizes that decide one, plus a contact
// sheet on both a light and a dark ground.
//
// It asks NSWorkspace for the bundle's icon rather than rasterising the SVG,
// because an Icon Composer mark is only half of what ends up on screen: the
// squircle, the gradient, the shadow and the specular are the system's, and
// a preview drawn without them is a preview of something nobody sees.
let args = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: RenderIcon <app> <outdir> [label]\n", stderr); exit(2) }
let appPath = args[1], outDir = args[2]
let label = args.count > 3 ? args[3] : URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let icon = NSWorkspace.shared.icon(forFile: appPath)

func bitmap(_ image: NSImage, _ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
               from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes = [16, 32, 64, 128, 256, 512]
for px in sizes {
    let rep = bitmap(icon, px)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(label)-\(px).png")
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

// Contact sheet: the small sizes shown at true scale against both backgrounds,
// which is the only way 16pt tells you anything.
let pad = 24, gap = 28
let small = [16, 32, 48, 64, 128]
let sheetW = pad * 2 + small.reduce(0) { $0 + $1 + gap } - gap
let sheetH = 128 * 2 + pad * 3 + 40
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sheetW, pixelsHigh: sheetH,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSGraphicsContext.current?.imageInterpolation = .high
// top band light, bottom band dark
NSColor.white.setFill(); NSRect(x: 0, y: sheetH / 2, width: sheetW, height: sheetH / 2).fill()
NSColor(white: 0.13, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: sheetW, height: sheetH / 2).fill()
var x = pad
for px in small {
    for (i, bandBottom) in [sheetH / 2 + pad, pad].enumerated() {
        _ = i
        icon.draw(in: NSRect(x: x, y: bandBottom, width: px, height: px),
                  from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    x += px + gap
}
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.gray,
]
var lx = pad
for px in small {
    ("\(px)" as NSString).draw(at: NSPoint(x: lx, y: sheetH / 2 - 16), withAttributes: attrs)
    lx += px + gap
}
(label as NSString).draw(at: NSPoint(x: pad, y: sheetH - 20), withAttributes: attrs)
NSGraphicsContext.restoreGraphicsState()
try? sheet.representation(using: .png, properties: [:])?
    .write(to: URL(fileURLWithPath: outDir).appendingPathComponent("\(label)-sheet.png"))

// The small sizes again, blown up with the pixels kept square. A 16pt icon is
// fourteen pixels of squircle; shown at 16pt nobody can see what is wrong with
// it, and shown smoothed it looks better than it is.
let zoom = 9
let zoomed = [16, 32]
let zW = pad * 2 + zoomed.reduce(0) { $0 + $1 * zoom + gap } - gap
let zH = pad * 2 + 32 * zoom
let loupe = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: zW, pixelsHigh: zH,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: loupe)
NSColor(white: 0.5, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: zW, height: zH).fill()
NSGraphicsContext.current?.imageInterpolation = .none
var zx = pad
for px in zoomed {
    let rep = bitmap(icon, px)
    let img = NSImage(size: NSSize(width: px, height: px))
    img.addRepresentation(rep)
    img.draw(in: NSRect(x: zx, y: pad, width: px * zoom, height: px * zoom),
             from: .zero, operation: .sourceOver, fraction: 1.0)
    zx += px * zoom + gap
}
NSGraphicsContext.restoreGraphicsState()
try? loupe.representation(using: .png, properties: [:])?
    .write(to: URL(fileURLWithPath: outDir).appendingPathComponent("\(label)-loupe.png"))
print("rendered \(label)")
