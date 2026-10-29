import SwiftUI

/// ⌘K: type part of a name and connect, without finding it in the tree first
/// — or type `user@host:port` and connect to a machine that is not in it.
struct QuickConnectSheet: View {
    let store: HostStore
    let onConnect: (Host) -> Void

    @State private var text = ""
    @State private var highlighted: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Saying user@host:port in the field is the only way anybody
            // would find out that it takes one.
            TextField("Connect to a host, or user@host:port", text: $text)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .focused($focused)
                .onSubmit { connect(first) }

            Divider()

            // A reader around it so the highlight can be kept on screen:
            // fifty matches do not fit, and an arrow key that moves a
            // highlight out of view is worse than one that does nothing.
            ScrollViewReader { reader in
                List(rows, selection: $highlighted) { row in
                    line(row)
                        .contentShape(Rectangle())
                        .tag(row.id)
                        .onTapGesture { connect(row) }
                }
                .listStyle(.inset)
                .onChange(of: highlighted) { _, now in
                    if let now { reader.scrollTo(now) }
                }
            }
        }
        .frame(width: 520, height: 380)
        .onAppear {
            focused = true
            highlighted = rows.first?.id
        }
        // The top match is highlighted as you type, so what Return will do is
        // on screen rather than implied. Typing starts the choice again —
        // the list underneath is a different list.
        .onChange(of: text) { _, _ in highlighted = rows.first?.id }
        // The field keeps focus so typing carries on; these only move the
        // highlight. Up and down do nothing in a one-line field, so there is
        // nothing to take away from it.
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        // A palette has no footer, so nothing here binds `.cancelAction` and
        // nothing answers Escape. This does.
        .onExitCommand { dismiss() }
    }

    /// What the list is showing. The ranking lives in `QuickConnect`, where
    /// it can be checked without a window and without a host list that
    /// connects to real machines — and so does where the typed row goes.
    private var rows: [QuickConnect.Row] {
        QuickConnect.rows(among: store.snapshot.hosts, for: text)
    }

    @ViewBuilder
    private func line(_ row: QuickConnect.Row) -> some View {
        switch row {
        case let .saved(host):
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.name)
                    Text(host.effective.user.isEmpty ? host.addr : "\(host.effective.user)@\(host.addr)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let group = store.group(host.groupId) {
                    Text(store.path(of: group)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        case let .typed(destination):
            VStack(alignment: .leading, spacing: 1) {
                Text("Connect to \(destination.spelled)")
                Text("Not in your list")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var first: QuickConnect.Row? {
        if let highlighted, let row = rows.first(where: { $0.id == highlighted }) { return row }
        return rows.first
    }

    private func move(_ delta: Int) {
        highlighted = QuickConnect.moved(from: highlighted, by: delta, over: rows)
    }

    private func connect(_ row: QuickConnect.Row?) {
        switch row {
        case let .saved(host)?: onConnect(host)
        case let .typed(destination)?: onConnect(QuickConnect.unsaved(destination))
        case nil: return
        }
        dismiss()
    }
}
