import SwiftUI

/// ⌘K: type part of a name and connect, without finding it in the tree first.
struct QuickConnectSheet: View {
    let store: HostStore
    let onConnect: (Host) -> Void

    @State private var text = ""
    @State private var highlighted: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Connect to…", text: $text)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .focused($focused)
                .onSubmit { connect(first) }

            Divider()

            // A reader around it so the highlight can be kept on screen:
            // fifty matches do not fit, and an arrow key that moves a
            // highlight out of view is worse than one that does nothing.
            ScrollViewReader { rows in
                List(matches, selection: $highlighted) { host in
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
                    .contentShape(Rectangle())
                    .tag(host.id)
                    .onTapGesture { connect(host) }
                }
                .listStyle(.inset)
                .onChange(of: highlighted) { _, now in
                    if let now { rows.scrollTo(now) }
                }
            }
        }
        .frame(width: 520, height: 380)
        .onAppear {
            focused = true
            highlighted = matches.first?.id
        }
        // The top match is highlighted as you type, so what Return will do is
        // on screen rather than implied. Typing starts the choice again —
        // the list underneath is a different list.
        .onChange(of: text) { _, _ in highlighted = matches.first?.id }
        // The field keeps focus so typing carries on; these only move the
        // highlight. Up and down do nothing in a one-line field, so there is
        // nothing to take away from it.
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        // A palette has no footer, so nothing here binds `.cancelAction` and
        // nothing answers Escape. This does.
        .onExitCommand { dismiss() }
    }

    /// Everything whose name, address or tags hold what was typed, nearest
    /// first: a name that starts with it before one that merely contains it.
    private var matches: [Host] {
        let needle = text.lowercased()
        guard !needle.isEmpty else {
            return Array(store.snapshot.hosts
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .prefix(50))
        }
        return store.snapshot.hosts
            .compactMap { host -> (Host, Int)? in
                let name = host.name.lowercased()
                if name.hasPrefix(needle) { return (host, 0) }
                if name.contains(needle) { return (host, 1) }
                if host.addr.lowercased().contains(needle) { return (host, 2) }
                if host.tags.contains(where: { $0.lowercased().contains(needle) }) { return (host, 3) }
                return nil
            }
            .sorted {
                $0.1 == $1.1
                    ? $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending
                    : $0.1 < $1.1
            }
            .prefix(50)
            .map(\.0)
    }

    private var first: Host? {
        if let highlighted, let host = matches.first(where: { $0.id == highlighted }) { return host }
        return matches.first
    }

    /// Moves the highlight, stopping at the ends rather than wrapping — the
    /// shape Spotlight has, where running off the bottom and reappearing at
    /// the top loses your place.
    private func move(_ delta: Int) {
        let list = matches
        guard !list.isEmpty else { return }
        let at = list.firstIndex { $0.id == highlighted } ?? 0
        highlighted = list[min(max(at + delta, 0), list.count - 1)].id
    }

    private func connect(_ host: Host?) {
        guard let host else { return }
        onConnect(host)
        dismiss()
    }
}
