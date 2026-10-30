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
    @ViewBuilder private var colours: some View {
        GridRow {
            Text("Colours")
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Button { choosing = true } label: {
                HStack(spacing: 7) {
                    TerminalMiniature(palette: shown, size: CGSize(width: 34, height: 21))
                    Text(host.theme.isEmpty ? preview.effective.inheritedPalette : host.theme)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Colours")
        }
    }

    /// The palette this host comes up in, whether it chose one or not.
    private var shown: Palette? {
        Themes.named(host.theme.isEmpty ? preview.effective.theme : host.theme)
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
    @State private var message = ""
    @State private var choosing = false

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
                    colours
                }
                .font(.callout)

                command
                if !openHere.isEmpty { openNow }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $choosing) {
            PalettePicker(
                chosen: host.theme,
                inherited: preview.effective.inheritedPalette,
                inheritedPalette: Themes.named(preview.effective.theme),
                onChoose: { choose(palette: $0) })
        }
        // `Host` is Hashable, so this re-runs for any change to it — a port
        // edited here, or a group above it changing what it passes down.
        .task(id: host) {
            message = ""
            preview = await store.preview(of: host)
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

    // MARK: what will run

    /// The line ssh is actually given. It is the one place the whole of the
    /// inheritance shows at once — the jump chain spelled out as a nested
    /// `ProxyCommand`, every `-o` a group contributed, the port, the key —
    /// and it is what you paste into a ticket when a connection misbehaves.
    ///
    /// Copy sits in the header rather than under the line, for the reason the
    /// keys dialog learned: a long value pushes a button below the fold, and
    /// taking this away with you is most of why you would look at it.
    private var command: some View {
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
            // quoted for a shell. Drawn as that quoted line, a jump chain was
            // a wall of `'"'"'` cut in the middle of a path.
            VStack(alignment: .leading, spacing: 2) {
                if preview.argv.isEmpty {
                    Text("Working it out…").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(preview.lines.enumerated()), id: \.offset) { index, line in
                        Text(line).padding(.leading, index == 0 ? 0 : 14)
                    }
                }
            }
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(preview.argv.isEmpty ? "Working it out" : preview.command)
        }
    }

    // MARK: already open

    /// The sessions already on this machine. Worth saying before you connect:
    /// with forty hosts and nine tabs, "am I already on this one?" is a
    /// question the list cannot answer and the tab strip only answers if you
    /// read every label.
    private var openNow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(openHere.count == 1 ? "Open now" : "Open now (\(openHere.count))")
                .font(.headline)
            ForEach(openHere, id: \.id) { session in
                Button {
                    onShowSession(session.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                        Text(Sessions.shortTitle(of: session))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("Show").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show the session on \(Sessions.shortTitle(of: session))")
            }
        }
    }

    // MARK: what each section is made of

    private var openHere: [TerminalSession] {
        (sessions?.all ?? []).filter { $0.host?.id == host.id }
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
            .textSelection(.enabled)
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
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            HStack(spacing: 6) {
                Text(value.isEmpty ? "—" : value)
                    .textSelection(.enabled)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                // "from Production", the words the group editor uses. An
                // arrow said the same to the eye, and VoiceOver read it out
                // as "left arrow".
                if !from.isEmpty {
                    Text("from \(from)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Inherited from \(from)")
                }
            }
        }
    }
}
