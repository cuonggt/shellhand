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

    /// The Window menu lists it as Settings, whichever pane is in front. By
    /// its title — the pane's name, as System Settings titles itself — it was
    /// "SFTP" on its SFTP pane, beside the SFTP window of the same name.
    /// AppKit lists a window afresh whenever its title changes, so this puts
    /// the name back each time it does.
    private var titleWatch: NSKeyValueObservation?

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
        titleWatch = window.observe(\.title) { [weak self] _, _ in
            Task { @MainActor in self?.listInWindowMenu() }
        }
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
        listInWindowMenu()
    }

    /// Only while it is up: AppKit adds a window not in the menu, and drops
    /// one as it closes.
    private func listInWindowMenu() {
        guard let window, window.isVisible else { return }
        NSApp.changeWindowsItem(window, title: "Settings", filename: false)
    }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
    }
}
