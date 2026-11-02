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
    /// The tab shown beside the one in front, which its tab says.
    let beside: PaneTab?
    let onPick: (PaneTab) -> Void
    /// A tab's × and its own menu, handed back to the window rather than
    /// acted on here — so the × asks first exactly as ⌘W does, where it used
    /// to close a live session on the spot.
    let actions: TabActions

    /// How wide the session tabs' part of the strip is, which they share.
    @State private var room: CGFloat = 0
    /// The strip's edges with tabs past them, which fade.
    @State private var hidden = Panes.HiddenEdges()

    var body: some View {
        // Named as the Window menu names them, a second of one name with its
        // number: two tabs on one host read "refuser" twice.
        let titles = sessions.titles
        // Each name measured, whole and in every spelling its tab may draw,
        // so the strip's room goes where it is needed and a name cut short
        // takes only what it draws; and a Needs you badge counted where one
        // is drawn.
        let steps = zip(sessions.all, titles).map { session, title in
            let parts = Panes.tabTitleParts(title)
            return Panes.tabTitleSteps(
                Panes.tabTitleCuts(parts.name, typed: session.host?.id.isEmpty == true),
                number: parts.number, width: Self.measured)
        }
        let widths = Panes.tabTitleWidths(
            room: room, needs: steps.map { $0.widths.first ?? 0 },
            extras: sessions.all.map { $0.status == .needsAnswer ? Panes.tabGap + TabButton.badgeWidth : 0 },
            cuts: steps.map { $0.widths })
        HStack(spacing: Panes.tabSpacing) {
            // The way back to the list, outside the scrolling: with the strip
            // full, a new tab scrolled into view pushed Hosts half off the
            // strip's edge.
            FixedTab(title: "Hosts", icon: "list.bullet",
                     selected: pane == .hosts) { onPick(.hosts) }
            ScrollViewReader { strip in
                ScrollView(.horizontal) {
                    HStack(spacing: Panes.tabSpacing) {
                        ForEach(Array(sessions.all.enumerated()), id: \.element.id) { index, session in
                            TabButton(
                                session: session,
                                title: titles[index],
                                cuts: steps[index].cuts,
                                titleWidth: widths[index],
                                selected: pane == .session(session.id),
                                beside: beside == .session(session.id),
                                hasOthers: sessions.all.count > 1,
                                actions: actions,
                                onShow: { onPick(.session(session.id)) })
                            .id(session.id)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
                // An edge with tabs past it fades, so a tab cut there reads as
                // more beyond rather than broken: at the window's default size
                // four tabs fill the strip, and the first was shown sheared,
                // square against Hosts, with nothing to say the strip scrolled.
                .onScrollGeometryChange(for: Panes.HiddenEdges.self) { geometry in
                    Panes.hiddenEdges(
                        offset: geometry.contentOffset.x, shown: geometry.containerSize.width,
                        content: geometry.contentSize.width)
                } action: { _, now in
                    hidden = now
                }
                .mask(StripFade(hidden: hidden))
                // The tab in front is scrolled into view: a session opened with
                // the strip full landed past its end, out of sight. A turn of
                // the loop later, since a new tab is not laid out in the update
                // that adds it.
                .onChange(of: pane) { _, now in
                    guard case let .session(id) = now else { return }
                    DispatchQueue.main.async { withAnimation { strip.scrollTo(id) } }
                }
                // And again once the tabs' widths settle. A tab opened with the
                // strip nearly full shares the room out anew, every title down
                // to its least, and the scroll above, measured against the
                // widths before, stopped short: the new tab's × out of sight,
                // now and then, in the build before the fade as well as after.
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.width } action: { _, _ in
                    guard case let .session(id) = pane else { return }
                    strip.scrollTo(id)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// A tab's name as its tab draws it, in the body font.
    private static func measured(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ]).width.rounded(.up)
    }
}

/// The strip's mask: opaque, but for a fade at each edge with tabs past it.
private struct StripFade: View {
    let hidden: Panes.HiddenEdges

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: hidden.leading ? 24 : 0)
            SwiftUI.Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: hidden.trailing ? 24 : 0)
        }
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
    /// Its name in the strip, told apart from another of the same name.
    let title: String
    /// The spellings its name may be drawn in, widest first, the number of
    /// a second of one name left out (`Panes.tabTitleSteps`).
    let cuts: [String]
    /// The most its name may take, the strip's room shared among the tabs.
    let titleWidth: CGFloat
    let selected: Bool
    /// Shown beside the tab in front, in a split.
    let beside: Bool
    /// Whether there is another tab for Close Other Tabs to close.
    let hasOthers: Bool
    let actions: TabActions
    let onShow: () -> Void

    static let needsYou = "Needs you"
    static let badgePadding: CGFloat = 6

    /// The Needs you badge's width, in the font it is drawn in.
    static let badgeWidth: CGFloat = (needsYou as NSString).size(withAttributes: [
        .font: NSFont.systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .semibold),
    ]).width.rounded(.up) + 2 * badgePadding

    var body: some View {
        Button {
            onShow()
        } label: {
            // Drawn with `Panes`'s parts, which the strip shares its room by.
            HStack(spacing: Panes.tabGap) {
                StatusMark(status: session.status)
                // The machine and the tail of the path, not the whole of
                // what the shell sent — and capped, because the tail can be
                // long too. Truncating in the middle keeps both the ends
                // that say which session this is: `prod-api-ch…/current`.
                // The number of a second of one name stays whole after it,
                // where cut as one "root@127.0.0.1:2 (2)" read "root…(2)".
                // The name is drawn in the first of its spellings that fits
                // (`Panes.tabTitleCuts`): a machine typed into ⌘K gives up
                // its user before its address, and an address whole parts
                // from between its dots — cut in the middle anywhere,
                // "root@127.0.0.1:2" read "root@….0.1:2", and without its
                // user "127….1:2", four dots in a row.
                HStack(spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        ForEach(Array(cuts.enumerated()), id: \.offset) { _, cut in
                            Text(cut)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Text(Panes.tabTitleParts(title).number)
                        .lineLimit(1)
                        .fixedSize()
                }
                // From the mark, where a name cut short stands: centred in
                // what it was given, the gap after the mark ran 7.5, 10.5 or
                // 11.5pt as the cut fell.
                .frame(maxWidth: titleWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                // A question in a tab behind this one was a yellow dot, and
                // the far end gives up on it after a couple of minutes.
                if session.status == .needsAnswer {
                    Text(Self.needsYou)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, Self.badgePadding)
                        .padding(.vertical, 1)
                        .background(SwiftUI.Color.orange.opacity(0.18), in: Capsule())
                }
                Button { actions.close(session) } label: {
                    Image(systemName: "xmark").font(.caption2)
                        .frame(width: Panes.tabClose)
                }
                .buttonStyle(.plain)
                // Which tab, not just "close": a strip of them all reading
                // "close this tab" says nothing about which one you are on.
                .accessibilityLabel("Close \(title)")
                .help("Close this tab")
            }
            .padding(.horizontal, Panes.tabPadding)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            // Outlined while shown beside the tab in front, so a split says
            // which tab is on which side: it read like any tab behind.
            .overlay {
                if beside {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(SwiftUI.Color.accentColor.opacity(0.6), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        // The tab's name whole, for the times the strip had to cut it, and
        // what the shell sent where that says more (`Panes.tabHelp`): a
        // truncated name should always be readable somewhere.
        .help(Panes.tabHelp(title: title, sent: session.title))
        // Its state in words as well as its name: a colour says nothing to
        // VoiceOver, and the symbol only as much as its shape.
        .accessibilityLabel("\(title), \(session.status.spoken)\(beside ? ", shown beside" : "")")
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
/// does not shift as the state moves on. The strip's, and the inspector's
/// Open now's, which drew every tab alike, live or never connected.
struct StatusMark: View {
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
                // About the middle while nothing has run, since there is
                // nothing under it to read, its top kept where it is as one
                // card gives way to another; once something has, in a band
                // across the top, so the session's last output stays in sight.
                .overlay(alignment: .top) {
                    if session.status.isBeforeAnything {
                        CardPlacement { said }
                    } else {
                        said
                    }
                }
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

/// What every card over a terminal, and SFTP's over a side it cannot list,
/// is drawn with.
enum Card {
    /// The most a card stands across over a terminal with nothing on it, or
    /// a side with nothing to list.
    static let width: CGFloat = 480

    /// What a card is drawn on: the window's own ground, opaque, so its words
    /// read as they do anywhere else in the window. A material let the
    /// terminal through, and over a black one came out mid-grey, 147, the red
    /// headline about 1.3:1 against it and the secondary words 2.9:1.
    static let ground = SwiftUI.Color(nsColor: .windowBackgroundColor)

    /// A hairline round it, so a card still reads as one on a ground the
    /// same as its own: on SFTP's white side, the card went and only its
    /// words stood, where the material had drawn it 237 on 255.
    static let edge = SwiftUI.Color(nsColor: .separatorColor)

    /// The secondary words — where a connection is going, what a refusal
    /// means — in the secondary label colour as itself. As `.secondary`, the
    /// material the card was drawn on then drew them vibrant: over a black
    /// terminal, darker than the card's headline and ssh's line, 20 against
    /// 44 and 41.
    static let secondary = SwiftUI.Color(nsColor: .secondaryLabelColor)

    /// How far above the middle of a pane with nothing on it a card's top
    /// stands: about half the refusal's height, so the card that stays sits
    /// about in the middle. Nonisolated, as `CardPlacement` reads it from a
    /// layout's own calls.
    nonisolated static let rise: CGFloat = 80

    /// The most a card's centre stands below that middle before the card
    /// rises: every card at a pane's full width keeps one top, and a taller
    /// one beside another tab hangs no lower than this.
    nonisolated static let sink: CGFloat = 24

    /// The slot a headline's icon stands in, as wide as the spinner and every
    /// mark are laid out in a headline.
    static let mark: CGFloat = 16
}

/// A card over a pane with nothing on it, its top a set way above the middle
/// rather than the card centred: centred, a card that gave way to a taller
/// or shorter one moved, a refusal's top 28pt above the connecting card's it
/// replaced, 154pt tall against 98. It rises from there only as far as
/// keeps its centre no more than `Card.sink` below the middle: held to its
/// place, a refusal beside another tab, its buttons stacked and 292pt tall,
/// stood with its centre 78pt under the middle, 246.5pt of terminal above it
/// and 90 below; and a card taller than twice the way up, centred instead,
/// moved the full-width refusal 9pt — 154pt tall, but 178 with its margins.
/// Higher still only where the card would otherwise run past the foot.
struct CardPlacement: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let across = ProposedViewSize(width: bounds.width, height: nil)
        for card in subviews {
            let height = card.sizeThatFits(across).height
            let top = max(bounds.minY, min(
                bounds.midY - Card.rise, bounds.midY - height / 2 + Card.sink, bounds.maxY - height))
            card.place(at: CGPoint(x: bounds.midX, y: top), anchor: .top, proposal: across)
        }
    }
}

/// A card's headline, its icon in a slot of one width: in its own, the words
/// started 24 after a circle, 24.5 after the spinner and 25.5 after the
/// triangle, and moved as one card gave way to the next.
struct CardHeadline: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
        } icon: {
            configuration.icon.frame(width: Card.mark)
        }
        // Its own style, or it would be drawn in this one again.
        .labelStyle(.titleAndIcon)
    }
}

extension LabelStyle where Self == CardHeadline {
    static var cardHeadline: CardHeadline { CardHeadline() }
}

/// Where a connection is going and how long it has been at it, over a
/// terminal that has nothing on it yet: connecting used to be a blank screen
/// that looked the same as one that had hung.
private struct ConnectingCard: View {
    let session: TerminalSession

    var body: some View {
        // Laid out as the ended card that takes its place is, the spinner
        // where that one's mark is: centred, 440 wide in 20pt margins, the
        // card jumped to another shape as the connection failed, and beside
        // another tab its line lost the room it needed.
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(SessionStatus.connecting.headline(for: session.host?.name))
            } icon: {
                ProgressView().controlSize(.small)
            }
            .labelStyle(.cardHeadline)
            .font(.headline)
            TimelineView(.periodic(from: session.startedAt ?? .now, by: 1)) { context in
                let seconds = Int(context.date.timeIntervalSince(session.startedAt ?? context.date))
                // On one line where it fits, and a part to a line where it
                // does not: beside another tab it broke inside the port. It
                // is asked to fit at the longest it will be, so the choice
                // holds while the seconds count: asked each second, one line
                // at 9 s broke into three at 10, and the card jumped.
                ViewThatFits(in: .horizontal) {
                    Text(SessionStatus.connectingLine(
                        destination: destination, through: session.route.through,
                        seconds: SessionStatus.longestWait))
                        .hidden()
                        .overlay(alignment: .leading) {
                            Text(SessionStatus.connectingLine(
                                destination: destination, through: session.route.through,
                                seconds: seconds))
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(SessionStatus.connectingLines(
                            destination: destination, through: session.route.through,
                            seconds: seconds).enumerated()), id: \.offset) { _, part in
                            Text(part).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .font(.callout.monospaced())
                .foregroundStyle(Card.secondary)
            }
            // ⌘. is the Terminal menu's, where the keys live.
            Button("Stop Connecting") { session.stopConnecting() }
                .controlSize(.small)
        }
        .cardChrome()
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
                .labelStyle(.cardHeadline)
                .font(.headline)
                .foregroundStyle(status.isFailure ? SwiftUI.Color.red : SwiftUI.Color.primary)

            // What ssh wrote to its own log, which -E keeps out of the
            // terminal: the refusal, the wrong key, the timeout. As tall as
            // its lines, as the sentence under it is: beside another tab at
            // 1220pt it was held to one line, "port 2…", its "Connection
            // refused" cut, while a narrower side wrapped it whole.
            if !said.isEmpty {
                Text(said)
                    .font(.caption.monospaced())
                    .selectable(said)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            if !meaning.isEmpty {
                Text(meaning)
                    .font(.callout)
                    .foregroundStyle(Card.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Side by side where they fit, one above another where they do
            // not: beside another tab they were cut to "Recon…", "Edit H…".
            ViewThatFits(in: .horizontal) {
                HStack { buttons(stacked: false) }
                // One above another at one width, the widest's: each at its
                // own, they stood ragged, 76, 77 and 72pt beside another tab.
                VStack(alignment: .leading) { buttons(stacked: true) }
                    .fixedSize(horizontal: true, vertical: false)
            }
            .controlSize(.small)
        }
        .cardChrome(maxWidth: status.isBeforeAnything ? Card.width : .infinity)
    }

    @ViewBuilder
    private func buttons(stacked: Bool) -> some View {
        if session.host != nil {
            if status.isFailure {
                Button { actions.reconnect(session) } label: {
                    Text("Reconnect").stackedButtonLabel(stacked)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { actions.reconnect(session) } label: {
                    Text("Reconnect").stackedButtonLabel(stacked)
                }
            }
        }
        if let onEdit {
            Button(action: onEdit) { Text("Edit Host…").stackedButtonLabel(stacked) }
        }
        Button { actions.close(session) } label: {
            Text("Close Tab").stackedButtonLabel(stacked)
        }
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
                        .selectable(asked.fingerprint)
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
            .selectable(question)
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

extension View {
    /// A card's ground and margins, one for every card: the connecting card
    /// was 440 wide in 20pt margins and gave way to an ended card 480 wide in
    /// 14 and 12, and SFTP's was 460 in 24.
    func cardChrome(maxWidth: CGFloat = Card.width) -> some View {
        padding(14)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(Card.ground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Card.edge))
            .padding(12)
    }

    /// A button's label taking its stack's width where the buttons stand one
    /// above another, so they stand at one width — the widest's, the stack
    /// held to it — rather than each at its own.
    func stackedButtonLabel(_ stacked: Bool) -> some View {
        frame(maxWidth: stacked ? .infinity : nil)
    }
}
