// A contact sheet of the distribution marks, at the sizes that decide them.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     xcrun swift tools/osmarks-preview.swift Shellhand/Resources/OSMarks sheet.png
//
// The sibling of `tools/icon-preview.sh`, and for the same reason: **a mark is
// judged at 16pt, not at 64**, because 16 is where it fails and where it is
// mostly looked at — a row in the host list. Each mark is drawn at the two
// sizes the app actually draws it, a row's 16 and a card's 22, beside a large
// one for the artwork itself.
//
// Drawn at two device pixels per point and left unsmoothed, so what is on the
// sheet is what a Retina screen puts there rather than a kinder version of it.

import AppKit

let from = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Shellhand/Resources/OSMarks"
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "osmarks.png"

let files = (try! FileManager.default.contentsOfDirectory(atPath: from))
    .filter { $0.hasPrefix("os-") && $0.hasSuffix(".svg") }
    .sorted()

let scale: CGFloat = 2
let sizes: [CGFloat] = [48, 22, 16]
let rowHeight: CGFloat = 60
let columnWidth: CGFloat = 320
let columns = 2
let rows = (files.count + columns - 1) / columns
let width = columnWidth * CGFloat(columns)
let height = rowHeight * CGFloat(rows) + 20

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
context.cgContext.scaleBy(x: scale, y: scale)

NSColor.white.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let label: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11),
    .foregroundColor: NSColor.black,
]

for (i, file) in files.enumerated() {
    let column = CGFloat(i / rows)
    let row = CGFloat(i % rows)
    // Flipped: the bitmap's origin is at the bottom and a list reads downward.
    let top = height - 10 - row * rowHeight
    var x = column * columnWidth + 16

    guard let image = NSImage(contentsOfFile: from + "/" + file) else { continue }
    for size in sizes {
        image.draw(in: NSRect(x: x, y: top - size - (48 - size) / 2, width: size, height: size))
        x += size + 14
    }
    let name = file.replacingOccurrences(of: "os-", with: "")
        .replacingOccurrences(of: ".svg", with: "")
    NSString(string: name).draw(at: NSPoint(x: x + 6, y: top - 32), withAttributes: label)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("\(files.count) marks at \(sizes.map { Int($0) }) onto \(out)")
