import AppKit
import SwiftUI

/// A double-click on something that is not in a `List`.
///
/// `List` publishes `primaryAction`, which is AppKit's own double-click action
/// and costs the first click nothing — that is what the pane's rows use. A
/// `LazyVGrid` publishes no such thing, and the SwiftUI answer,
/// `TapGesture(count: 2)`, makes **every** single click wait out the system's
/// double-click interval before it is delivered. That shipped once and a user
/// felt it on the first click.
///
/// So this is the AppKit hook instead: an `NSClickGestureRecognizer` asking
/// for two clicks with **`delaysPrimaryMouseButtonEvents` off**, which is the
/// knob that stops a recogniser holding the first mouse-down back while it
/// waits to see whether a second one arrives. The first click reaches the
/// button underneath immediately; only the second comes here.
///
/// **It installs on its superview, not on its own view**, and the reason is
/// the whole difficulty: a view in **front** of the card would take the click
/// the button needs, and one **behind** it would never see a click at all.
/// Placed as a background, this view shares the card's geometry and its
/// superview is the card, which is the view the clicks actually land on.
struct DoubleClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.action = action
        context.coordinator.install(on: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        /// What it is already on, so a redraw does not stack a second
        /// recogniser on the same card and connect twice.
        private weak var installed: NSView?

        init(action: @escaping () -> Void) { self.action = action }

        func install(on view: NSView) {
            // Deferred: at `makeNSView` the view has no superview yet, so
            // there is nothing to install on until the hierarchy is built.
            DispatchQueue.main.async { [weak self] in
                guard let self, let card = view.superview, card !== self.installed
                else { return }
                let twice = NSClickGestureRecognizer(
                    target: self, action: #selector(self.fired))
                twice.numberOfClicksRequired = 2
                twice.delaysPrimaryMouseButtonEvents = false
                card.addGestureRecognizer(twice)
                self.installed = card
            }
        }

        @objc private func fired() { action() }
    }
}
