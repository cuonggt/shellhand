import SwiftUI

/// The pane beside the sidebar with nothing picked, and with a group picked.
///
/// The sidebar is narrow: a row there has room for a name and a destination,
/// middle-truncated. This is the same list with room to breathe — the groups
/// with what is filed under each, and the hosts with their destination, their
/// group and their tags beside one another.
///
/// Picking anything here selects it in the sidebar rather than navigating
/// somewhere of its own, so there are never two ideas about what is selected.
/// A group picked here shows its own contents next, which is the same view
/// one level down.
struct HostsPane: View {
    let store: HostStore
    /// Whose contents to show, or nil for the whole list.
    let group: Group?
    /// What is selected, so a row can look it. The pane used to be replaced
    /// by the selected host's details, so nothing here ever had to show a
    /// selection; now the list stays and the highlight is the only thing
    /// saying which host the inspector is describing.
    let selection: Selection?
    let onPick: (Selection) -> Void
    let onConnect: (Host) -> Void
    let onEditGroup: (Group) -> Void
    /// For the row menu, which is the sidebar's — see `Views/RowMenu.swift`.
    let actions: AppActions

    /// How you like to read the list, so `@AppStorage` rather than
    /// `@SceneStorage`: it is about you, not about this window.
    ///
    /// **The key stays `libraryLayout`** though nothing is called Library any
    /// more: it is what every existing preference is stored under, and
    /// renaming it would quietly reset everybody's choice. Same reason
    /// `setFrameAutosaveName("FilesWindow")` must not change.
    ///
    /// For anything automated: `@AppStorage` is keyed by the bundle id and
    /// not by `--db`, so a run against a scratch store writes the real
    /// preference. Read it first and put it back.
    @AppStorage("libraryLayout") private var layout = HostsLayout.list

    /// How many cards `.adaptive` has settled on across the grid, which the
    /// arrow keys need and SwiftUI does not publish. Measured rather than
    /// assumed — see `gridWidth`.
    @State private var columns = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned rather than scrolling away with the rows: it carries the
            // layout picker and says which place this is, and both are wanted
            // while you are part-way down a long list.
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 14)

            if groups.isEmpty && hosts.isEmpty {
                empty
            } else if layout == .list {
                rows
            } else {
                grid
            }
        }
    }

    /// The selection as a binding, for `List`.
    ///
    /// A nil write — ⌘-clicking the selected row — is dropped rather than
    /// passed on: the inspector beside this has to be describing *something*,
    /// and "nothing selected" is a state you can only reach by deselecting,
    /// which nobody does on purpose. Writing an unchanged value through a
    /// `List` binding fires nothing at all, which is a trap recorded twice
    /// elsewhere in this app; nothing here leans on it, because the highlight
    /// is drawn from `selection` rather than from a change to it.
    private var picked: Binding<Selection?> {
        Binding(get: { selection }, set: { if let now = $0 { onPick(now) } })
    }

    /// List mode is a real `List(selection:)` rather than a column of
    /// buttons, which is what "selectable" has to mean: the highlight follows
    /// the selection, ↑ and ↓ walk the rows, and ⏎ connects. The buttons it
    /// replaces could be clicked and nothing else — no keyboard anywhere, and
    /// a row drew the same whether or not it was the one selected.
    private var rows: some View {
        List(selection: picked) {
            if !groups.isEmpty {
                Section(group == nil ? "Groups" : "Inside") {
                    ForEach(groups) { folder in
                        row(for: folder).tag(Selection.group(folder.id))
                    }
                }
            }
            if !hosts.isEmpty {
                Section("Hosts") {
                    ForEach(hosts) { host in
                        row(for: host)
                            .tag(Selection.host(host.id))
                            // **No double-click to connect here**, and
                            // the reason is worth the loss: a two-tap gesture
                            // has to wait out the system's double-click
                            // interval before it can tell one click from the
                            // first of a pair, so **every** selection pays
                            // that delay before the row lights up. Selecting
                            // is what this pane is for, and a convenience is
                            // not worth making the main gesture feel slow.
                            // Connecting is ⏎ here, ⌘↩ in the Host menu, and
                            // the Connect button in the inspector.
                    }
                }
            }
        }
        .listStyle(.inset)
        // **Double-click connects, and this is the way that does not cost
        // anything.** `primaryAction` is AppKit's own double-click action, so
        // the first click still selects immediately. A `TapGesture(count: 2)`
        // here instead made *every* single click wait out the system's
        // double-click interval before the row lit up — it shipped, a user
        // felt it at once, and it came straight back out.
        .contextMenu(forSelectionType: Selection.self) { items in
            rowMenu(for: items.first)
        } primaryAction: { items in
            guard case let .host(id) = items.first,
                  let host = hosts.first(where: { $0.id == id })
            else { return }
            onConnect(host)
        }
        .focusEffectDisabled()
        // ⏎ as well as the Host menu's ⌘↩: in a list you have arrowed down,
        // Return is the key the hand reaches for, and the menu item is across
        // the screen. Ignored unless a host is selected, so Return on a group
        // row falls through rather than connecting to something else.
        .onKeyPress(.return) {
            guard case let .host(id) = selection,
                  let host = hosts.first(where: { $0.id == id })
            else { return .ignored }
            onConnect(host)
            return .handled
        }
    }

    /// Grid mode keeps its buttons — a `LazyVGrid` has no selection of its
    /// own — so the highlight is drawn by hand and the keyboard belongs to
    /// the list.
    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !groups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group == nil ? "Groups" : "Inside").font(.headline)
                        LazyVGrid(columns: cards, alignment: .leading, spacing: 10) {
                            ForEach(groups) { folder in
                                card(for: folder)
                            }
                        }
                    }
                }
                if !hosts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hosts").font(.headline)
                        LazyVGrid(columns: cards, alignment: .leading, spacing: 10) {
                            ForEach(hosts) { host in
                                card(for: host)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { gridWidth }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        // A `LazyVGrid` has no selection and no keyboard of its own, so both
        // are hand-wired. Keys do reach it — that was worth checking before
        // writing any of this, since the alternative was a rule nothing could
        // use. Focus has to get here first, which a click does and Tab does.
        // Focusable for the keys, **not** to be outlined: a ring around the
        // whole pane is a lot of chrome for "the arrows will go here", and
        // the selected card already says where they will land.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(.left) }
        .onKeyPress(.rightArrow) { move(.right) }
        .onKeyPress(.upArrow) { move(.up) }
        .onKeyPress(.downArrow) { move(.down) }
        .onKeyPress(.return) { connectPicked() }
    }

    /// The width the grids are actually given, measured **inside** the frame
    /// and **outside** the padding, which is exactly the width `.adaptive`
    /// divides up. Asking the `ScrollView` instead would be 48pt too wide and
    /// would put the column count one out at some sizes.
    private var gridWidth: some View {
        GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in
                // The arithmetic `.adaptive` does: as many cards of the
                // minimum width as fit, counting the gap between them.
                columns = max(1, Int((width + 10) / (230 + 10)))
            }
        }
    }

    /// The cards in the order they are drawn: every group, then every host.
    private var cardOrder: [Selection] {
        groups.map { Selection.group($0.id) } + hosts.map { Selection.host($0.id) }
    }

    private func move(_ direction: GridMove.Direction) -> KeyPress.Result {
        let order = cardOrder
        guard let at = selection.flatMap({ order.firstIndex(of: $0) }) else {
            // An arrow with nothing picked starts at the first card rather
            // than doing nothing, which is what the list does too.
            guard let first = order.first else { return .ignored }
            onPick(first)
            return .handled
        }
        guard let landed = GridMove.next(
            direction, from: at,
            sections: [groups.count, hosts.count], columns: columns)
        else { return .ignored }
        onPick(order[landed])
        return .handled
    }

    private func connectPicked() -> KeyPress.Result {
        guard case let .host(id) = selection,
              let host = hosts.first(where: { $0.id == id })
        else { return .ignored }
        onConnect(host)
        return .handled
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Nothing filed here yet", systemImage: "tray")
        } description: {
            Text(group == nil
                ? "Press ⌘N to add a host."
                : "Drag a host onto \(group?.name ?? "") to file it here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Whether this is the one selected, for the cards to draw.
    private func selected(_ what: Selection) -> Bool { selection == what }

    /// The same menu a sidebar row carries, on the same items.
    private func rowMenu(for item: Selection?) -> some View {
        RowMenu(item: item, store: store, actions: actions, onConnect: onConnect)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group?.name ?? "All hosts").font(.title2).bold()
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let group {
                Button("Edit") { onEditGroup(group) }
            }
            // Images as the segments' own content, not interpolated into a
            // `Text`: that collapses to U+FFFC and draws nothing, which the
            // host editor's tab mark learned the hard way.
            Picker("Layout", selection: $layout) {
                Image(systemName: "list.bullet")
                    .accessibilityLabel("List")
                    .tag(HostsLayout.list)
                Image(systemName: "square.grid.2x2")
                    .accessibilityLabel("Grid")
                    .tag(HostsLayout.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 84)
            .help("Show as a list or a grid")
        }
    }

    /// Wide enough for a name and a destination without wrapping, and as many
    /// across as the pane has room for.
    private var cards: [GridItem] {
        [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 10, alignment: .topLeading)]
    }

    /// What is here, counted. The group line says where it sits as well,
    /// because a name like "prod" means little without the path above it.
    private var summary: String {
        var said = hosts.count == 1 ? "1 host" : "\(hosts.count) hosts"
        if !groups.isEmpty {
            said += groups.count == 1 ? ", 1 group" : ", \(groups.count) groups"
        }
        if let group, case let path = store.path(of: group), path != group.name {
            said += " — \(path)"
        }
        return said
    }

    // MARK: rows

    /// Plain content, not a button: the `List` above draws the row and its
    /// selection, so a button inside one would take the click the selection
    /// needs and paint a background over the highlight.
    private func row(for folder: Group) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(.tint)
            Text(folder.name)
            Spacer(minLength: 12)
            Text(counted(folder)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(folder.name), \(counted(folder))")
    }

    private func row(for host: Host) -> some View {
        HStack(spacing: 10) {
            HostIcon(os: host.os)
            // A set width, not a minimum: with a minimum the destination
            // starts wherever the name happens to end, so the second
            // column is ragged down the page and cannot be scanned.
            Text(host.name)
                .frame(width: 240, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(destination(of: host))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            // Only when it is not already the answer: inside a group,
            // every row would say the same thing.
            if group == nil, let folder = store.group(host.groupId) {
                Text(folder.name).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(host.tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(host.name), \(destination(of: host))")
    }

    private func card(for folder: Group) -> some View {
        Button {
            // Two clicks goes in, which is what two clicks on a folder means;
            // one selects it, and the pane follows either way.
            onPick(.group(folder.id))
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: "folder").font(.title3).foregroundStyle(.tint)
                Text(folder.name).lineLimit(1).truncationMode(.middle)
                Text(counted(folder)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            // A set height so a card with tags does not stand taller than one
            // without and leave the row ragged.
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(skin(for: .group(folder.id)), in: RoundedRectangle(cornerRadius: 8))
            .overlay(ring(for: .group(folder.id)))
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenu(for: .group(folder.id)) }
        .accessibilityLabel("\(folder.name), \(counted(folder))")
    }

    private func card(for host: Host) -> some View {
        Button {
            // **The button already fires once per click**, so the second
            // click of a double arrives here carrying `clickCount == 2`.
            // Reading the triggering event is all it takes: no gesture to
            // disambiguate, so the first click still selects at once.
            //
            // Two earlier attempts are worth not repeating. A
            // `TapGesture(count: 2)` made every single click wait out the
            // double-click interval. An `NSClickGestureRecognizer` on the
            // card's superview never fired at all — the button consumes the
            // clicks before an AppKit recogniser above it sees them.
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                onConnect(host)
            } else {
                onPick(.host(host.id))
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HostIcon(os: host.os, size: 22)
                Text(host.name).lineLimit(1).truncationMode(.middle)
                Text(destination(of: host))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    if group == nil, let folder = store.group(host.groupId) {
                        Text(folder.name).font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(host.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(skin(for: .host(host.id)), in: RoundedRectangle(cornerRadius: 8))
            .overlay(ring(for: .host(host.id)))
            // No double-click here either, for the reason the row gives:
            // it costs every single click the double-click interval.
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenu(for: .host(host.id)) }
        .accessibilityLabel("\(host.name), \(destination(of: host))")
    }

    /// A card's fill, and the ring that makes the selection unmistakable at a
    /// glance across a grid — a tint wash alone reads as a hover on a dense
    /// page of cards.
    private func skin(for what: Selection) -> AnyShapeStyle {
        selected(what)
            ? AnyShapeStyle(.tint.opacity(0.18))
            : AnyShapeStyle(.quaternary.opacity(0.4))
    }

    @ViewBuilder
    private func ring(for what: Selection) -> some View {
        if selected(what) {
            RoundedRectangle(cornerRadius: 8).strokeBorder(.tint, lineWidth: 2)
        }
    }

    // MARK: what is shown

    /// Top-level groups with nothing picked, the children of the one picked
    /// otherwise.
    private var groups: [Group] {
        store.snapshot.groups
            .filter { $0.parentId == (group?.id ?? "") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Every host with nothing picked — the point of this pane is the whole
    /// list at a width that fits it — and a group's own hosts otherwise.
    private var hosts: [Host] {
        store.snapshot.hosts
            .filter { group == nil || $0.groupId == group?.id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func counted(_ folder: Group) -> String {
        let n = store.snapshot.hosts.count { $0.groupId == folder.id }
        return n == 1 ? "1 host" : "\(n) hosts"
    }

    private func destination(of host: Host) -> String {
        let user = host.effective.user
        let port = host.effective.port
        return (user.isEmpty ? host.addr : "\(user)@\(host.addr)")
            + (port == 22 ? "" : ":\(port)")
    }
}

/// Whether the list reads as rows or as a grid of cards.
enum HostsLayout: String {
    case list, grid
}
