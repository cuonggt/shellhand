import AppKit
import SwiftUI

/// The window the SFTP browser lives in. **One at a time.**
///
/// A window rather than a tab because a window can sit beside a terminal and
/// a tab cannot, so a transfer can be watched while something else is typed.
/// This has been a tab, a window, a tab and a window again; `CLAUDE.md` keeps
/// the reasoning each way round.
///
/// One instead of one per opening, which is what it was the last time it was
/// a window: asking again brings the window you have forward and **re-points**
/// it, rather than stacking another over it. So two hosts' files at once is
/// the two panes inside, not two windows.
///
/// Made here rather than as a SwiftUI `Window` scene for the reasons
/// `CLAUDE.md` records: `openWindow` does nothing unless a live view asks for
/// it, so a scene has to be opened by bumping a counter some view watches,
/// and the first scene in `body` is the one macOS opens at launch, so a
/// second needs suppressing or it comes up instead of the host list. A
/// controller is asked directly, and a menu item can ask it.
@MainActor
final class FilesWindowController: NSWindowController, NSWindowDelegate {
    /// The one open, if any. Held because a controller nothing refers to is
    /// deallocated with its window still on screen.
    private static var shared: FilesWindowController?

    /// The browser inside it, so a second asking can move it.
    private let files: FilesModel
    /// Whether closing has been asked about and agreed, so the close the
    /// answer starts goes through rather than asking again.
    private var answered = false

    /// What closing the window would stop, for quitting to count as well.
    static var transfersStillToGo: Int {
        shared.map { TransferQueue.stillToGo($0.files.transfers) } ?? 0
    }

    /// Opens the browser, or brings the one open forward. On a host, the
    /// right side goes there; from nowhere in particular it asks which host
    /// rather than showing this Mac twice.
    static func show(store: HostStore, on host: Host?) {
        if front() {
            // Asked again on a different host, the window that is already
            // there moves — `start` would not, since it only fills a side
            // that was never chosen.
            if let host, let shared { Task { await shared.files.show(host) } }
            return
        }
        let controller = FilesWindowController(store: store, on: host)
        shared = controller
        controller.showWindow(nil)
    }

    /// Brings the browser forward if there is one, and says whether there
    /// was. **Needs no store**, which is the whole point.
    ///
    /// `AppActions` is a focused scene value, nil whenever the host window is
    /// not in front — and that included standing in the SFTP window itself,
    /// so ⌘B did nothing at the one moment it was most likely to be pressed.
    /// *Opening* a browser needs the store the host window holds, but
    /// bringing an existing one forward does not; and if you are looking at
    /// the window, one exists by definition. So the menu tries this first and
    /// falls back to `AppActions` only to make a new one.
    @discardableResult
    static func front() -> Bool {
        guard let shared else { return false }
        shared.showWindow(nil)
        return true
    }

    private init(store: HostStore, on host: Host?) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 900, height: 600)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        files = FilesModel(
            db: store.dbPath,
            home: TestRun.active ? TestRun.home : FileManager.default.homeDirectoryForCurrentUser.path)
        super.init(window: window)

        // Just "SFTP": there is one of these and either side can be
        // re-pointed, so a title naming a host would be wrong as soon as you
        // navigated, and there is no second window to tell it apart from.
        window.title = "SFTP"
        window.minSize = NSSize(width: 720, height: 420)
        // A window made in code is released when it closes, which would leave
        // this controller holding a freed one. The controller owns it instead.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: FilesPane(store: store, files: files, openedOn: host))
        // These three in this order, as the keys window learned: a hosting
        // controller sizes the window to its view's minimum and throws away
        // the rect `NSWindow` was given, and setting the autosave name
        // applies a saved frame straight away, so it comes last.
        window.setContentSize(NSSize(width: 980, height: 640))
        window.center()
        window.setFrameAutosaveName("FilesWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SFTP is not made from a nib.")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Let go on closing, so the next opening is a fresh browser rather than
    /// one still holding the connections of the last. Nothing is left talking
    /// to a host with no window to show it.
    ///
    /// **`files.close()` is what makes that last sentence true, and it was
    /// missing.** `Core` holds each `SFTPClient` in `sessions`, so letting the
    /// controller go released the window and the model and *not* the `ssh`
    /// children: one per connected pane stayed alive, per opening, until the
    /// app quit. `FilesModel.close()` existed and was documented and had no
    /// callers anywhere — which is why the comment above described behaviour
    /// the code did not have. It also answers a replace question still on
    /// screen, which nothing else here could.
    func windowWillClose(_ notification: Notification) {
        files.close()
        Self.shared = nil
    }

    /// Asks before closing stops transfers, by `Closing`'s rule and the way
    /// the host window asks before it ends sessions. Closing used to stop
    /// them without a word, while Settings said it would ask.
    func windowShouldClose(_ window: NSWindow) -> Bool {
        if !answered, let question = Closing.question(
            .closingFiles, dropping: [], stopping: TransferQueue.stillToGo(files.transfers),
            confirming: Closing.confirmsNow) {
            NSAlert(asking: question).beginSheetModal(for: window) { [weak self, weak window] in
                guard $0 == .alertFirstButtonReturn, let self, let window else { return }
                self.answered = true
                window.performClose(nil)
            }
            return false
        }
        answered = false
        return true
    }
}
