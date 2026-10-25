import AppKit
import Foundation
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
    enum State: Equatable {
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
    private(set) var host: Host?

    private let logPath: String
    private var watchdog: Task<Void, Never>?
    private var themeObserver: (any NSObjectProtocol)?

    init(title: String, host: Host?) {
        self.title = title
        self.host = host
        self.logPath = NSTemporaryDirectory() + "shellhand-ssh-\(UUID().uuidString).log"
        view.processDelegate = self
        view.font = NSFont.monospacedSystemFont(
            ofSize: Self.preferredFontSize, weight: .regular)
        apply(theme: Self.theme(for: host))
        // Settings is a scene of its own and cannot reach the sessions a
        // window holds, so the change is announced and each one listens.
        watchTheme()
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

    isolated deinit {
        // A block observer is held by the centre until it is handed back —
        // `weak self` keeps the session from being pinned, but the block
        // itself would outlive every tab that was ever opened.
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }

    /// Starts ssh with the argv the core built, plus the one option the app
    /// adds for itself.
    func start(argv: [String]) {
        state = .connecting
        diagnostics = ""
        try? FileManager.default.removeItem(atPath: logPath)
        // nil rather than an empty array: SwiftTerm reads nil as "inherit",
        // and a session with no TERM or PATH is not a session.
        view.startProcess(executable: "/usr/bin/ssh", args: ["-E", logPath] + argv,
                          environment: nil)
        watch()
    }

    /// A local shell, for a window that wants one.
    func startLocalShell() {
        state = .connected
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(executable: shell, execName: "-" + (shell as NSString).lastPathComponent)
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

    func resetFontSize() {
        view.font = NSFont.monospacedSystemFont(ofSize: Self.preferredFontSize, weight: .regular)
    }

    /// What Settings asks new sessions to start at.
    static var preferredFontSize: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "defaultFontSize")
        return stored > 0 ? CGFloat(stored) : 12
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

    func answerHostKey(accept: Bool) {
        send(accept ? "yes\n" : "no\n")
        state = .connecting
    }

    func close() {
        watchdog?.cancel()
        view.terminate()
    }

    /// Watches for the two things that need the app rather than the terminal:
    /// a host-key question, and ssh's own log filling up.
    private func watch() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                self.ticks += 1
                self.readDiagnostics()
                if case .ended = self.state { return }

                let screen = self.screen
                // Only the end of the buffer counts. ssh writes the question
                // last and then waits, so a match anywhere else is a question
                // that has already been answered — and matching the whole
                // buffer left the session stuck on a prompt that was gone.
                if Self.isWaitingForHostKey(screen) {
                    if case .askingHostKey = self.state {} else {
                        self.state = .askingHostKey(Self.hostKeyQuestion(in: screen))
                    }
                } else if !screen.isEmpty {
                    switch self.state {
                    case .connecting, .askingHostKey:
                        // Anything else from the far side means we are through.
                        self.state = .connected
                    default:
                        break
                    }
                }
            }
        }
    }

    private func readDiagnostics() {
        guard let text = try? String(contentsOfFile: logPath, encoding: .utf8) else { return }
        diagnostics = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the last thing on screen is ssh waiting for an answer.
    private static func isWaitingForHostKey(_ screen: String) -> Bool {
        let tail = screen
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(2)
        return tail.contains { $0.contains("continue connecting (yes/no") }
    }

    /// The fingerprint and the question, without the rest of the screen.
    private static func hostKeyQuestion(in screen: String) -> String {
        let lines = screen.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let end = lines.lastIndex(where: { $0.contains("continue connecting (yes/no") }) else {
            return screen
        }
        let start = lines[..<end].lastIndex { $0.contains("authenticity of host") } ?? max(0, end - 4)
        return lines[start...end].filter { !$0.isEmpty }.joined(separator: "\n")
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
        let name = session.host?.name ?? "Local"
        guard let colon = session.title.lastIndex(of: ":") else { return name }
        let place = session.title[session.title.index(after: colon)...]
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

    func closeAll() {
        all.forEach { $0.close() }
        all.removeAll()
        selected = nil
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
