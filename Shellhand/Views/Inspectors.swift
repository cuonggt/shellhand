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
        let above = FromAbove(of: group, among: store.snapshot.groups)
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
                // to "New Group Insid…".
                ViewThatFits(in: .horizontal) {
                    HStack { newHost; newGroup }
                    VStack(alignment: .leading) { newHost; newGroup }
                }

                Text("Passed down to everything inside").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                    passed("User", own: group.user, above: above.user, from: above.userFrom)
                    passed("Key", own: group.identity, above: above.identity, from: above.identityFrom)
                    passed("Jump host", own: group.proxyJump, above: above.proxyJump,
                           from: above.proxyJumpFrom)
                    agent(above)
                    colours(above)
                }
                .font(.callout)

                if !inside.isEmpty || !store.tree.hosts(in: group.id).isEmpty {
                    Text("Inside").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                        ForEach(inside) { child in
                            ValueRow(child.name,
                                     Browsing.counted(store.tree.hostsBeneath(child.id).count))
                        }
                        let here = store.tree.hosts(in: group.id).count
                        if here > 0 { ValueRow("Filed here", Browsing.counted(here)) }
                    }
                    .font(.callout)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var newHost: some View { Button("New Host Inside…") { onNewHostIn(group) } }
    private var newGroup: some View { Button("New Group Inside…") { onNewGroupIn(group) } }

    private var subtitle: String {
        let path = store.path(of: group)
        let count = "Group · \(Browsing.counted(store.tree.hostsBeneath(group.id).count)) in all"
        return path == group.name ? count : "\(count) · \(path)"
    }

    /// Its own value with no caption, or what reaches it from above with one.
    private func passed(_ label: String, own: String, above: String, from: String) -> ValueRow {
        own.isEmpty ? ValueRow(label, above, from: from) : ValueRow(label, own)
    }

    private func agent(_ above: FromAbove) -> ValueRow {
        if let says = group.forwardAgent {
            return ValueRow("Agent forwarding", says ? "Carried" : "Not carried")
        }
        guard let says = above.forwardAgent else { return ValueRow("Agent forwarding", "") }
        return ValueRow("Agent forwarding", says ? "Carried" : "Not carried",
                        from: above.forwardAgentFrom)
    }

    private func colours(_ above: FromAbove) -> ValueRow {
        if !group.theme.isEmpty { return ValueRow("Colours", group.theme) }
        if !above.theme.isEmpty { return ValueRow("Colours", above.theme, from: above.themeFrom) }
        return ValueRow("Colours", "As in Settings")
    }
}

/// A terminal on this Mac rather than on a host.
struct LocalShellInspector: View {
    /// What `TerminalSession` starts a local shell with.
    private var shell: String { ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh" }

    var body: some View {
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
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A machine typed into ⌘K, which is in no list — and could not be put in
/// one from anywhere, short of typing it all again into New Host.
struct UnsavedHostInspector: View {
    let host: Host
    let onSave: (Host) -> Void

    var body: some View {
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
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                ValueRow("Address", host.addr)
                ValueRow("User", host.user)
                ValueRow("Port", host.port == 0 ? "" : String(host.port))
            }
            .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
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
