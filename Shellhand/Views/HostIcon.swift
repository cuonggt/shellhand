import AppKit
import SwiftUI

/// What a host is drawn as: its operating system's own mark where one is
/// bundled, and a plain server otherwise.
///
/// **Nothing lists the distributions.** A mark is found by name —
/// `os-ubuntu.svg` for a machine whose `/etc/os-release` says `ID=ubuntu` —
/// so adding one is dropping a file into `Resources/OSMarks` and removing one
/// is deleting it. That matters more than it looks: these are trademarks with
/// their own usage policies, so which of them ship is a decision somebody has
/// to be able to change without touching code.
///
/// The fallback is not an error state. A host that has never connected has
/// said nothing about itself; one that only takes a password cannot be asked,
/// since the probe goes over SFTP with `BatchMode=yes`; and a distribution
/// nobody has drawn yet is simply not drawn. All three look the same on
/// purpose — there is nothing for a user to fix in any of them.
struct HostIcon: View {
    /// The `ID` out of the host's own `/etc/os-release`, or empty.
    let os: String
    /// What to call it in words. Empty is allowed and means the mark says
    /// nothing to anyone who does not recognise it, which is why every call
    /// site that has one passes it.
    var named: String = ""
    var size: CGFloat = 16

    var body: some View {
        mark
            // **Named, not hidden.** Hiding it was right while it was a
            // decorative fallback glyph and wrong the moment it carried
            // which operating system a machine runs: several of these are a
            // coloured tile at the size a row draws them, so somebody who
            // does not recognise one has no way to find out, and somebody
            // using VoiceOver has no way to know it is there at all.
            //
            // With nothing known there is nothing to say, and an "unknown"
            // announced on every row would be noise over the host's own name
            // — so it stays decoration in exactly that case.
            .accessibilityHidden(named.isEmpty)
            .accessibilityLabel(named)
            .help(named)
    }

    @ViewBuilder private var mark: some View {
        if let mark = OSMark.image(for: os) {
            Image(nsImage: mark)
                .resizable()
                .aspectRatio(contentMode: .fit)
                // The full slot, so a mark is as big as the glyph it stands
                // in for. It was shrunk to 0.9 once, to make the two the
                // same *height* — the glyph is wider than it is tall — and
                // that only made the marks look small beside it.
                .frame(width: size, height: size)
                // A mark is somebody's artwork and carries its own colours,
                // so it is drawn as it is rather than tinted like a glyph.
        } else {
            // The plain symbol, as it has always been. A tile of its own was
            // tried, to match the marks' weight; asked for back, because a
            // host nobody has asked yet should look like an absence rather
            // than like a badge for "unknown".
            //
            // So the two do not weigh the same, and that is accepted: a
            // filled mark beside line art always reads heavier. What they do
            // share is the slot and the size.
            Image(systemName: "server.rack")
                .font(.system(size: size))
                .foregroundStyle(.tint)
                .frame(width: size, height: size)
        }
    }
}

/// Finding the artwork for a distribution id.
nonisolated enum OSMark {
    /// What a mark for this id would be called, without the extension.
    ///
    /// Pure, and tested, because the convention is the whole interface: the
    /// name is the only agreement between a file somebody drops in and the
    /// code that looks for it, and a change here silently stops every mark
    /// being found.
    static func resourceName(for os: String) -> String? {
        let id = os.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // A path separator would reach outside the bundle's own resources,
        // and the id comes off a machine somebody else administers.
        guard !id.isEmpty, !id.contains("/"), !id.contains("..") else { return nil }
        return "os-" + id
    }

    /// The marks already looked up, since a list of forty hosts asks for the
    /// same handful over and over and a miss costs a filesystem walk.
    nonisolated(unsafe) private static var found: [String: NSImage?] = [:]
    private static let lock = NSLock()

    static func image(for os: String) -> NSImage? {
        guard let name = resourceName(for: os) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let already = found[name] { return already }
        // Vector first where there is one.
        let mark = ["svg", "pdf", "png"]
            .lazy
            .compactMap { Bundle.main.url(forResource: name, withExtension: $0) }
            .compactMap { NSImage(contentsOf: $0) }
            .first
        found[name] = mark
        return mark
    }
}
