import SwiftUI

/// What this host connects with, where each part of it came from, and what is
/// already going on with it.
///
/// **One shape, and it lives in the inspector.** There were two: the main
/// panel got the lot while the inspector asked for `compact`, which dropped
/// the ssh line and the open sessions — because at 300pt a quoted command
/// wraps into a paragraph, and because showing the same thing in both at once
/// was simply the same view twice. The pane shows the list now, so this is
/// the only place a host is described and there is nothing to repeat.
///
/// The command stays, wrapping and all. It is what you paste into a ticket
/// when a connection misbehaves, and the alternative to a wrapped line here
/// is not having it anywhere — the inspector widens to 420pt, and `Copy`
/// sits in its header where the length cannot push it below the fold.
struct HostDetailView: View {
    let store: HostStore
    let host: Host
    /// What is open, for the sessions already on this host.
    var sessions: Sessions?
    let onConnect: (Host) -> Void
    /// Bringing one of the sessions in "Open now" to the front.
    var onShowSession: (UUID) -> Void = { _ in }
    /// The session in front, which Open now says rather than offers to show.
    var inFront: UUID? = nil
    let onEdit: (Host) -> Void

    /// The palette, changed from here rather than through the editor.
    ///
    /// **The one control in a grid of facts, and it earns the place**: a
    /// palette is the setting people change most and the only one whose
    /// effect they want to see straight away, on the tab already open. The
    /// rest of this grid describes a host; this row changes one.
    ///
    /// The same picker the editor's Advanced tab has, down to the sentence
    /// labelling "inherit" — `Effective.inheritedPalette`, so the two cannot
    /// come to say different things about the same host.
    ///
    /// **Laid out as the rows around it are**: the label level with the first
    /// line, and what reaches the host as the palette with "from Production"
    /// in grey beside or under it. The sentence wrapped to "Gruvbox Dark /
    /// from / Production" in full-size type, the label centred against it.
    @ViewBuilder private var colours: some View {
        GridRow(alignment: .top) {
            Text("Colours")
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            PaletteChoice(
                chosen: host.theme, inherited: preview.effective.inheritedPalette,
                inheritedPalette: TerminalSession.palette(named: preview.effective.theme),
                inheritedParts: preview.effective.inheritedPaletteParts,
                onChoose: { choose(palette: $0) })
        }
    }

    /// Its own choice, what reaches it from a group with the group's name, or
    /// ssh's default — in the editors' words, `Effective.agent`. A group's
    /// inspector had this row and a host's did not.
    private var agent: ValueRow {
        let (value, from) = Effective.agent(
            host.effective.forwardAgent, from: host.effective.forwardAgentFrom)
        return ValueRow("Agent forwarding", value, from: from)
    }

    /// The host as previewed: its own palette left out, so the preview's
    /// says what inheriting would give. With it in, a host with a palette of
    /// its own had its "inherit" row named after that same palette.
    nonisolated static func inheriting(_ host: Host) -> Host {
        var asked = host
        asked.theme = ""
        return asked
    }

    /// Saves the choice and nothing else.
    ///
    /// Read again from the snapshot rather than saving the copy this view is
    /// drawing, which may be older than it looks — the same reason
    /// `learnOS` does. A save is what repaints the sessions already open, so
    /// the terminal changes colour as the picker closes: that is
    /// `Sessions.repaint(from:)` on the host list changing, and it was built
    /// for a group's palette reaching the tabs beneath it.
    private func choose(palette: String) {
        guard palette != host.theme else { return }
        Task {
            guard var now = store.snapshot.hosts.first(where: { $0.id == host.id }) else { return }
            now.theme = palette
            _ = await store.save(now)
        }
    }

    /// What ssh would be given, worked out by `Core` the same way the host
    /// editor's preview line is — so the two can never disagree about what
    /// this host runs.
    @State private var preview = HostPreview()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let alias = host.effective.aliasElsewhere {
                    Label {
                        Text("Your ssh config has a Host \(alias.name) going to \(alias.addr):\(alias.port), "
                            + "so what is written there is not this host's.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.callout)
                    .padding(10)
                    .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                    ValueRow("Address", host.addressLine)
                    // Shown even when nothing is known, because a dash here
                    // is what explains the generic icon beside the host's
                    // name — the one row in this grid that answers a question
                    // somebody is otherwise left asking.
                    ValueRow("OS", host.osLabel)
                    ValueRow("User", host.effective.user, from: host.effective.userFrom)
                    ValueRow("Key", host.effective.identity, from: host.effective.identityFrom)
                    ValueRow("Jump host", host.effective.jumpHost.value,
                             from: host.effective.jumpHost.from)
                    if let group = store.group(host.groupId) {
                        ValueRow("Group", store.path(of: group))
                    }
                    if !host.tags.isEmpty {
                        ValueRow("Tags", host.tags.joined(separator: ", "))
                    }
                    // Only when there is one. Unlike the rows above, this
                    // is a command line — long, and nothing anybody sets
                    // from here — so a dash for every host that has none
                    // would be a row of noise rather than an answer.
                    if !host.effective.configProxyCommand.isEmpty {
                        ValueRow("Proxy command", host.effective.configProxyCommand,
                                 from: "your ssh config")
                    }
                    agent
                    colours
                }
                .font(.callout)

                WhatWillRun(preview: preview)
                if !openHere.isEmpty {
                    OpenNow(sessions: sessions, here: openHere, inFront: inFront,
                            onShow: onShowSession)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // `Host` is Hashable, so this re-runs for any change to it — a port
        // edited here, or a group above it changing what it passes down.
        .task(id: host) {
            preview = await store.preview(of: Self.inheriting(host))
        }
    }

    /// The name with what acts on it, then where it goes, on a line of its
    /// own.
    ///
    /// **The destination has the whole width, and keeps to one line.** It
    /// used to sit under the name beside Edit and Connect, in whatever they
    /// left — about half the inspector — so `deploy@203.0.113.21 port 2222`
    /// broke as `deploy@203.0.113.2` / `1 port 2222`, inside the address,
    /// since there was nowhere else to break it. A destination longer even
    /// than the full width — a cloud machine's own name is — is cut in the
    /// middle, which keeps the user and the port, and is whole on the
    /// tooltip. The name beside the buttons is cut the same way, for the
    /// same reason.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(host.name).font(.title2).bold()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(host.name)
                Spacer()
                Button("Edit") { onEdit(host) }
                // No ⌘↩ of its own: Host ▸ Connect has it, and acts on the
                // same host. Bound here as well, the two could pick different
                // machines, and which one answered was SwiftUI's choice.
                Button("Connect") { onConnect(host) }
                    .buttonStyle(.borderedProminent)
            }
            DestinationLine(text: host.destinationLine)
        }
    }

    // MARK: what each section is made of

    private var openHere: [TerminalSession] {
        (sessions?.all ?? []).filter { $0.host?.id == host.id }
    }
}

/// The line ssh is actually given — a listed host's, or a machine typed
/// into ⌘K's. It is the one place the whole of the inheritance shows at
/// once — the jump chain spelled out as a nested `ProxyCommand`, every `-o`
/// a group contributed, the port, the key — and it is what you paste into a
/// ticket when a connection misbehaves.
///
/// Copy sits in the header rather than under the line, for the reason the
/// keys dialog learned: a long value pushes a button below the fold, and
/// taking this away with you is most of why you would look at it.
struct WhatWillRun: View {
    let preview: HostPreview
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("What will run").font(.headline)
                Spacer()
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(preview.command, forType: .string)
                    message = "Copied."
                }
                .controlSize(.small)
                .disabled(preview.argv.isEmpty)
            }
            // One argument a line, as ssh receives it; Copy gives the line
            // quoted for a shell.
            CommandLines(preview: preview)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
        .onChange(of: preview) { message = "" }
    }
}

/// The sessions already on a machine, each marked as the strip marks its
/// tab, the one in front said rather than offered. Worth saying before you
/// connect: with forty hosts and nine tabs, "am I already on this one?" is a
/// question the list cannot answer and the tab strip only answers if you
/// read every label.
struct OpenNow: View {
    /// For the names the strip gives the tabs.
    let sessions: Sessions?
    /// The sessions on this machine.
    let here: [TerminalSession]
    /// The session in front, which is said rather than offered.
    let inFront: UUID?
    let onShow: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Not counted: the rows count themselves, and "Open now (2)" sat
            // over a tab named "refuser (2)" as one more of its numbering.
            Text("Open now")
                .font(.headline)
            ForEach(here, id: \.id) { session in
                // The tab in front is said, not offered: its Show did nothing.
                if session.id == inFront {
                    openRow(session, saying: "In front")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(title(of: session)), \(session.status.spoken), in front")
                } else {
                    Button {
                        onShow(session.id)
                    } label: {
                        openRow(session, saying: "Show")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Show the session \(title(of: session)), \(session.status.spoken)")
                }
            }
        }
    }

    private func openRow(_ session: TerminalSession, saying what: String) -> some View {
        HStack(spacing: 8) {
            // The strip's mark for the tab: a terminal icon on every row said
            // a tab that never connected was as open as a live one.
            StatusMark(status: session.status)
            Text(title(of: session))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(what).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    /// A session's name as the strip and the Window menu give it: two on
    /// this host read "refuser" twice here.
    private func title(of session: TerminalSession) -> String {
        sessions?.title(of: session.id) ?? Sessions.shortTitle(of: session)
    }
}

nonisolated extension Host {
    /// Where this host goes, as the inspector's header says it: the user it
    /// logs in as, the address, and the port when it is not 22 — each as
    /// inheritance left it.
    ///
    /// **The one spelling of a destination**, shared by the sidebar, the
    /// list, the inspector, ⌘K and the window's subtitle, which wrote it five
    /// ways between them — a stray space before the port in one, "port 2222"
    /// in another, no port at all in a third. It is the way ssh is typed,
    /// brackets round an IPv6 address where a port follows it.
    var destinationLine: String {
        let port = effective.port
        return QuickConnect.Destination(
            user: effective.user, host: addr, port: port == 22 ? 0 : port
        ).spelled
    }

    /// The address alone, with the port when it is not 22, spelled the same.
    var addressLine: String {
        let port = effective.port
        return QuickConnect.Destination(host: addr, port: port == 22 ? 0 : port).spelled
    }
}

/// A host's destination as the inspector's header draws it: one line, cut in
/// the middle when it is longer than the line, and whole on the tooltip.
///
/// Its own view, and not private, so a test can render it at a narrow width
/// and measure that it stayed on one line — a layout nothing else could
/// check without driving the inspector.
struct DestinationLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .selectable(text)
            .help(text)
    }
}

/// One labelled value, with the name of whatever supplied it when it was not
/// written on the host itself.
struct ValueRow: View {
    let label: String
    let value: String
    let from: String

    init(_ label: String, _ value: String, from: String = "") {
        self.label = label
        self.value = value
        self.from = from
    }

    var body: some View {
        // The label against the value's first line, not halfway down a value
        // with its caption under it.
        GridRow(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            // Beside the value while both fit, under it when they do not:
            // squeezed onto one line, a key path and its caption both wrapped
            // into a column of fragments.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { shown; source }
                VStack(alignment: .leading, spacing: 1) { shown; source }
            }
        }
    }

    private var shown: some View {
        Text(value.isEmpty ? "—" : value)
            .selectable(value)
            .foregroundStyle(value.isEmpty ? .secondary : .primary)
    }

    /// "from Production", the words the group editor uses. An arrow said the
    /// same to the eye, and VoiceOver read it out as "left arrow".
    @ViewBuilder
    private var source: some View {
        if !from.isEmpty {
            Text("from \(from)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Inherited from \(from)")
        }
    }
}
