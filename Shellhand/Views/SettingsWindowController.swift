import AppKit
import SwiftUI

/// The window Settings lives in.
///
/// An `NSWindow` made here rather than a SwiftUI `Settings` scene, because
/// the style mask is the thing that matters and a scene does not expose it:
/// `.fullSizeContentView` is what gets the rounded, translucent chrome macOS
/// 26 draws, and setting it afterwards through an `NSViewRepresentable` does
/// not hold — SwiftUI puts the window back the way it had it.
///
/// What the `Settings` scene gave for free was Shellhand ▸ Settings on ⌘,.
/// That is bought back in `Commands.swift` with a `CommandGroup(replacing:
/// .appSettings)`, so the item stays where every Mac app keeps it.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    /// Opens Settings, on a given tab if one is asked for.
    static func show(storePath: String, configPath: String, tab: SettingsTab? = nil) {
        if let tab { SettingsNavigation.shared.selectedTab = tab }
        if shared == nil {
            shared = SettingsWindowController(storePath: storePath, configPath: configPath)
        }
        shared?.showWindow(nil)
    }

    private init(storePath: String, configPath: String) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 700, height: 500)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable,
                        // The one that matters: without it there is no glass.
                        .fullSizeContentView],
            backing: .buffered,
            defer: false)
        super.init(window: window)

        window.title = "Settings"
        window.toolbarStyle = .automatic
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("SettingsWindow")
        window.minSize = NSSize(width: 620, height: 420)
        // A window made in code is released when it closes, which would leave
        // this controller holding a freed one. The controller owns it instead.
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SettingsRootView(storePath: storePath, configPath: configPath))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Settings is not made from a nib.")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        // Shellhand keeps a Dock icon, so there is no activation policy to
        // step up here — the window just needs bringing to the front.
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
    }
}
