import AppKit
import Foundation
import SwiftUI
import Observation
import SwiftTerm

/// One connection: /usr/bin/ssh on a pty the window owns, with the terminal
/// SwiftTerm draws.
///
/// Phase 0 settled two things this is built around. ssh's own output can be
/// kept out of the terminal with `-E`, which leaves the pty carrying only what
/// the remote wrote — so a refusal or an unknown host key becomes something
/// the app can show rather than text scrolling past. And a session riding a
/// shared master dies with it, so every tab makes its own connection.
@Observable
@MainActor
final class TerminalSession: Identifiable, LocalProcessTerminalViewDelegate {
    nonisolated enum State: Equatable {
        case connecting
        case connected
        /// ssh wants an answer about a host key. The text is what it asked.
        case askingHostKey(String)
        /// The connection ended. `code` is ssh's exit status, and `diagnostic`
        /// is whatever ssh wrote to its log rather than to the terminal.
        case ended(code: Int32?, diagnostic: String)
    }

    nonisolated let id = UUID()
    let view = FocusingTerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))

    /// What the terminal is drawn on, for the room around it.
    ///
    /// **The palette's own value, not the view's.** `nativeBackgroundColor`
    /// looks like the right source and is not: read back it answers white for
    /// a terminal that is plainly drawing black, which is how the first
    /// attempt at this put a white ring around a black terminal. The palette
    /// is what this app asked for, and is the only thing here that knows.
    ///
    /// Black for the **System** palette, which installs no colours of ours at
    /// all — taken off a screenshot of one rather than assumed, since there
    /// is nothing to ask.
    private(set) var background = SwiftUI.Color.black
    private(set) var state: State = .connecting
    private(set) var title: String
    /// What ssh said for itself, kept apart from what the remote wrote.
    private(set) var diagnostics = ""
    /// The scrollback search belongs to the session: the Find menu drives it,
    /// and switching tabs and back should not lose what was typed.
    var findOpen = false
    var findTerm = ""
    /// How many times the watchdog has looked, so a state that never moves can
    /// be told from a watchdog that never ran.
    private(set) var ticks = 0
    /// How many of those looks read the screen: all of them while there can
    /// be a question to ask, none once the session has settled — see
    /// `SessionProgress.watches`.
    private(set) var looks = 0
    /// When the watchdog last took the session through. Settable so that a
    /// test can settle a session without waiting two minutes for it.
    var connectedAt: Date?
    private(set) var host: Host?

    /// Readable so that a test can put an ssh log where the watchdog looks.
    let logPath: String
    private var watchdog: Task<Void, Never>?
    private var themeObserver: (any NSObjectProtocol)?
    private var settingsObserver: (any NSObjectProtocol)?
    /// The Option setting as this session last took it from Settings, which
    /// is not always what its terminal is doing — see `watchSettings`.
    private var optionSetting: Bool
    /// The font family as this session last took it from Settings, empty for
    /// SF Mono — and what Actual Size goes back to, at Settings' size.
    private var fontSetting: String

    /// `optionAsMeta` and `fontFamily` are parameters so that a test can hand
    /// a session either value without writing the user's own defaults to do
    /// it.
    init(title: String, host: Host?,
         optionAsMeta: Bool = TerminalSession.prefersOptionAsMeta,
         fontFamily: String = TerminalFont.preferred) {
        self.title = title
        self.host = host
        self.optionSetting = optionAsMeta
        self.fontSetting = fontFamily
        self.logPath = NSTemporaryDirectory() + "shellhand-ssh-\(UUID().uuidString).log"
        view.processDelegate = self
        view.font = TerminalFont.font(named: fontFamily, size: Self.preferredFontSize)
        view.optionAsMetaKey = optionAsMeta
        view.changeScrollback(Self.scrollback)
        apply(theme: Self.theme(for: host))
        // Settings is a scene of its own and cannot reach the sessions a
        // window holds, so the change is announced and each one listens.
        watchTheme()
        watchSettings()
    }

    private func watchTheme() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .shellhandThemeChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The host's own palette still wins: changing the Settings one
                // should not repaint a terminal whose colours were chosen for
                // it by its group.
                self.apply(theme: TerminalSession.theme(for: self.host))
            }
        }
    }

    /// Follows the Option switch and the font in Settings while the session
    /// is open.
    ///
    /// **Any change to the defaults, not a notice Settings has to remember
    /// to post.** A setting writing its key is then the whole of the wiring,
    /// with no second step to forget — which is how `confirmCloseLiveSession`
    /// switched nothing from the day it was added until it was wired up.
    /// The price is hearing every other write too, so only a change to a
    /// setting itself reaches the terminal: otherwise a window saving its
    /// frame would undo SwiftTerm's own ⌥⌘O, which flips the one terminal it
    /// is pressed in.
    private func watchSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.takeSettings() }
        }
    }

    /// Takes whichever of Settings' choices changed since this session last
    /// took them. A new font keeps the size this session is at, since ⌘+ and
    /// ⌘- may have put it somewhere other than Settings' size.
    private func takeSettings() {
        let option = Self.prefersOptionAsMeta
        if option != optionSetting {
            optionSetting = option
            view.optionAsMetaKey = option
        }
        let family = TerminalFont.preferred
        if family != fontSetting {
            fontSetting = family
            view.font = TerminalFont.font(named: family, size: view.font.pointSize)
        }
    }

    isolated deinit {
        // A block observer is held by the centre until it is handed back —
        // `weak self` keeps the session from being pinned, but the block
        // itself would outlive every tab that was ever opened.
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    /// Starts ssh with the argv the core built, plus the one option the app
    /// adds for itself.
    func start(argv: [String]) {
        state = .connecting
        diagnostics = ""
        try? FileManager.default.removeItem(atPath: logPath)
        // nil rather than an empty array: SwiftTerm reads nil as "inherit",
        // and a session with no TERM or PATH is not a session.
        // Under `Forking`'s lock, so the fork cannot land while some pipe is
        // still unmarked and take it into this terminal for its whole life.
        Forking.exclusively {
            view.startProcess(executable: "/usr/bin/ssh", args: ["-E", logPath] + argv,
                              environment: nil)
        }
        watch()
    }

    /// A local shell, for a window that wants one.
    ///
    /// **It starts at home, and saying so is the whole point.** A forked shell
    /// inherits the app's working directory, and an app launched the ordinary
    /// way — by LaunchServices, from the Dock or Finder — has `/`. So a local
    /// shell opened at the root of the disk, which is nobody's idea of where a
    /// terminal begins; Terminal.app opens at home and so does this.
    func startLocalShell() {
        state = .connected
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        Forking.exclusively {
            view.startProcess(
                executable: shell, execName: "-" + (shell as NSString).lastPathComponent,
                currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
        }
    }

    func send(_ text: String) { view.send(txt: text) }

    @discardableResult
    func findNext() -> Bool {
        guard !findTerm.isEmpty else { return false }
        return view.findNext(findTerm)
    }

    @discardableResult
    func findPrevious() -> Bool {
        guard !findTerm.isEmpty else { return false }
        return view.findPrevious(findTerm)
    }

    /// "3 of 17", or nothing when nothing is being looked for.
    var findSummary: String {
        guard !findTerm.isEmpty else { return "" }
        let found = view.searchMatchSummary(findTerm)
        return found.total == 0 ? "none" : "\(found.index) of \(found.total)"
    }

    /// Bigger or smaller text, within what is readable.
    func changeFontSize(by delta: CGFloat) {
        let font = view.font
        let size = min(28, max(9, font.pointSize + delta))
        view.font = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
    }

    /// How many lines a terminal keeps above its screen, set here so this app
    /// knows the number — SwiftTerm will not say what it is, and Clear
    /// Scrollback has to put it back exactly.
    ///
    /// **10,000, where SwiftTerm's own default is 500**, and measured rather
    /// than picked: a line costs about 8 bytes a column, so 8–16MB a session
    /// at 80–200 columns; a search that finds nothing takes 0.1–0.2s and a
    /// resize that rewraps every line 10–14ms. 100,000 cost 70–140MB, 1–2s
    /// searches and 0.1–0.2s rewraps. Raising it waited on the watchdog,
    /// which read the whole history five times a second until
    /// `SessionProgress.watches` stopped it once a session settles.
    static let scrollback = 10_000

    /// Clear Scrollback, ⌥⌘K: drops every line above the screen and keeps
    /// the screen itself — the shell's prompt, or the vim in front of it.
    ///
    /// **By shrinking the history to nothing and back.** `Terminal`'s own
    /// `clearScrollback` is out of reach, its view keeping the terminal
    /// internal. Feeding it the `ESC [3J` a shell's `clear` sends would work
    /// on the buffer in front only — nothing at all while vim has the
    /// alternate screen — and could land in the middle of an escape sequence
    /// the far end is half way through sending, and garble it. This acts on
    /// the normal buffer whatever is in front, and never goes near the
    /// parser.
    func clearScrollback() {
        view.changeScrollback(0)
        view.changeScrollback(Self.scrollback)
    }

    /// Actual Size: Settings' size, in the font this session is drawn in —
    /// not SF Mono, which is what it went back to before there was a choice.
    func resetFontSize() {
        view.font = TerminalFont.font(named: fontSetting, size: Self.preferredFontSize)
    }

    /// What Settings asks new sessions to start at.
    static var preferredFontSize: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "defaultFontSize")
        return stored > 0 ? CGFloat(stored) : 12
    }

    /// Where Settings keeps whether Option is Meta, named once so the switch
    /// and the sessions cannot read two different keys.
    nonisolated static let optionAsMetaSetting = "optionAsMeta"

    /// Whether a new terminal treats Option as Meta: what Settings says, and
    /// **off** while nobody has touched the switch.
    ///
    /// Off, Option types what the keyboard puts on it. Meta turns that into
    /// Esc and the bare key instead, so on the many layouts that put `@`,
    /// `|`, `{}` or `[]` on Option those could not be typed into a session at
    /// all — and Meta is SwiftTerm's own default, which this app left alone
    /// for every release up to 0.0.11. Off is where Terminal.app, iTerm2 and
    /// Ghostty start too.
    nonisolated static var prefersOptionAsMeta: Bool {
        UserDefaults.standard.bool(forKey: optionAsMetaSetting)
    }

    /// The palette Settings has chosen, or nil for SwiftTerm's own.
    static var preferredTheme: Palette? {
        Themes.named(UserDefaults.standard.string(forKey: "terminalTheme") ?? Themes.systemName)
    }

    /// What this host's terminal is painted with: whatever the host, or the
    /// nearest group above it, asked for — and the one chosen in Settings when
    /// nothing in the chain did.
    ///
    /// A name nothing answers to falls through to Settings rather than
    /// blanking the terminal, which is what a theme renamed in the config file
    /// would otherwise do to every host that named it.
    static func theme(for host: Host?) -> Palette? {
        let wanted = host?.effective.theme ?? ""
        guard !wanted.isEmpty else { return preferredTheme }
        // Asked for plainly: SwiftTerm's own colours, which is a different
        // answer from "whatever Settings says".
        guard wanted.caseInsensitiveCompare(Themes.systemName) != .orderedSame else { return nil }
        // A name nothing answers to — a palette renamed in the settings file
        // after a host was pointed at it — falls back rather than blanking
        // the terminal.
        return Themes.named(wanted) ?? preferredTheme
    }

    /// Paints the terminal. Nil leaves it as SwiftTerm made it, which is what
    /// the system palette means — there is no "undo" for installing colours,
    /// so choosing it back takes a new session.
    func apply(theme: Palette?) {
        guard let theme, theme.isComplete else { return }
        background = SwiftUI.Color(nsColor: NSColor(theme.background))
        view.installColors(theme.ansi.map {
            SwiftTerm.Color(red: UInt16($0.red) * 257, green: UInt16($0.green) * 257,
                            blue: UInt16($0.blue) * 257)
        })
        view.nativeBackgroundColor = NSColor(theme.background)
        view.nativeForegroundColor = NSColor(theme.foreground)
        view.caretColor = NSColor(theme.cursor)
        view.selectedTextBackgroundColor = NSColor(theme.selection)
    }

    /// Takes the host's settings again after the list has changed.
    ///
    /// A group's palette reaches every host under it, and the tabs already
    /// open are exactly the ones that should show that — the same reasoning
    /// that has the Settings picker repaint open terminals rather than
    /// waiting for the next connection. What is already on the screen is not
    /// touched; only the colours it is drawn in.
    func adopt(_ now: Host) {
        guard now.id == host?.id else { return }
        host = now
        apply(theme: Self.theme(for: now))
    }

    /// What is on screen, as a person would read it.
    var screen: String { String(decoding: view.getBufferAsData() as Data, as: UTF8.self) }

    /// The question most recently answered, kept until the session is
    /// through: an answer is typed before its echo arrives, so for an instant
    /// the screen still shows it being asked, and the watchdog is told not to
    /// ask it again.
    private var answered: String?

    func answerHostKey(accept: Bool) {
        if case .askingHostKey(let question) = state { answered = question }
        send(accept ? "yes\n" : "no\n")
        state = .connecting
    }

    func close() {
        watchdog?.cancel()
        view.terminate()
    }

    /// Watches for the two things that need the app rather than the terminal:
    /// a host-key question, and ssh's own log filling up.
    ///
    /// What it *decides* is `SessionProgress`; this is only the looking. Not
    /// private, so that a test can run the loop against a view it has fed by
    /// hand rather than a real `ssh` on a real pty. The log is read on every
    /// look and the screen only while `SessionProgress.watches` says so,
    /// because the screen is the whole history.
    func watch() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                self.ticks += 1
                self.readDiagnostics()
                if case .ended = self.state { return }
                guard SessionProgress.watches(self.state, connectedAt: self.connectedAt) else {
                    continue
                }

                self.looks += 1
                if let next = SessionProgress.next(
                    from: self.state, screen: self.screen, answered: self.answered)
                {
                    self.state = next
                    // Through, so any question after this is a new one, even
                    // one worded exactly like the last.
                    if next == .connected {
                        self.answered = nil
                        self.connectedAt = Date()
                    }
                }
            }
        }
    }

    private func readDiagnostics() {
        guard let text = try? String(contentsOfFile: logPath, encoding: .utf8) else { return }
        diagnostics = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        guard !title.isEmpty else { return }
        Task { @MainActor [weak self] in self?.title = title }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.watchdog?.cancel()
            self.readDiagnostics()
            self.state = .ended(code: exitCode, diagnostic: self.diagnostics)
        }
    }

    nonisolated func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        Task { @MainActor [weak self] in
            self?.state = .ended(code: nil, diagnostic: "ssh could not be started: \(error)")
        }
    }
}

extension Notification.Name {
    /// Settings changed the palette; every open terminal repaints.
    static let shellhandThemeChanged = Notification.Name("shellhand.themeChanged")
}

/// Turns a palette's colour into one AppKit can paint with.
extension NSColor {
    convenience init(_ rgb: RGB) {
        self.init(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255,
                  blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}

/// A terminal that takes the keyboard when it is put on screen.
///
/// Which is the whole of the question: a session is shown because it was just
/// opened or just switched to, and either way it is the thing about to be
/// typed in. Connecting and then having to click the terminal first is a step
/// nobody wants, and nothing else in the window is shown by being swapped in
/// like this, so there is nothing to steal focus from.
final class FocusingTerminalView: LocalProcessTerminalView {
    /// Cleared for the pane beside the one in front: splitting should not move
    /// you out of the terminal you were typing in.
    var takesKeyboardWhenShown = true

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard takesKeyboardWhenShown, let window else { return }
        // On the next turn of the run loop: during this one the responder
        // chain is still being rearranged by whatever added the view.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }
}

/// Every session the window holds.
///
/// The terminals. Which tab is in front is not kept here but in
/// `ContentView`'s `PaneTab`, so that the hosts or SFTP can be in front
/// instead and nothing has to encode "a session is selected but not shown".
@Observable
@MainActor
final class Sessions {
    private(set) var all: [TerminalSession] = []

    /// Every window's sessions, held weakly, for what quitting has to ask
    /// about: the app's delegate has no other way into a window's state.
    private static let everywhere = NSHashTable<Sessions>.weakObjects()

    /// Every session open in any window.
    static var inEveryWindow: [TerminalSession] { everywhere.allObjects.flatMap(\.all) }

    init() { Self.everywhere.add(self) }
    /// Which terminal is the current one. Not which tab is in front — that
    /// is `ContentView`'s `PaneTab`, because the hosts and an SFTP browser
    /// can be in front too, and neither is a session.
    var selected: UUID?

    // There is deliberately no `current` here. It read as "the session on
    // screen" and meant "the session whose id is selected", and once the
    // hosts could be in front those stopped being the same thing — which
    // put the wrong host in the inspector, the wrong name in the title bar
    // and the whole Terminal menu on a terminal nobody could see. What is
    // in front is `ContentView.pane`, and `frontSession` reads it.


    /// A session named short enough for a menu.
    ///
    /// The title is whatever the shell sends — `user@host:~/some/long/path` —
    /// which is too long for a menu and mostly the same across sessions on
    /// one machine. The machine and the tail of the path say which is which.
    static func shortTitle(of session: TerminalSession) -> String {
        shortTitle(host: session.host?.name, title: session.title)
    }

    /// The rule itself, over the only two things it reads.
    ///
    /// Separate from the overload above so that checking it costs nothing: a
    /// `TerminalSession` builds a 900×560 terminal view and registers a
    /// notification observer, which is a lot of machinery to stand up in
    /// order to test where a string gets cut.
    nonisolated static func shortTitle(host: String?, title: String) -> String {
        let name = host ?? "Local"
        // A session starts out titled with its host's name, which is no
        // place: a machine typed into ⌘K is named `root@127.0.0.1:1`, and its
        // tab read "root@127.0.0.1:1 — 1" until the shell said otherwise.
        guard title != name, let colon = title.lastIndex(of: ":") else { return name }
        let place = title[title.index(after: colon)...]
        return place.isEmpty ? name : "\(name) — \(place)"
    }

    @discardableResult
    func open(host: Host, argv: [String]) -> TerminalSession {
        let session = TerminalSession(title: host.name, host: host)
        all.append(session)
        selected = session.id
        session.start(argv: argv)
        return session
    }

    /// Hands every open session its host as the list now has it, so a palette
    /// chosen on a group shows up in the tabs that are already open.
    func repaint(from hosts: [Host]) {
        for session in all {
            guard let id = session.host?.id,
                  let now = hosts.first(where: { $0.id == id })
            else { continue }
            session.adopt(now)
        }
    }

    @discardableResult
    func openLocalShell() -> TerminalSession {
        let session = TerminalSession(title: "Local", host: nil)
        all.append(session)
        selected = session.id
        session.startLocalShell()
        return session
    }

    func close(_ session: TerminalSession) {
        session.close()
        all.removeAll { $0.id == session.id }
        if selected == session.id { selected = all.last?.id }
    }
}


extension TerminalSession.State {
    /// A word for the state, for reports and logs.
    var name: String {
        switch self {
        case .connecting: "connecting"
        case .connected: "connected"
        case .askingHostKey: "askingHostKey"
        case let .ended(code, _): "ended(\(code.map(String.init) ?? "signal"))"
        }
    }
}
