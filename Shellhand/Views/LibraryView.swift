import SwiftUI

/// The main panel with nothing picked in the sidebar, and with a group picked.
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
struct LibraryView: View {
    let store: HostStore
    /// Whose contents to show, or nil for the whole list.
    let group: Group?
    let onPick: (Selection) -> Void
    let onEditGroup: (Group) -> Void

    /// How you like to read the list, so `@AppStorage` rather than
    /// `@SceneStorage`: it is about you, not about this window.
    ///
    /// For anything automated: `@AppStorage` is keyed by the bundle id and
    /// not by `--db`, so a run against a scratch store writes the real
    /// preference. Read it first and put it back.
    @AppStorage("libraryLayout") private var layout = LibraryLayout.list

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !groups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group == nil ? "Groups" : "Inside").font(.headline)
                        if layout == .list {
                            ForEach(groups) { folder in
                                row(for: folder)
                            }
                        } else {
                            LazyVGrid(columns: cards, alignment: .leading, spacing: 10) {
                                ForEach(groups) { folder in
                                    card(for: folder)
                                }
                            }
                        }
                    }
                }

                if !hosts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hosts").font(.headline)
                        if layout == .list {
                            ForEach(hosts) { host in
                                row(for: host)
                            }
                        } else {
                            LazyVGrid(columns: cards, alignment: .leading, spacing: 10) {
                                ForEach(hosts) { host in
                                    card(for: host)
                                }
                            }
                        }
                    }
                }

                if groups.isEmpty && hosts.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing filed here yet", systemImage: "tray")
                    } description: {
                        Text(group == nil
                            ? "Press ⌘N to add a host."
                            : "Drag a host onto \(group?.name ?? "") to file it here.")
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    .tag(LibraryLayout.list)
                Image(systemName: "square.grid.2x2")
                    .accessibilityLabel("Grid")
                    .tag(LibraryLayout.grid)
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

    private func row(for folder: Group) -> some View {
        Button {
            onPick(.group(folder.id))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundStyle(.tint)
                Text(folder.name)
                Spacer(minLength: 12)
                Text(counted(folder)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(folder.name), \(counted(folder))")
    }

    private func row(for host: Host) -> some View {
        Button {
            onPick(.host(host.id))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "server.rack").foregroundStyle(.tint)
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
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(host.name), \(destination(of: host))")
    }

    private func card(for folder: Group) -> some View {
        Button {
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
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(folder.name), \(counted(folder))")
    }

    private func card(for host: Host) -> some View {
        Button {
            onPick(.host(host.id))
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: "server.rack").font(.title3).foregroundStyle(.tint)
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
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(host.name), \(destination(of: host))")
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

/// Whether the library reads as a list of rows or a grid of cards.
enum LibraryLayout: String {
    case list, grid
}
