import Foundation

/// Everything the window asks of the engine, in one place.
///
/// This was a C archive built from Go, linked into the app, with every call
/// crossing cgo as a JSON string. It is Swift now, and the window's side of it
/// barely changed: the same calls, awaited rather than wrapped in a detached
/// task, because an actor already keeps this work off the main thread.
///
/// Sessions, runs and transfers are held here by id, as they were when they
/// had to be — a file session is a running `ssh`, and whoever started it is
/// not the only one who asks after it.
actor Core {
    static let shared = Core()

    private var stores: [String: Store] = [:]
    private var sessions: [String: SFTPClient] = [:]
    private var transfers: [String: TransferJob] = [:]

    // MARK: the store

    private func store(_ path: String) throws -> Store {
        if let store = stores[path] { return store }
        let store = try Store(path: path)
        stores[path] = store
        return store
    }

    /// The list, with every host's inheritance worked out.
    func snapshot(db: String) throws -> Snapshot {
        var snapshot = try store(db).snapshot()
        snapshot.hosts = resolver(snapshot).resolveAll(snapshot.hosts)
        return snapshot
    }

    private func resolver(_ snapshot: Snapshot) -> Resolver {
        let config = sshConfig()
        return Resolver(groups: snapshot.groups, hosts: snapshot.hosts)
            .withAliases(config.aliases)
            .withProxies(config.proxy)
    }

    /// What ssh's own config says, kept against the file it was read from.
    private struct SSHConfig {
        let path: String
        let stamp: Date?
        let size: Int
        /// The names it gives machines.
        let aliases: [Alias]
        /// What it would send a destination through, asked per host because
        /// `Host 10.0.1.*` cannot be answered without knowing the address.
        let proxy: @Sendable (String) -> SSHConfigFile.Route
    }

    private var configRead: SSHConfig?

    /// The names ssh's own config gives machines, re-read only when that file
    /// has changed.
    ///
    /// **This wiring is the whole of the feature, and it was missing for every
    /// release up to now.** `Resolver` has always known what to do with these
    /// — reach a host by the name its config gives it, so the block written
    /// under that name applies, or say that the name goes to a different
    /// machine — `SSHArgs` has always spelled the first, and `HostDetailView`
    /// has always drawn the second. Nothing ever handed it any names, so the
    /// warning could not appear and the alias was always empty. The pieces
    /// each had tests; what had none was them being connected.
    ///
    /// Cached because a resolver is built for every snapshot, every argv and
    /// every preview the editor asks for as a group is picked — parsing a
    /// config and every file it includes on each of those is a filesystem
    /// walk nobody asked for. A `stat` is not free either, but it is one call
    /// against a walk, and a config nobody is editing is read once.
    private func sshConfig() -> SSHConfig {
        let path = SSHConfigFile.pathInUse
        // A file that is not there answers nil, which caches as "it says
        // nothing" and re-reads the moment one appears.
        let about = try? FileManager.default.attributesOfItem(atPath: path)
        let stamp = about?[.modificationDate] as? Date
        let size = (about?[.size] as? Int) ?? 0
        if let last = configRead, last.path == path, last.stamp == stamp, last.size == size {
            return last
        }
        // Parsed **once** for both answers. The blocks are what every later
        // question is asked of, including the per-destination one, which is
        // why they are held rather than a finished list.
        let blocks = SSHConfigFile.parse(path: path)
        let read = SSHConfig(
            path: path, stamp: stamp, size: size,
            aliases: SSHConfigFile.aliases(in: blocks),
            proxy: { SSHConfigFile.route(reaching: $0, in: blocks) })
        configRead = read
        return read
    }

    /// What ssh would be run with to reach a host — the line the window shows
    /// and the line it connects with, which have to be the same line. The one
    /// difference is a run under test's: its sessions lead with
    /// `TestRun.sshFixed`, which is nothing anyone should see or copy.
    func sshArgs(db: String, hostID: String) throws -> [String] {
        let snapshot = try store(db).snapshot()
        guard let host = snapshot.hosts.first(where: { $0.id == hostID }) else {
            throw CoreError("that host is no longer in the list")
        }
        return SSHArgs.build(resolver(snapshot).resolve(host))
    }

    /// What a host would inherit and what it would run, worked out for a host
    /// that may not be saved yet — which is what the editor needs: picking a
    /// group should say what that group gives before anything is written.
    func preview(db: String, host: Host) throws -> HostPreview {
        let resolved = resolver(try store(db).snapshot()).resolve(host)
        return HostPreview(effective: resolved.effective, argv: SSHArgs.build(resolved))
    }

    /// A host resolved, for the callers that need more than the argv.
    func resolved(db: String, hostID: String) throws -> Resolved {
        let snapshot = try store(db).snapshot()
        guard let host = snapshot.hosts.first(where: { $0.id == hostID }) else {
            throw CoreError("that host is no longer in the list")
        }
        return resolver(snapshot).resolve(host)
    }

    /// What a session on a listed host is opened with: the argv, and the
    /// route the connecting screen and the host-key question name.
    ///
    /// Under test it leads with the run's own ssh config, carried into every
    /// hop, since each jump is an `ssh` of its own that reads one too.
    func connection(db: String, hostID: String) throws -> Connection {
        let resolved = try resolved(db: db, hostID: hostID)
        return Connection(
            argv: SSHArgs.build(resolved, fixed: TestRun.sshFixed), route: resolved.route)
    }

    /// The same for a machine typed into ⌘K, resolved as it stands.
    func connection(db: String, unsaved host: Host) throws -> Connection {
        let resolved = resolver(try store(db).snapshot()).resolve(host)
        return Connection(
            argv: SSHArgs.build(resolved, fixed: TestRun.sshFixed), route: resolved.route)
    }

    @discardableResult
    func save(db: String, host: Host) throws -> Host { try store(db).save(host) }
    @discardableResult
    func save(db: String, group: Group) throws -> Group { try store(db).save(group) }
    func deleteHost(db: String, id: String) throws { try store(db).deleteHost(id: id) }
    func deleteGroup(db: String, id: String) throws { try store(db).deleteGroup(id: id) }

    // MARK: settings

    nonisolated struct Configured: Sendable {
        var path = ""
        var options: [String] = []
    }

    /// Reads the settings file and applies its ssh options to every connection
    /// from here on.
    ///
    /// Not on the actor: it runs in the app's own initialiser, before any
    /// window and before anything can connect, and there is nothing to
    /// serialise it against yet.
    nonisolated static func configure(configPath: String = "") throws -> Configured {
        let path = Config.path(configPath)
        let config = try Config.load(path: path)
        SSHArgs.setGlobalOptions(config.sshOptions)
        Themes.setCustom(config.themes)
        return Configured(path: path, options: config.sshOptions)
    }

    // MARK: moving a list in and out

    func exportYAML(db: String) throws -> String {
        let store = try store(db)
        let snapshot = try store.snapshot()
        return try Portable.export(groups: snapshot.groups, hosts: snapshot.hosts)
    }

    func importYAML(db: String, text: String, group: String = "", dryRun: Bool) throws
        -> MergeResult
    {
        try apply(try Portable.parse(text), newHostsIn: group, db: db, dryRun: dryRun)
    }

    /// Reads OpenSSH's own config as a host list. A group puts the hosts it
    /// adds in one place, which is what makes a first import tidy.
    func importSSHConfig(
        db: String, path: String = "", group: String = "", dryRun: Bool
    ) throws -> MergeResult {
        let document = SSHConfigFile.read(
            path: path.isEmpty ? SSHConfigFile.pathInUse : path)
        return try apply(document, newHostsIn: group, db: db, dryRun: dryRun)
    }

    /// Reads a list a spreadsheet or another client wrote.
    ///
    /// Carries back which columns were used and which were passed over, so
    /// the window can say so: a file whose Password column went nowhere is
    /// worth a sentence rather than a silence.
    func importCSV(
        db: String, text: String, group: String = "", dryRun: Bool
    ) throws -> CSVImport {
        let reading = try CSVHosts.read(text)
        let result = try apply(reading.document, newHostsIn: group, db: db, dryRun: dryRun)
        return CSVImport(result: result, used: reading.used, ignored: reading.ignored)
    }

    private func apply(
        _ document: Portable.Document, newHostsIn group: String, db: String, dryRun: Bool
    ) throws -> MergeResult {
        let store = try store(db)
        let plan = try Portable.merge(
            document, into: try store.snapshot(), newHostsIn: group)
        if !dryRun { try store.apply(plan) }
        return plan.result
    }

    nonisolated func defaultSSHConfigPath() -> String { SSHConfigFile.pathInUse }

    /// How many machines the ssh config names, for the window to offer on a
    /// fresh install. Nil when there is no such file, which is its own answer:
    /// there is nothing to offer.
    nonisolated func sshConfigHosts(path: String = "") -> Int? {
        let path = path.isEmpty ? SSHConfigFile.pathInUse : path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let named = SSHConfigFile.read(path: path).hosts.count
        return named == 0 ? nil : named
    }

    // MARK: files

    /// Opens a file session on a host, and says where it landed.
    func openSFTP(db: String, hostID: String) async throws -> [String: String] {
        let resolved = try resolved(db: db, hostID: hostID)
        let client = try await SFTPClient.connect(resolved)
        let id = Store.newID()
        sessions[id] = client
        return ["id": id, "label": resolved.host.name, "home": await client.home]
    }

    /// What a host says it is, read from its own `/etc/os-release`.
    ///
    /// A connection of its own, opened and closed for this one small file.
    /// The terminal's pty cannot be asked questions — it belongs to whoever is
    /// typing — so the only ways to learn this are a second connection or
    /// guessing from the screen, and a login banner is not a fact.
    ///
    /// Returns nil for every kind of "did not find out", and they are all
    /// ordinary: a host that only takes a password cannot be reached this way
    /// at all, since `connect` fixes `BatchMode=yes`; a BSD or a macOS has no
    /// such file; a container may have no sftp subsystem. **None of them is
    /// worth telling anybody about** — the cost of failing is an icon that
    /// stays generic, which is also what a host nobody has drawn a mark for
    /// looks like.
    /// `path` and `fixed` are both for the suite, and both follow a seam this
    /// app already has rather than inventing one: `connect(_:fixed:)` takes
    /// settings nothing may override — which is how **every** connection the
    /// suite makes is kept off the user's own `~/.ssh` — and
    /// `sshConfigHosts(path:)` takes a path the same way. Without them this
    /// function could not be tested at all without reaching somebody's real
    /// machine, which is why it went untested while everything around it did
    /// not: the read, the parsing, the store and the schedule each have their
    /// own checks and nothing held the wiring between them.
    func osOf(
        db: String, hostID: String,
        path: String = "/etc/os-release", fixed: [String] = []
    ) async -> (id: String, name: String)? {
        guard let resolved = try? resolved(db: db, hostID: hostID),
              let client = try? await SFTPClient.connect(resolved, fixed: fixed)
        else { return nil }
        defer { Task { await client.close() } }
        guard let bytes = try? await client.contents(of: path),
              let text = String(data: bytes, encoding: .utf8)
        else { return nil }
        let id = OSRelease.id(from: text)
        // The id is what finds a mark, so nothing without one is an answer —
        // but a name without an id would leave a host labelled and undrawn.
        return id.isEmpty ? nil : (id, OSRelease.name(from: text))
    }

    func closeSFTP(id: String) async {
        guard let client = sessions.removeValue(forKey: id) else { return }
        await client.close()
    }

    private func session(_ id: String) throws -> SFTPClient {
        guard let client = sessions[id] else { throw CoreError("that file session has closed") }
        return client
    }

    /// A directory on either side. An empty session is this machine, which is
    /// how the left-hand pane asks.
    func list(session id: String, path: String) async throws -> Listing {
        guard !id.isEmpty else { return try Core.listLocally(path) }
        let client = try session(id)
        let full = try await client.realpath(path.isEmpty ? "." : path)
        let entries = try await client.list(full)
        return Listing(
            path: full, parent: Core.parent(of: full), label: "",
            entries: entries.map {
                RemoteEntry(
                    name: $0.name, size: Int64($0.attributes.size ?? 0),
                    mode: $0.attributes.mode,
                    modTime: Core.when($0.attributes.modified),
                    isDir: $0.attributes.isDirectory)
            }.sorted(by: Core.inOrder))
    }

    func makeDirectory(session id: String, path: String) async throws {
        guard !id.isEmpty else {
            try FileManager.default.createDirectory(
                atPath: path, withIntermediateDirectories: false)
            return
        }
        try await session(id).mkdir(path)
    }

    /// On this Mac a deletion goes to the Trash, where it can be taken back,
    /// as it does in every other Mac app; it used to be removed outright. A
    /// host has no such place, so there it is gone.
    func remove(session id: String, path: String) async throws {
        guard !id.isEmpty else {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            return
        }
        try await session(id).remove(path)
    }

    /// Renames a file where it is. The protocol has a request for it, so a
    /// rename is not a download and an upload with a new name.
    func rename(session id: String, from: String, to: String) async throws {
        guard !id.isEmpty else {
            try FileManager.default.moveItem(atPath: from, toPath: to)
            return
        }
        try await session(id).rename(from, to: to)
    }

    // MARK: transfers

    private final class TransferJob {
        var transfer = Transfer()
        var work: Task<Void, Never>?
        /// What to do when its turn comes. Kept rather than started, which is
        /// the whole of the queue.
        var sessionID = ""
        var direction = ""
        var remotePath = ""
        var localPath = ""
        var isDirectory = false
    }

    /// The order they were asked for, which is the order they go in. A
    /// dictionary has none, and without one the queue would pick at random.
    private var transferOrder: [String] = []
    private var transferWidth = TransferQueue.defaultWidth

    /// How many move at once.
    func setTransferWidth(_ width: Int) {
        transferWidth = TransferQueue.clamped(width)
        pumpTransfers()
    }

    /// Takes a transfer and gives it a place in the queue.
    ///
    /// The stat that decides file-or-folder still happens here rather than
    /// when the job starts: a path that is not there should say so while the
    /// person is still looking at the thing they dragged, not after a wait.
    func startTransfer(
        session id: String, direction: String, remotePath: String, localPath: String
    ) async throws -> String {
        let client = try session(id)
        let job = TransferJob()
        let jobID = Store.newID()
        let name = ((direction == "download" ? remotePath : localPath) as NSString)
            .lastPathComponent

        let isDirectory: Bool
        if direction == "download" {
            // Asked once, and not with `try?`: a stat that failed used to
            // read as "not a directory", and a stat that answered something
            // unexpected as "directory" — which quietly ran a directory copy
            // over a file and produced an empty one, with the job reporting
            // done.
            isDirectory = try await client.stat(remotePath).isDirectory
        } else {
            var directory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: localPath, isDirectory: &directory)
            isDirectory = directory.boolValue
        }

        job.transfer = Transfer(
            id: jobID, name: name, kind: isDirectory ? "folder" : "file",
            state: TransferQueue.queued)
        job.sessionID = id
        job.direction = direction
        job.remotePath = remotePath
        job.localPath = localPath
        job.isDirectory = isDirectory
        transfers[jobID] = job
        transferOrder.append(jobID)
        pumpTransfers()
        return jobID
    }

    /// Starts whatever the queue says should be moving, and is called again
    /// every time one finishes — so the next begins the moment there is room.
    private func pumpTransfers() {
        for id in TransferQueue.toStart(orderedTransfers, width: transferWidth) {
            launchTransfer(id)
        }
    }

    private var orderedTransfers: [Transfer] {
        transferOrder.compactMap { transfers[$0]?.transfer }
    }

    private func launchTransfer(_ jobID: String) {
        guard let job = transfers[jobID], let client = try? session(job.sessionID) else {
            settle(jobID, state: TransferQueue.failed, error: "that connection has gone")
            return
        }
        job.transfer.state = TransferQueue.running
        let direction = job.direction
        let isDirectory = job.isDirectory
        let remotePath = job.remotePath
        let localPath = job.localPath

        // An actor is Sendable, so the closure the transfer reports through
        // can hold it rather than a weak reference it would have to unwrap on
        // every chunk. This one is a singleton; there is no cycle to break.
        job.work = Task { [self] in
            let progress: @Sendable (Int64, Int64) -> Void = { done, total in
                Task { await self.progress(jobID, done: done, total: total) }
            }
            do {
                switch (direction, isDirectory) {
                case ("download", true):
                    try await client.downloadDirectory(
                        remotePath, to: localPath, onProgress: progress)
                case ("download", false):
                    try await client.download(remotePath, to: localPath, onProgress: progress)
                case (_, true):
                    try await client.uploadDirectory(
                        localPath, to: (remotePath as NSString).deletingLastPathComponent,
                        onProgress: progress)
                default:
                    try await client.upload(localPath, to: remotePath, onProgress: progress)
                }
                self.settle(jobID, state: TransferQueue.done, error: "")
            } catch is CancellationError {
                self.settle(jobID, state: TransferQueue.cancelled, error: "")
            } catch {
                self.settle(jobID, state: TransferQueue.failed, error: error.localizedDescription)
            }
        }
    }

    private func progress(_ id: String, done: Int64, total: Int64) {
        guard let job = transfers[id] else { return }
        job.transfer.done = done
        job.transfer.total = total
    }

    private func settle(_ id: String, state: String, error: String) {
        guard let job = transfers[id] else { return }
        job.transfer.state = state
        job.transfer.error = error
        if state == TransferQueue.done, job.transfer.total == 0 {
            job.transfer.total = job.transfer.done
        }
        // Somebody's turn has ended, so somebody else's can begin.
        pumpTransfers()
    }

    func transferStatus(id: String) throws -> Transfer {
        guard let job = transfers[id] else { throw CoreError("that transfer has been forgotten") }
        return job.transfer
    }

    /// Calls one off. One still waiting has no work to cancel, so it is
    /// settled here — otherwise it would sit in the queue for ever, holding
    /// a place nothing will ever use.
    func cancelTransfer(id: String) {
        guard let job = transfers[id] else { return }
        if job.transfer.state == TransferQueue.queued {
            settle(id, state: TransferQueue.cancelled, error: "")
        } else {
            job.work?.cancel()
        }
    }

    func forgetTransfer(id: String) {
        transfers[id]?.work?.cancel()
        transfers[id] = nil
        transferOrder.removeAll { $0 == id }
        pumpTransfers()
    }

    // MARK: this machine's own files

    nonisolated static func listLocally(_ path: String) throws -> Listing {
        let manager = FileManager.default
        let folder = path.isEmpty ? manager.homeDirectoryForCurrentUser.path : path
        let names = try manager.contentsOfDirectory(atPath: folder)
        let entries = names.compactMap { name -> RemoteEntry? in
            let full = (folder as NSString).appendingPathComponent(name)
            guard let attributes = try? manager.attributesOfItem(atPath: full) else { return nil }
            let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
            return RemoteEntry(
                name: name, size: (attributes[.size] as? Int64) ?? 0,
                mode: modeText(attributes, isDirectory: isDirectory),
                modTime: when((attributes[.modificationDate] as? Date)
                    .map { UInt32($0.timeIntervalSince1970) }),
                isDir: isDirectory)
        }
        return Listing(
            path: folder, parent: parent(of: folder), label: "",
            entries: entries.sorted(by: inOrder))
    }

    private nonisolated static func modeText(
        _ attributes: [FileAttributeKey: Any], isDirectory: Bool
    ) -> String {
        let permissions = (attributes[.posixPermissions] as? UInt32) ?? 0
        return SFTP.Attributes(permissions: permissions | (isDirectory ? 0x4000 : 0x8000)).mode
    }

    /// Directories first and then by name, which is how a file list reads.
    nonisolated static func inOrder(_ a: RemoteEntry, _ b: RemoteEntry) -> Bool {
        if a.isDir != b.isDir { return a.isDir }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    nonisolated static func parent(of path: String) -> String {
        let up = (path as NSString).deletingLastPathComponent
        return up.isEmpty ? "/" : up
    }

    nonisolated static func when(_ seconds: UInt32?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}

/// What the editor shows about the host being typed: where each empty field
/// would take its value from, and the command the whole of it adds up to.
nonisolated struct HostPreview: Sendable, Equatable {
    var effective = Effective()
    var argv: [String] = []

    /// The command as a line, quoted the way a shell would need it.
    var command: String {
        (["ssh"] + argv).map(SSHArgs.shellQuote).joined(separator: " ")
    }

    /// The command one argument a line, each as ssh will receive it — no
    /// shell quoting, which `command` keeps for pasting — with an option and
    /// its value on one line. For reading: the quoted line of a jump chain
    /// was a wall of `'"'"'`.
    var lines: [Line] {
        guard !argv.isEmpty else { return [] }
        var out = [Line(value: "ssh")]
        var at = 0
        while at < argv.count {
            if Self.takesValue.contains(argv[at]), at + 1 < argv.count {
                out.append(Line(option: argv[at], value: argv[at + 1]))
                at += 2
            } else {
                out.append(Line(value: argv[at]))
                at += 1
            }
        }
        return out
    }

    /// An option and its value, or an argument on its own with no option.
    /// Kept apart so that a long value wraps under itself: wrapped back to
    /// the option, the jump host inside a `ProxyCommand` read as a second
    /// destination.
    nonisolated struct Line: Equatable, Sendable {
        var option = ""
        var value: String

        var text: String { option.isEmpty ? value : "\(option) \(value)" }
    }

    /// The options `ssh` reads a value after, from its manual.
    private static let takesValue: Set<String> = [
        "-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l",
        "-m", "-O", "-o", "-p", "-Q", "-R", "-S", "-W", "-w",
    ]
}

nonisolated struct CoreError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
