import SwiftUI

/// What the inspector says about the things that are not a listed host: a
/// group picked in the list, a terminal on this Mac, and a machine typed into
/// ⌘K. It said "Nothing selected" for all three — `Panes.inspected` decides
/// which of these is in front.

/// A group: what it holds, and what it passes down to everything inside.
///
/// "Passed down" is the group's own value where it sets one and what reaches
/// it from above otherwise (`FromAbove`), which is what a host filed inside
/// it would start from.
struct GroupInspector: View {
    let store: HostStore
    let group: Group
    let onEdit: (Group) -> Void
    let onNewHostIn: (Group) -> Void
    let onNewGroupIn: (Group) -> Void

    var body: some View {
        let above = FromAbove(
            of: group, among: store.snapshot.groups, identities: store.snapshot.identities)
        let inside = store.tree.children(of: group.id)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.name).font(.title2).bold()
                        Spacer()
                        Button("Edit") { onEdit(group) }
                    }
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                // Side by side when the inspector is wide enough, one above
                // the other when not: at its usual width the second was cut
                // to "New Group Insid…". One above the other at one width,
                // the widest's, as a card's buttons stand: each at its own,
                // they stood 133 and 142pt across.
                ViewThatFits(in: .horizontal) {
                    HStack { newHost(stacked: false); newGroup(stacked: false) }
                    VStack(alignment: .leading) { newHost(stacked: true); newGroup(stacked: true) }
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text("Passed down to everything inside").font(.headline)
                // One grid for both sections, so their values stand in one
                // column: two, each sizing its own labels, put Contents'
                // values 41.5pt left of what is passed down.
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                    identity(above)
                    passed("User", own: group.user, above: above.user, from: above.userFrom)
                    passed("Key", own: group.keyPath, above: above.keyPath, from: above.keyPathFrom)
                    passed("Jump host", own: group.proxyJump, above: above.proxyJump,
                           from: above.proxyJumpFrom)
                    agent(above)
                    colours(above)
                    options(above)

                    if !inside.isEmpty || !store.tree.hosts(in: group.id).isEmpty {
                        // What the group holds. Inside is where a group sits —
                        // its editor's row, New Group Inside Production… — and
                        // this heading said it of its children, beside that
                        // very row.
                        GridRow {
                            Text("Contents").font(.headline)
                                .padding(.top, 9)
                                .gridCellColumns(2)
                                .gridCellAnchor(.leading)
                        }
                        ForEach(inside) { child in
                            ValueRow(child.name,
                                     Browsing.counted(store.tree.hostsBeneath(child.id).count))
                        }
                        let here = store.tree.hosts(in: group.id).count
                        if here > 0 { ValueRow("Filed here", Browsing.counted(here)) }
                    }
                }
                .font(.callout)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func newHost(stacked: Bool) -> some View {
        Button { onNewHostIn(group) } label: { Text("New Host Inside…").stackedButtonLabel(stacked) }
    }

    private func newGroup(stacked: Bool) -> some View {
        Button { onNewGroupIn(group) } label: { Text("New Group Inside…").stackedButtonLabel(stacked) }
    }

    private var subtitle: String {
        let path = store.path(of: group)
        let count = "Group · \(Browsing.counted(store.tree.hostsBeneath(group.id).count)) in all"
        return path == group.name ? count : "\(count) · \(path)"
    }

    /// Its own value with no caption, or what reaches it from above with one.
    private func passed(_ label: String, own: String, above: String, from: String) -> ValueRow {
        own.isEmpty ? ValueRow(label, above, from: from) : ValueRow(label, own)
    }

    /// The identity this group points at, by **name**: the store holds an id
    /// and nothing outside it has any use for one. A dash where nothing
    /// points anywhere, since this grid says what the group passes down and
    /// "nothing" is an answer here, unlike in a host's.
    private func identity(_ above: FromAbove) -> ValueRow {
        let own = store.identity(group.identityId)?.name ?? ""
        return passed("Identity", own: own, above: above.identity, from: above.identityFrom)
    }

    /// Its own choice, or what reaches it from above with where from, in the
    /// editors' words: nothing said read "—" here and "Not carried (nothing
    /// says)" there.
    private func agent(_ above: FromAbove) -> ValueRow {
        let (value, from) = group.forwardAgent != nil
            ? Effective.agent(group.forwardAgent, from: "")
            : Effective.agent(above.forwardAgent, from: above.forwardAgentFrom)
        return ValueRow("Agent forwarding", value, from: from)
    }

    /// A swatch that opens the picker, as a host's row is, and the group's
    /// palette changed from here: it is what tells production from staging,
    /// and the row was a name, the one thing here a host's inspector draws
    /// as itself. A save repaints the tabs beneath it, through
    /// `Sessions.repaint(from:)`.
    private func colours(_ above: FromAbove) -> some View {
        let parts = above.paletteParts
        // On the swatch's line, as the editors set it.
        return GridRow(alignment: .firstTextBaseline) {
            Text("Colours")
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            PaletteChoice(
                chosen: group.theme,
                inherited: Effective.inherited(parts.name, from: parts.from),
                inheritedPalette: TerminalSession.palette(named: above.theme),
                inheritedParts: parts,
                onChoose: { choose(palette: $0) })
        }
    }

    /// Saves the choice and nothing else, read again from the list rather
    /// than from the copy this view is drawing, as the host inspector's does.
    private func choose(palette: String) {
        guard palette != group.theme else { return }
        Task {
            guard var now = store.group(group.id) else { return }
            now.theme = palette
            _ = await store.save(now)
        }
    }

    /// Its own ssh options, then each group's above with whose they are,
    /// one a line: they add up rather than the nearest standing in for the
    /// rest. The inspector left them out, so a group's options showed
    /// nowhere but its editor.
    @ViewBuilder
    private func options(_ above: FromAbove) -> some View {
        let own = group.sshOptions.isEmpty
            ? [] : [FromAbove.Options(lines: group.sshOptions, from: "")]
        let all = own + above.sshOptions
        if all.isEmpty {
            ValueRow("ssh options", "")
        } else {
            ForEach(Array(all.enumerated()), id: \.offset) { index, set in
                ValueRow(index == 0 ? "ssh options" : "",
                         set.lines.joined(separator: "\n"), from: set.from)
            }
        }
    }
}

/// A terminal on this Mac rather than on a host.
struct LocalShellInspector: View {
    /// What is open, for the shells on this Mac.
    var sessions: Sessions?
    /// The session in front, which Open now says rather than offers.
    var inFront: UUID? = nil
    var onShowSession: (UUID) -> Void = { _ in }

    /// What `TerminalSession` starts a local shell with.
    private var shell: String { ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This Mac").font(.title2).bold()
                    Text("A local shell").font(.callout).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                    ValueRow("Shell", shell)
                    ValueRow("Starts in", "Your home folder")
                }
                .font(.callout)
                // Its shells, as a host's inspector lists that host's tabs:
                // with two open, nothing here said which was in front or
                // offered the other.
                if !openHere.isEmpty {
                    OpenNow(sessions: sessions, here: openHere, inFront: inFront,
                            onShow: onShowSession)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The shells on this Mac: the sessions on no host.
    private var openHere: [TerminalSession] {
        (sessions?.all ?? []).filter { $0.host == nil }
    }
}

/// A machine typed into ⌘K, which is in no list — and could not be put in
/// one from anywhere, short of typing it all again into New Host.
struct UnsavedHostInspector: View {
    let store: HostStore
    let host: Host
    /// What is open, for the tabs on this machine.
    var sessions: Sessions?
    /// The session in front, which Open now says rather than offers.
    var inFront: UUID? = nil
    var onShowSession: (UUID) -> Void = { _ in }
    let onSave: (Host) -> Void

    /// What ssh is given, resolved as the session's own argv is.
    @State private var preview = HostPreview()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(destination).font(.title2).bold()
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Typed into ⌘K · not in your list")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button("Save as Host…") { onSave(Self.savable(host)) }
                    .buttonStyle(.borderedProminent)
                // Written as a listed host's are: the address with its port, then
                // the user. It gave the port a row of its own after the user.
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                    ValueRow("Address", Self.addressLine(of: host))
                    ValueRow("User", host.user)
                }
                .font(.callout)
                // What a listed host's inspector says as well: with two tabs
                // open on a machine typed in, this said neither, and its
                // command could be read nowhere but Save as Host…'s sheet.
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
        .task(id: host) {
            preview = await store.preview(of: host)
        }
    }

    /// Its tabs: the sessions on a machine typed the same way.
    private var openHere: [TerminalSession] {
        (sessions?.all ?? []).filter { Self.sameMachine($0.host, as: host) }
    }

    /// Whether a session's machine is this one typed in again: by what was
    /// typed, never by the empty id, which every machine typed into ⌘K
    /// shares. A listed host at the same address is not it, nor a local
    /// shell, which has no host.
    nonisolated static func sameMachine(_ other: Host?, as host: Host) -> Bool {
        guard let other, other.id.isEmpty, host.id.isEmpty else { return false }
        return other.addr == host.addr && other.port == host.port && other.user == host.user
    }

    /// The address with its port unless 22, spelled as a listed host's
    /// (`Host.addressLine`), from what was typed.
    nonisolated static func addressLine(of host: Host) -> String {
        QuickConnect.Destination(host: host.addr, port: host.port == 22 ? 0 : host.port).spelled
    }

    /// Spelled from what was typed: a machine from ⌘K has nothing above it
    /// to inherit from.
    private var destination: String {
        QuickConnect.Destination(
            user: host.user, host: host.addr, port: host.port == 22 ? 0 : host.port
        ).spelled
    }

    /// What New Host opens with: the machine as typed, named by its address,
    /// which is a better start than the whole of `user@host:port` as a name.
    nonisolated static func savable(_ host: Host) -> Host {
        var saved = host
        saved.id = ""
        saved.name = host.addr
        return saved
    }
}
