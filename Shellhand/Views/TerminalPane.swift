import SwiftTerm
import SwiftUI

/// The hosts, which are always there, then the open sessions.
///
/// A tab is as wide as its label, so what the label says is what decides
/// whether a handful of sessions fill the strip and push the rest behind a
/// horizontal scroll nobody finds. It is not the shell's title.
///
/// **Hosts leads, and cannot be closed.** It is what the window is for, and
/// having it here is what makes "show me the list" a thing you can see and
/// click rather than a mode set behind your back.
struct SessionTabBar: View {
    let sessions: Sessions
    let pane: PaneTab
    let onPick: (PaneTab) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                FixedTab(title: "Hosts", icon: "list.bullet",
                         selected: pane == .hosts) { onPick(.hosts) }
                ForEach(sessions.all) { session in
                    TabButton(
                        session: session, sessions: sessions,
                        selected: pane == .session(session.id),
                        onShow: { onPick(.session(session.id)) })
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.never)
        .background(.bar)
    }
}

/// The tab that is always there and cannot be closed: the hosts.
///
/// No close button and no status dot, which is what tells it apart from the
/// sessions beside it at a glance — those are about a connection, and this
/// is not one.
private struct FixedTab: View {
    let title: String
    let icon: String
    let selected: Bool
    let onShow: () -> Void

    var body: some View {
        Button(action: onShow) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                selected
                    ? SwiftUI.Color.accentColor.opacity(0.22)
                    : SwiftUI.Color.secondary.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct TabButton: View {
    let session: TerminalSession
    let sessions: Sessions
    let selected: Bool
    let onShow: () -> Void

    var body: some View {
        Button {
            onShow()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color(session.state))
                    .frame(width: 6, height: 6)
                // The machine and the tail of the path, not the whole of
                // what the shell sent — and capped, because the tail can be
                // long too. Truncating in the middle keeps both the ends
                // that say which session this is: `prod-api-ch…/current`.
                Text(Sessions.shortTitle(of: session))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    sessions.close(session)
                } label: {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.plain)
                // Which tab, not just "close": a strip of them all reading
                // "close this tab" says nothing about which one you are on.
                .accessibilityLabel("Close \(Sessions.shortTitle(of: session))")
                .help("Close this tab")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        // The whole of what the shell sent, for the times the label had to
        // cut it: a truncated name should always be readable somewhere.
        .help(session.title)
        .accessibilityLabel(session.title)
    }

    /// Keyed off the strip's own selection, not `Sessions.selected`: with
    /// the hosts tab up no session tab is the one in front, though `Sessions`
    /// still holds the one you would come back to.
    private var background: SwiftUI.Color {
        selected
            ? SwiftUI.Color.accentColor.opacity(0.22)
            : SwiftUI.Color.secondary.opacity(0.1)
    }

    // SwiftTerm has a Color of its own, for terminal colours.
    private func color(_ state: TerminalSession.State) -> SwiftUI.Color {
        switch state {
        case .connecting: SwiftUI.Color.orange
        case .connected: SwiftUI.Color.green
        case .askingHostKey: SwiftUI.Color.yellow
        case let .ended(code, _): (code == 0) ? SwiftUI.Color.secondary : SwiftUI.Color.red
        }
    }
}

/// One session's terminal, with the things ssh says for itself shown as the
/// app's own rather than left in the scrollback.
struct TerminalPane: View {
    let session: TerminalSession
    let sessions: Sessions
    /// Whether this is the pane in front. The one beside it is shown, not
    /// moved into.
    var isFront = true
    /// Reconnecting rebuilds the argv rather than reusing it: the host may
    /// have been edited, here or in the TUI, since this tab was opened.
    let onReconnect: (Host) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if session.findOpen {
                FindBar(session: session)
                Divider()
            }
            TerminalRepresentable(session: session, takesKeyboard: isFront)
                // Identity by session, or SwiftUI keeps the first terminal it
                // was given: the pane sits in the same place whichever tab is
                // in front, so without this nothing tells it to swap the view
                // underneath, and every tab showed the first session.
                .id(session.id)
                .overlay(alignment: .top) { banner }
        }
        // A host key question is a decision, so dismissing the sheet any other
        // way answers no rather than letting the session hang on a prompt
        // nobody can see.
        .sheet(isPresented: Binding(
            get: { isAsking },
            set: { shown in if !shown, isAsking { session.answerHostKey(accept: false) } }
        )) { hostKeySheet }
    }

    private var isAsking: Bool {
        if case .askingHostKey = session.state { return true }
        return false
    }

    @ViewBuilder
    private var banner: some View {
        if case let .ended(code, diagnostic) = session.state {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(ended(code))
                } icon: {
                    Image(systemName: code == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                }
                .font(.callout.bold())

                // What ssh wrote to its own log, which -E keeps out of the
                // terminal: the refusal, the wrong key, the timeout.
                if !diagnostic.isEmpty {
                    Text(diagnostic)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if let host = session.host {
                        Button("Reconnect") {
                            sessions.close(session)
                            onReconnect(host)
                        }
                    }
                    Button("Close") { sessions.close(session) }
                }
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(12)
        }
    }

    private var hostKeySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("This host is not in your known_hosts", systemImage: "key.radiowaves.forward")
                .font(.headline)
            if case let .askingHostKey(question) = session.state {
                Text(question)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: 460, alignment: .leading)
            }
            Text("Accepting adds it to your known_hosts, exactly as answering ssh would.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Reject") { session.answerHostKey(accept: false) }
                Button("Accept") { session.answerHostKey(accept: true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func ended(_ code: Int32?) -> String {
        switch code {
        case .some(0): "The session ended."
        case let .some(value): "The session ended with status \(value)."
        case nil: "The session ended."
        }
    }
}

struct TerminalRepresentable: NSViewRepresentable {
    let session: TerminalSession
    let takesKeyboard: Bool

    // Set before the view is in a window, which is where it decides.
    func makeNSView(context: Context) -> FocusingTerminalView {
        session.view.takesKeyboardWhenShown = takesKeyboard
        return session.view
    }

    func updateNSView(_ nsView: FocusingTerminalView, context: Context) {
        nsView.takesKeyboardWhenShown = takesKeyboard
    }
}
