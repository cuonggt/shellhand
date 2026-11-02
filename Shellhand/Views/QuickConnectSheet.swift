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
                // The highlight drawn here rather than as the list's own
                // selection, which is greyed while the keyboard is in the
                // field above — where it always is: the row Return takes
                // stood in grey, as a list does that is not in use.
                List(rows) { row in
                    let lit = row.id == highlighted
                    line(row, lit: lit)
                        .foregroundStyle(lit ? AnyShapeStyle(Self.litWords) : AnyShapeStyle(.primary))
                        .contentShape(Rectangle())
                        .onTapGesture { connect(row) }
                        .listRowBackground(lit ? Self.lit : nil)
                        .accessibilityAddTraits(lit ? .isSelected : [])
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

    /// The highlighted row's ground and words: a list's own selection where
    /// the list is in use, the inset list's shape in the accent.
    private static var lit: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(SwiftUI.Color(nsColor: .selectedContentBackgroundColor))
            .padding(.horizontal, 10)
    }
    private static let litWords = SwiftUI.Color(nsColor: .alternateSelectedControlTextColor)

    /// What the list is showing. The ranking lives in `QuickConnect`, where
    /// it can be checked without a window and without a host list that
    /// connects to real machines — and so does where the typed row goes.
    private var rows: [QuickConnect.Row] {
        QuickConnect.rows(among: store.snapshot.hosts, for: text)
    }

    @ViewBuilder
    private func line(_ row: QuickConnect.Row, lit: Bool) -> some View {
        switch row {
        case let .saved(host):
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.name)
                    Text(host.destinationLine)
                        .font(.caption)
                        .foregroundStyle(secondary(lit))
                }
                Spacer()
                if let group = store.group(host.groupId) {
                    Text(store.path(of: group)).font(.caption2).foregroundStyle(secondary(lit))
                }
            }
        case let .typed(destination):
            VStack(alignment: .leading, spacing: 1) {
                Text("Connect to \(destination.spelled)")
                Text(QuickConnect.typedCaption(among: store.snapshot.hosts, for: text))
                    .font(.caption)
                    .foregroundStyle(secondary(lit))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A row's lesser words: grey, and on the highlight as the rest are, as a
    /// list in use draws every word of its chosen row — as `.secondary` there
    /// they came out a pale blue, 2.5:1 against the accent.
    private func secondary(_ lit: Bool) -> AnyShapeStyle {
        lit ? AnyShapeStyle(Self.litWords) : AnyShapeStyle(.secondary)
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
