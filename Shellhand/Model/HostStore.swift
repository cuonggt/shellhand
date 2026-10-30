import Foundation
import Observation

/// The host list the windows read, kept here rather than fetched per view.
///
/// Read once and kept, rather than asked for per view, per row or per
/// keystroke: resolving every host's inheritance is real work, and a sidebar
/// that asked for it while drawing would do it a few hundred times a frame.
/// It reads again when something changes — its own writes, or the file
/// changing underneath it.
@Observable
@MainActor
final class HostStore {
    private(set) var snapshot = Snapshot()
    private(set) var lastError: String?
    private(set) var loading = false

    let dbPath: String
    /// Held outside the actor so `deinit`, which is nonisolated, can stop it.
    private let watcher = Watcher()
    /// Our own writes would otherwise look like somebody else's: the watcher
    /// sees the file change, reloads, and the reload is itself a change. That
    /// loop once read the store every few milliseconds while the sidebar
    /// rebuilt around it. This closes the window while we write.
    private var ignoringChanges = false
    private var pendingReload: Task<Void, Never>?

    /// The list as a tree, rebuilt with each snapshot. The walks live in
    /// `Tree` so they can be checked without a store; this holds the current
    /// one and the sidebar reads it directly.
    private(set) var tree = Tree()

    init(dbPath: String) {
        self.dbPath = dbPath
    }

    // MARK: reading

    /// Dismissing the alert clears the error; without this it came straight
    /// back, because `lastError` was still set.
    func clearError() { lastError = nil }

    /// Puts up something that went wrong outside the store, through the same
    /// alert as its own errors — an export the disk would not take, say.
    func report(_ message: String) { lastError = message }

    func refresh() async {
        loading = true
        ignoringChanges = true
        defer {
            loading = false
            // A moment, because the file system reports our own read after it.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                ignoringChanges = false
            }
        }
        let path = dbPath
        do {
            let next = try await Core.shared.snapshot(db: path)
            // Only when something really changed: an identical snapshot that
            // is assigned anyway redraws every view watching it.
            if next != snapshot {
                snapshot = next
                index()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func index() { tree = Tree(snapshot) }

    /// Reloads when the store changes underneath us, so a list edited
    /// elsewhere — an import, another window — shows up here.
    func watchForExternalChanges() {
        guard watcher.source == nil else { return }
        // O_CLOEXEC because this is held for the app's whole life, so without
        // it every terminal's `ssh` carries a descriptor on the host list for as
        // long as it runs — SwiftTerm forks without closing anything.
        let descriptor = Darwin.open(dbPath, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.reloadSoon() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        watcher.source = source
    }

    /// Coalesces the flurry of events one write produces, and ignores the
    /// ones our own reading caused.
    private func reloadSoon() {
        guard !ignoringChanges else { return }
        pendingReload?.cancel()
        pendingReload = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    deinit { watcher.cancel() }

    /// A cancellable the deinit can reach.
    nonisolated private final class Watcher: @unchecked Sendable {
        var source: DispatchSourceFileSystemObject?
        func cancel() {
            source?.cancel()
            source = nil
        }
    }

    // MARK: the shape the sidebar wants

    func group(_ id: String) -> Group? { tree.group(id) }

    func children(of groupID: String) -> [Group] { tree.children(of: groupID) }

    func hosts(in groupID: String) -> [Host] { tree.hosts(in: groupID) }

    /// Every host beneath a group, however deep — what deleting it would take
    /// with it, and what its row stands for.
    func hostsBeneath(_ groupID: String) -> [Host] { tree.hostsBeneath(groupID) }

    var ungrouped: [Host] { tree.ungrouped }

    var allTags: [String] { Tags.all(in: snapshot.hosts) }

    /// Renames a tag everywhere it is used, writing only the hosts that carry
    /// it. Renaming onto a tag that already exists merges the two.
    @discardableResult
    func rename(tag: String, to new: String) async -> Int {
        await write(Tags.renaming(tag, to: new, in: snapshot.hosts))
    }

    /// Takes a tag off every host that carries it, which is what deleting one
    /// means: there is no list of tags apart from the hosts.
    @discardableResult
    func delete(tag: String) async -> Int {
        await write(Tags.removing(tag, from: snapshot.hosts))
    }

    /// Moves a host into a group, or out of all of them with an empty id.
    /// What dragging a row onto a group does.
    func move(host: Host, toGroup id: String) async {
        guard host.groupId != id else { return }
        var moved = host
        moved.groupId = id
        await save(moved)
    }

    /// The same for a group. A group cannot be moved inside itself or inside
    /// something already beneath it — `Validation.possibleParents` says which
    /// ones are left, and this refuses the rest rather than making a loop.
    @discardableResult
    func move(group: Group, toParent id: String) async -> Bool {
        guard group.parentId != id, group.id != id else { return false }
        guard id.isEmpty || Validation.possibleParents(for: group, among: snapshot.groups)
            .contains(where: { $0.id == id })
        else { return false }
        var moved = group
        moved.parentId = id
        await save(moved)
        return true
    }

    /// Saves a run of hosts as one change, so the sidebar redraws once.
    private func write(_ hosts: [Host]) async -> Int {
        guard !hosts.isEmpty else { return 0 }
        for host in hosts { await save(host) }
        return hosts.count
    }

    /// What else goes when a record does. Asked from the editors and from
    /// the sidebar both, and worded in the engine so it can be tested.
    func deletionWarning(for host: Host) -> String {
        Validation.deletionWarning(for: host, hosts: snapshot.hosts, groups: snapshot.groups)
    }

    func deletionWarning(for group: Group) -> String {
        Validation.deletionWarning(
            for: group, groups: snapshot.groups, hosts: snapshot.hosts)
    }

    /// The name a group shows in a path, "Production / EU".
    func path(of group: Group) -> String { tree.path(of: group) }

    // MARK: writing

    @discardableResult
    func save(_ host: Host) async -> Host? {
        await write { try await Core.shared.save(db: $0, host: host) }
    }

    @discardableResult
    func save(_ group: Group) async -> Group? {
        await write { try await Core.shared.save(db: $0, group: group) }
    }

    func delete(_ host: Host) async {
        await write { try await Core.shared.deleteHost(db: $0, id: host.id) }
    }

    func delete(_ group: Group) async {
        await write { try await Core.shared.deleteGroup(db: $0, id: group.id) }
    }

    /// What a host would inherit and what it would run, for a host being
    /// edited — saved or not.
    func preview(of host: Host) async -> HostPreview {
        (try? await Core.shared.preview(db: dbPath, host: host)) ?? HostPreview()
    }

    /// What a session on `host` is opened with: the argv, and the route it
    /// goes by. A machine typed into ⌘K is resolved as it stands, as below.
    func connection(for host: Host) async -> Connection? {
        let path = dbPath
        let id = host.id
        do {
            if id.isEmpty { return try await Core.shared.connection(db: path, unsaved: host) }
            return try await Core.shared.connection(db: path, hostID: id)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func sshArgs(for host: Host) async -> [String]? {
        let path = dbPath
        let id = host.id
        do {
            // A host typed into ⌘K is in no list to look it up in, so it is
            // resolved as it stands — the way the editor previews one not yet
            // saved — and takes the settings file's options like any other.
            if id.isEmpty { return try await Core.shared.preview(db: path, host: host).argv }
            return try await Core.shared.sshArgs(db: path, hostID: id)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: moving a list in and out

    func importSSHConfig(path: String = "", group: String = "", dryRun: Bool) async -> MergeResult? {
        let db = dbPath
        do {
            let result = try await Core.shared.importSSHConfig(
                db: db, path: path, group: group, dryRun: dryRun)
            if !dryRun { await refresh() }
            lastError = nil
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func importYAML(_ text: String, group: String = "", dryRun: Bool) async -> MergeResult? {
        let db = dbPath
        do {
            let result = try await Core.shared.importYAML(
                db: db, text: text, group: group, dryRun: dryRun)
            if !dryRun { await refresh() }
            lastError = nil
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func importCSV(_ text: String, group: String = "", dryRun: Bool) async -> CSVImport? {
        let db = dbPath
        do {
            let reading = try await Core.shared.importCSV(
                db: db, text: text, group: group, dryRun: dryRun)
            if !dryRun { await refresh() }
            lastError = nil
            return reading
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// How many machines `~/.ssh/config` names, so an empty list can offer
    /// them by number rather than in the abstract.
    ///
    /// Not `async`, although it reads a file. `Core.sshConfigHosts` is
    /// `nonisolated`, so there was never a hop to await: the read ran on the
    /// caller — this main actor — and the `async` bought the look of
    /// something it was not doing. If it ever needs to be off the main
    /// thread, that is a change to `Core`, not a keyword here.
    func sshConfigHosts(path: String = "") -> Int? {
        Core.shared.sshConfigHosts(path: path)
    }

    func exportYAML() async -> String? {
        let db = dbPath
        do {
            return try await Core.shared.exportYAML(db: db)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Every write goes through here: off the main thread, then a reread, so
    /// what the windows show is what the store holds rather than what this
    /// side believes it wrote.
    @discardableResult
    private func write<T: Sendable>(_ body: @escaping @Sendable (String) async throws -> T) async -> T? {
        let path = dbPath
        ignoringChanges = true
        do {
            let result = try await body(path)
            await refresh()
            lastError = nil
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func write(_ body: @escaping @Sendable (String) async throws -> Void) async {
        let _: Void? = await write { (path: String) -> Void in try await body(path) }
    }
}

extension HostStore {
    /// The real host list, as opposed to the scratch one a test run gets.
    static var defaultDatabasePath: String { Store.defaultPath }
}
