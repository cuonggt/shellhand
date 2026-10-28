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

    /// What ssh would be given, worked out by `Core` the same way the host
    /// editor's preview line is — so the two can never disagree about what
    /// this host runs.
    @State private var preview = HostPreview()
    @State private var message = ""

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
                    ValueRow("Address", "\(host.addr):\(host.effective.port)")
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
                }
                .font(.callout)

                command
                if !openHere.isEmpty { openNow }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // `Host` is Hashable, so this re-runs for any change to it — a port
        // edited here, or a group above it changing what it passes down.
        .task(id: host) {
            message = ""
            preview = await store.preview(of: host)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name).font(.title2).bold()
                Text(destination).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Button("Edit") { onEdit(host) }
            Button("Connect") { onConnect(host) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
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
            Text(preview.argv.isEmpty ? "Working it out…" : preview.command)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(preview.argv.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
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

    private var destination: String {
        let user = host.effective.user
        let port = host.effective.port
        return (user.isEmpty ? host.addr : "\(user)@\(host.addr)") + (port == 22 ? "" : " port \(port)")
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
                if !from.isEmpty {
                    Text("← \(from)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Inherited from \(from)")
                }
            }
        }
    }
}
