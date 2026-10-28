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
    var size: CGFloat = 16

    var body: some View {
        if let mark = OSMark.image(for: os) {
            Image(nsImage: mark)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                // A mark is somebody's artwork and carries its own colours,
                // so it is drawn as it is rather than tinted like a glyph.
                .accessibilityHidden(true)
        } else {
            // Sized rather than left to the inherited font, so that a row
            // with a mark and a row without line up: both branches draw into
            // the same box.
            Image(systemName: "server.rack")
                .font(.system(size: size))
                .foregroundStyle(.tint)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
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
