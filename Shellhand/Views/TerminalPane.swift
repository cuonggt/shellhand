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
    /// A tab's × and its own menu, handed back to the window rather than
    /// acted on here — so the × asks first exactly as ⌘W does, where it used
    /// to close a live session on the spot.
    let actions: TabActions

    var body: some View {
        ScrollViewReader { strip in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    FixedTab(title: "Hosts", icon: "list.bullet",
                             selected: pane == .hosts) { onPick(.hosts) }
                    ForEach(sessions.all) { session in
                        TabButton(
                            session: session,
                            selected: pane == .session(session.id),
                            hasOthers: sessions.all.count > 1,
                            actions: actions,
                            onShow: { onPick(.session(session.id)) })
                        .id(session.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            // The tab in front is scrolled into view: a session opened with
            // the strip full landed past its end, out of sight. A turn of the
            // loop later, since a new tab is not laid out in the update that
            // adds it.
            .onChange(of: pane) { _, now in
                guard case let .session(id) = now else { return }
                DispatchQueue.main.async { withAnimation { strip.scrollTo(id) } }
            }
        }
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

/// What a tab's × and its own menu do to the session the tab is on.
///
/// **Each is handed its session**, the way a row's menu is handed its host:
/// a right-click on a tab does not bring it in front, so a menu that read the
/// session in front would reconnect or close some other tab. The decisions —
/// what Duplicate opens, whether SFTP can reach the machine, what closing
/// asks — are `Panes` and `Closing`; the window wires them in.
struct TabActions {
    var reconnect: (TerminalSession) -> Void = { _ in }
    var duplicate: (TerminalSession) -> Void = { _ in }
    var openSFTP: (TerminalSession) -> Void = { _ in }
    var close: (TerminalSession) -> Void = { _ in }
    var closeOthers: (TerminalSession) -> Void = { _ in }
    /// Whether Duplicate has anything to open — not for a host since deleted.
    var canDuplicate: (TerminalSession) -> Bool = { _ in false }
    /// Whether the session's machine can be opened over SFTP — a saved host,
    /// not a local shell or one typed into ⌘K.
    var canOpenSFTP: (TerminalSession) -> Bool = { _ in false }
}

private struct TabButton: View {
    let session: TerminalSession
    let selected: Bool
    /// Whether there is another tab for Close Other Tabs to close.
    let hasOthers: Bool
    let actions: TabActions
    let onShow: () -> Void

    var body: some View {
        Button {
            onShow()
        } label: {
            HStack(spacing: 6) {
                StatusMark(status: session.status)
                // The machine and the tail of the path, not the whole of
                // what the shell sent — and capped, because the tail can be
                // long too. Truncating in the middle keeps both the ends
                // that say which session this is: `prod-api-ch…/current`.
                Text(Sessions.shortTitle(of: session))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
                    .fixedSize(horizontal: false, vertical: true)
                // A question in a tab behind this one was a yellow dot, and
                // the far end gives up on it after a couple of minutes.
                if session.status == .needsAnswer {
                    Text("Needs you")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(SwiftUI.Color.orange.opacity(0.18), in: Capsule())
                }
                Button { actions.close(session) } label: {
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
        // Its state in words as well as its name: a colour says nothing to
        // VoiceOver, and the symbol only as much as its shape.
        .accessibilityLabel("\(Sessions.shortTitle(of: session)), \(session.status.spoken)")
        // Reconnecting and closing go through the same questions ⌘R and ⌘W
        // put; Duplicate is ⌘T for this tab rather than the one in front.
        .contextMenu {
            Button("Reconnect") { actions.reconnect(session) }
                .disabled(session.host == nil)
            Button("Duplicate") { actions.duplicate(session) }
                .disabled(!actions.canDuplicate(session))
            Button("SFTP") { actions.openSFTP(session) }
                .disabled(!actions.canOpenSFTP(session))
            Divider()
            Button("Close Tab") { actions.close(session) }
            Button("Close Other Tabs") { actions.closeOthers(session) }
                .disabled(!hasOthers)
        }
    }

    /// Keyed off the strip's own selection, not `Sessions.selected`: with
    /// the hosts tab up no session tab is the one in front, though `Sessions`
    /// still holds the one you would come back to.
    private var background: SwiftUI.Color {
        selected
            ? SwiftUI.Color.accentColor.opacity(0.22)
            : SwiftUI.Color.secondary.opacity(0.1)
    }

}

/// A tab's state as a shape: a spinner while connecting, the green dot once
/// through, and a symbol for everything else — `SessionStatus.symbol`.
/// Never a colour alone, and in a box of one size, so the name beside it
/// does not shift as the state moves on.
private struct StatusMark: View {
    let status: SessionStatus

    var body: some View {
        SwiftUI.Group {
            switch status {
            case .connecting:
                ProgressView().controlSize(.mini)
            case .connected:
                Circle().fill(SwiftUI.Color.green).frame(width: 7, height: 7)
            default:
                Image(systemName: status.symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }

    // SwiftTerm has a Color of its own, for terminal colours.
    private var tint: SwiftUI.Color {
        switch status {
        case .needsAnswer: .orange
        case .couldNotConnect, .lost: .red
        default: .secondary
        }
    }
}

/// One session's terminal, with the things ssh says for itself shown as the
/// app's own rather than left in the scrollback.
struct TerminalPane: View {
    /// Enough to read as deliberate, and small enough not to cost a column:
    /// the terminal sizes itself from what is left after this.
    static let inset: CGFloat = 8

    let session: TerminalSession
    /// Whether this is the pane in front. The one beside it is shown, not
    /// moved into.
    var isFront = true
    /// Reconnect and Close Tab, through the window as the tab's own menu
    /// goes: reconnecting puts the new session in this one's place and
    /// builds its argv again, since the host may have been edited.
    let actions: TabActions
    /// Edit Host… after a failure, for a host in the list; nil leaves it out.
    var onEdit: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if session.findOpen {
                FindBar(session: session)
                Divider()
            }
            TerminalRepresentable(session: session, takesKeyboard: isFront)
                // Room inside the terminal, after Termius: the background
                // runs edge to edge and the text is inset from it.
                //
                // **Three modifiers and each does a job.** `padding` insets
                // the terminal; the `frame` makes what holds it fill the
                // pane, so the colour reaches the edges rather than stopping
                // where the last whole cell does; `background` then paints
                // that whole area. Top-leading, or the leftover from
                // rounding to whole cells is split either side and the text
                // sits off-centre from the inset.
                //
                // Done here rather than in a container `NSView` around the
                // terminal, which was the first attempt: a plain wrapper
                // takes everything offered and painted over the tab strip.
                .padding(TerminalPane.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(session.background)
                // Identity by session, or SwiftUI keeps the first terminal it
                // was given: the pane sits in the same place whichever tab is
                // in front, so without this nothing tells it to swap the view
                // underneath, and every tab showed the first session.
                .id(session.id)
                // In the middle while nothing has run, since there is nothing
                // under it to read; once something has, in a band across the
                // top, so the session's last output stays in sight.
                .overlay(alignment: session.status.isBeforeAnything ? .center : .top) { said }
        }
        // A host key question is a decision, so dismissing the sheet any other
        // way answers no rather than letting the session hang on a prompt
        // nobody can see. By item, so that the question answered stays on
        // the sheet while it goes, rather than the sheet emptying first.
        .sheet(item: Binding(
            get: { question.map(Question.init) },
            set: { shown in if shown == nil, question != nil { session.answerHostKey(accept: false) } }
        )) { asked in
            HostKeySheet(session: session, question: asked.text)
        }
    }

    private struct Question: Identifiable {
        let text: String
        var id: String { text }
    }

    private var question: String? {
        if case let .askingHostKey(question) = session.state { return question }
        return nil
    }

    @ViewBuilder
    private var said: some View {
        let status = session.status
        switch status {
        case .connecting:
            ConnectingCard(session: session)
        case .stopped, .couldNotConnect, .lost, .ended:
            EndedCard(session: session, status: status, actions: actions,
                      onEdit: status == .couldNotConnect ? onEdit : nil)
        case .connected, .needsAnswer:
            EmptyView()
        }
    }
}

/// Where a connection is going and how long it has been at it, over a
/// terminal that has nothing on it yet: connecting used to be a blank screen
/// that looked the same as one that had hung.
private struct ConnectingCard: View {
    let session: TerminalSession

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(SessionStatus.connecting.headline(for: session.host?.name))
                .font(.headline)
            TimelineView(.periodic(from: session.startedAt ?? .now, by: 1)) { context in
                Text(SessionStatus.connectingLine(
                    destination: destination, through: session.route.through,
                    seconds: Int(context.date.timeIntervalSince(session.startedAt ?? context.date))))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            // ⌘. is the Terminal menu's, where the keys live.
            Button("Stop Connecting") { session.stopConnecting() }
                .controlSize(.small)
        }
        .padding(20)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(20)
    }

    /// `Host.destinationLine`, unless the name already is it: a machine typed
    /// into ⌘K is named as it was typed.
    private var destination: String {
        guard let host = session.host else { return "" }
        return host.id.isEmpty ? "" : host.destinationLine
    }
}

/// How a session ended, in words: ssh's own line, what it means where that
/// is known, and what can be done next.
///
/// It said "The session ended with status 255." for every failure ssh has —
/// the words typing `exit` got too, short of the number — so a refused
/// connection and a clean logout read alike.
private struct EndedCard: View {
    let session: TerminalSession
    let status: SessionStatus
    let actions: TabActions
    let onEdit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(status.headline(for: session.host?.name), systemImage: status.symbol)
                .font(.headline)
                .foregroundStyle(status.isFailure ? SwiftUI.Color.red : SwiftUI.Color.primary)

            // What ssh wrote to its own log, which -E keeps out of the
            // terminal: the refusal, the wrong key, the timeout.
            if !said.isEmpty {
                Text(said)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            if !meaning.isEmpty {
                Text(meaning)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if session.host != nil {
                    if status.isFailure {
                        Button("Reconnect") { actions.reconnect(session) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Reconnect") { actions.reconnect(session) }
                    }
                }
                if let onEdit { Button("Edit Host…", action: onEdit) }
                Button("Close Tab") { actions.close(session) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: status.isBeforeAnything ? 480 : .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }

    private var said: String {
        if case let .ended(_, diagnostic) = session.state { return diagnostic }
        return ""
    }

    /// Nothing lost, what ssh's line means, and the far end's own status —
    /// whichever of them there is.
    private var meaning: String {
        var parts: [String] = []
        if let reassurance = status.reassurance { parts.append(reassurance) }
        if status.isFailure, let reason = SessionEnding.reason(said) { parts.append(reason) }
        if case let .ended(code, _) = session.state, status == .ended,
           let note = SessionStatus.exitNote(code)
        {
            parts.append(note)
        }
        return parts.joined(separator: " ")
    }
}

/// ssh asking whether to trust a machine it has not met: which machine, by
/// the name you know it by and where it sits on the way, and the fingerprint
/// to compare — with the whole of what ssh asked a click away.
///
/// It was "This host is not in your known_hosts" over ssh's question as it
/// stood, which in a jump chain did not say which hop was asking, and
/// neither Return nor Esc answered it.
private struct HostKeySheet: View {
    let session: TerminalSession
    let question: String

    var body: some View {
        let asked = HostKey.asked(in: question)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(asked == nil ? "ssh is asking about a host key" : "First connection to \(who(asked))")
                        .font(.headline)
                    if let asked {
                        Text(whereItIs(asked))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let asked {
                Text("ssh hasn't met this machine before, so it can't yet tell whether it is "
                    + "really \(who(asked)). Compare the fingerprint below with one you trust: "
                    + "from the machine's console, or from whoever runs it.")
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(asked.keyType) key fingerprint")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(asked.fingerprint)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                DisclosureGroup("What ssh asked") { asWritten }
                    .font(.caption)
            } else {
                // Worded some other way than an unknown host's question, so
                // all of it, as ssh wrote it.
                asWritten
            }
            Text("Trusting it adds the key to your known_hosts, as answering yes to ssh would.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Don't Connect") { session.answerHostKey(accept: false) }
                    .keyboardShortcut(.cancelAction)
                Button("Trust and Connect") { session.answerHostKey(accept: true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: DialogSize.small)
    }

    private var asWritten: some View {
        Text(question)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The machine by the name the list gives it where the route knows it,
    /// and as ssh named it otherwise.
    private func who(_ asked: HostKey.Asked?) -> String {
        guard let asked else { return "" }
        if let index = session.route.index(asked: asked.host) { return session.route.stops[index].name }
        return Route.split(asked.host).name
    }

    /// "192.0.2.10, port 22 · the first of 2 hops on the way to db-01".
    private func whereItIs(_ asked: HostKey.Asked) -> String {
        let (name, port) = Route.split(asked.host)
        let place = "\(name), port \(port)"
        guard let index = session.route.index(asked: asked.host),
              let position = session.route.position(of: index)
        else { return place }
        return "\(place) · \(position)"
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
