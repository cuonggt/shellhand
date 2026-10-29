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

/// Put behind the host list, so ⌃⇥ and ⌃⇧⇥ step through the strip the way
/// ⇧⌘] and ⇧⌘[ do from the Window menu.
///
/// **A monitor, because a menu item holds one key** and the menu's are
/// spent on ⇧⌘] and ⇧⌘[. It also gets there first: a local monitor sees a
/// key before any view does, so the terminal in front cannot take ⌃⇥ for
/// itself the way it takes every other control key.
///
/// It acts only on keys meant for this window — a sheet over it is a window
/// of its own, so Quick Connect and the closing questions keep their ⌃⇥ —
/// and lets the key go when `step` says there was nowhere to step to.
struct StepsTabs: NSViewRepresentable {
    let step: (Int) -> Bool

    final class Coordinator {
        var step: (Int) -> Bool = { _ in false }
        var monitor: Any?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let coordinator = context.coordinator
        coordinator.step = step
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak view, weak coordinator] event in
            guard let coordinator, let window = view?.window, event.window === window,
                  let offset = StepsTabs.offset(for: event)
            else { return event }
            return coordinator.step(offset) ? nil : event
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.step = step
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }

    /// +1 for ⌃⇥, -1 for ⌃⇧⇥, nil for anything else — Caps Lock and the
    /// like ignored, any other modifier held meaning it is some other key.
    static func offset(for event: NSEvent) -> Int? {
        let tab: UInt16 = 48
        guard event.keyCode == tab else { return nil }
        switch event.modifierFlags.intersection([.command, .control, .option, .shift]) {
        case [.control]: return 1
        case [.control, .shift]: return -1
        default: return nil
        }
    }
}

/// Put behind the host list, to stand a `ClosingGuard` in front of its
/// window's delegate — on update rather than on make, for the reason
/// `TagsHostsWindow` gives.
struct GuardsClosing: NSViewRepresentable {
    let sessions: Sessions

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            ClosingGuard.stand(in: window, for: sessions)
        }
    }
}

/// Asks before the host window closes on sessions somebody is in.
///
/// **In front of SwiftUI's own delegate, never instead of it.** The window
/// is the `WindowGroup`'s, and its delegate is SwiftUI's window controller —
/// measured, not assumed — which answers `windowShouldClose` itself and is
/// told when the window becomes key, resizes and closes. Cut it off and
/// SwiftUI loses track of its own window. So every message this does not
/// answer goes straight through to it, and once the question here is
/// answered yes, it is asked as well.
///
/// **The window keeps it, not a view.** A delegate is held weakly: a guard
/// owned by a view that SwiftUI rebuilt would vanish and leave the window
/// with no delegate at all, SwiftUI's included. Hung on the window, it lasts
/// exactly as long as the window does.
final class ClosingGuard: NSObject, NSWindowDelegate {
    /// SwiftUI's delegate, held weakly: it holds the window, which holds this.
    /// Read by the two overrides below, which the runtime calls from no actor.
    private nonisolated(unsafe) weak var behind: (any NSWindowDelegate)?
    private weak var sessions: Sessions?
    /// Set when the question has been answered yes, so the close that answer
    /// starts goes through rather than being asked about again.
    private var answered = false

    /// Where the window keeps its guard.
    private static let key = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    /// Puts a guard in front of the window's delegate, or points the one
    /// already there at these sessions.
    static func stand(in window: NSWindow, for sessions: Sessions) {
        if let standing = window.delegate as? ClosingGuard {
            standing.sessions = sessions
            return
        }
        let guarding = ClosingGuard()
        guarding.behind = window.delegate
        guarding.sessions = sessions
        objc_setAssociatedObject(window, key, guarding, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.delegate = guarding
    }

    /// What closing the window would ask now, or nil to let it close.
    func question(confirming: Bool = Closing.confirmsNow) -> Closing.Question? {
        Closing.question(
            .closingWindow, dropping: (sessions?.all ?? []).map(Closing.Open.init),
            confirming: confirming)
    }

    /// The delegate this stands in front of, so a test can see the chain is
    /// whole: SwiftUI's window controller, for the host window.
    var inFrontOf: (any NSWindowDelegate)? { behind }

    func windowShouldClose(_ window: NSWindow) -> Bool {
        if !answered, let question = question() {
            NSAlert(asking: question).beginSheetModal(for: window) { [weak self, weak window] in
                guard $0 == .alertFirstButtonReturn, let self, let window else { return }
                self.answered = true
                window.performClose(nil)
            }
            return false
        }
        answered = false
        return behind?.windowShouldClose?(window) ?? true
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (behind?.responds(to: selector) ?? false)
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        if let behind, behind.responds(to: selector) { return behind }
        return super.forwardingTarget(for: selector)
    }
}

extension NSAlert {
    /// One of `Closing`'s questions, with the button that goes ahead first —
    /// so Return answers it, as it does in Terminal.app — and Cancel on Escape.
    convenience init(asking question: Closing.Question) {
        self.init()
        messageText = question.title
        informativeText = question.message
        addButton(withTitle: question.confirm)
        addButton(withTitle: "Cancel")
    }
}
