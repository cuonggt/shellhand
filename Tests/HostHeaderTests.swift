import AppKit
import SwiftUI
import Testing

@testable import Shellhand

/// The inspector header's destination: what it says, and that it keeps to
/// one line however long the address.
///
/// The layout is checked by rendering, the way `TerminalMiniatureTests`
/// reads a palette's pixels: the line is drawn into a bitmap at a narrow
/// width and its height is the number of lines, near enough. A header that
/// wrapped inside an address is a thing nobody could check without driving
/// the inspector, which this app's views do not answer to.
///
/// `Shellhand.Host` spelled out: SwiftUI brings `Foundation.Host` with it.
@MainActor
@Suite("Host header")
struct HostHeaderTests {
    private let width: CGFloat = 200
    private let short = "deploy@192.0.2.21"
    private let long = "deploy@ip-10-0-13-223.eu-west-1.compute.internal port 2222"

    /// How tall a view comes out at a width narrower than the inspector's.
    private func height(of view: some View) -> CGFloat {
        ImageRenderer(content: view.frame(width: width, alignment: .leading)).nsImage?.size.height ?? 0
    }

    /// **The control first**: plain text this long at this width does wrap,
    /// so the renderer is measuring a layout rather than handing back one
    /// size whatever it is given — without that, the last check would pass
    /// for nothing. And a short line has to come out as tall as plain text,
    /// or the line is not being drawn as text at all.
    @Test("a destination longer than its line keeps to one line")
    func oneLine() {
        let plainShort = height(of: Text(short).font(.callout))
        let plainLong = height(of: Text(long).font(.callout))
        #expect(plainShort > 0)
        #expect(plainLong > plainShort * 1.5, "plain text did not wrap, so this measures nothing")
        #expect(abs(height(of: DestinationLine(text: short)) - plainShort) < 1,
                "a short destination is not drawn like a line of text")
        #expect(abs(height(of: DestinationLine(text: long)) - plainShort) < 1,
                "a long destination wrapped")
    }

    /// The one spelling, the way ssh is typed. It was written five ways
    /// across the window: "port 2222" here, a stray space before the colon in
    /// the sidebar, no port at all in ⌘K.
    @Test("it says the user, the address, and a port other than 22, as ssh is typed")
    func wording() {
        var host = Shellhand.Host(name: "db-01", addr: "192.0.2.21")
        host.effective.user = "deploy"
        host.effective.port = 2222
        #expect(host.destinationLine == "deploy@192.0.2.21:2222")
        #expect(host.addressLine == "192.0.2.21:2222")
        host.effective.port = 22
        #expect(host.destinationLine == "deploy@192.0.2.21")
        #expect(host.addressLine == "192.0.2.21")
        host.effective.user = ""
        #expect(host.destinationLine == "192.0.2.21")
    }

    @Test("an IPv6 address is bracketed where a port follows it")
    func ipv6() {
        var host = Shellhand.Host(name: "v6", addr: "2001:db8::5")
        host.effective.user = "root"
        host.effective.port = 2222
        #expect(host.destinationLine == "root@[2001:db8::5]:2222")
        host.effective.port = 22
        #expect(host.destinationLine == "root@2001:db8::5")
    }

    /// One argument a line, as ssh receives it: the quoted line of a jump
    /// chain was a wall of `'"'"'` cut in the middle of a path.
    @Test("what will run reads one argument a line, an option beside its value")
    func commandLines() {
        let preview = HostPreview(argv: [
            "-p", "2200",
            "-o", "ProxyCommand=ssh -p 2222 -i /keys/jump -W '[10.0.1.5]:2200' jump@10.0.0.9",
            "app@10.0.1.5",
        ])
        #expect(preview.lines.map(\.text) == [
            "ssh",
            "-p 2200",
            "-o ProxyCommand=ssh -p 2222 -i /keys/jump -W '[10.0.1.5]:2200' jump@10.0.0.9",
            "app@10.0.1.5",
        ])
        #expect(HostPreview().lines.isEmpty)
        #expect(HostPreview(argv: ["-T", "web"]).lines.map(\.text) == ["ssh", "-T", "web"])
    }

    /// The view wraps a value under itself, so the jump host at the end of a
    /// long `ProxyCommand` stays inside it rather than reading as a second
    /// destination.
    @Test("an option is kept apart from its value, an argument alone has none")
    func optionApart() {
        let jump = "ProxyCommand=ssh -i '~/.ssh/id_ed25519' -W '[192.0.2.21]:2222' deploy@192.0.2.10"
        let lines = HostPreview(argv: ["-p", "2222", "-o", jump, "-A", "deploy@192.0.2.21"]).lines
        #expect(lines == [
            HostPreview.Line(value: "ssh"),
            HostPreview.Line(option: "-p", value: "2222"),
            HostPreview.Line(option: "-o", value: jump),
            HostPreview.Line(value: "-A"),
            HostPreview.Line(value: "deploy@192.0.2.21"),
        ])
    }
}
