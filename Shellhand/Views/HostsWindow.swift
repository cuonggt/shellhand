import AppKit
import SwiftUI

/// The host list's window, findable from anywhere.
///
/// It is the one window this app does not make itself — it belongs to the
/// `WindowGroup`, so unlike Settings and SFTP there is no controller holding
/// it. Shellhand ▸ Hosts has to reach it while something else is in front: an
/// SFTP window, or Settings. That is exactly when a focused scene value is
/// nil, so `AppActions` is no use for this one item; tagging the window and
/// asking AppKit is what works from a `Commands` body. (`openWindow` is no
/// use either: it does nothing unless a live view asks for it.)
enum HostsWindow {
    static let identifier = NSUserInterfaceItemIdentifier("shellhand.hosts")

    /// Brings it forward, activating the app first so the window comes up in
    /// front of whatever other application is there.
    ///
    /// Does nothing when there is no such window. A `WindowGroup`'s window can
    /// be closed outright, and what reopens it then is the Dock icon rather
    /// than anything reachable from here.
    static func front() {
        guard let window = NSApp.windows.first(where: { $0.identifier == identifier })
        else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Put behind the host list, to tag the window it lands in.
///
/// The tag is set on update rather than on make, for the reason `TableFinder`
/// waits a turn: while the background view is being made it is not in the
/// hierarchy yet, so it has no window to tag. Re-tagging a window that
/// already carries it is skipped, and a view that has lost its window is left
/// alone until it has one again.
struct TagsHostsWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        guard view.window?.identifier != HostsWindow.identifier else { return }
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = HostsWindow.identifier
        }
    }
}
