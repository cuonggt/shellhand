import Foundation
import Observation

/// One side of the file window: this Mac, or a host.
///
/// Either side can be either thing, which is the point — a pane is a place
/// you choose, not a fixed end of one host's connection. Both start on this
/// Mac, and picking a host from the pane's own menu is what opens a session.
@Observable
@MainActor
final class FilePlace {
    private(set) var host: Host?
    private(set) var listing = Listing()
    private(set) var connecting = false
    private(set) var failure: String?
    /// Off by default, as a file manager shows a home directory without
    /// forty dotfiles in front of what you came for.
    var showHidden = false

    private(set) var session = ""
    /// Whether this side has been pointed anywhere yet. A pane that has not
    /// been is **not** this Mac — it is a question, and says so. Without
    /// this, an unpointed pane reads as "This Mac" with an empty listing,
    /// which looks like an empty home directory.
    private(set) var chosen = false
    private var opening = false
    private let db: String

    init(db: String) { self.db = db }

    var isLocal: Bool { chosen && host == nil }
    var title: String {
        guard chosen else { return "Choose a host" }
        return host?.name ?? "This Mac"
    }

    var entries: [RemoteEntry] {
        showHidden ? listing.entries : listing.entries.filter { !$0.name.hasPrefix(".") }
    }

    var hiddenCount: Int { listing.entries.count - entries.count }

    // MARK: where it is pointed

    /// Points this side at a host, or at this Mac. The session it had goes
    /// with it: a pane showing one machine has no use for another's.
    func use(_ host: Host?) async {
        guard host?.id != self.host?.id || listing.path.isEmpty || !chosen else { return }
        // Set before the connecting starts, so a host that refuses leaves the
        // pane saying what went wrong rather than going back to a question.
        chosen = true
        closeSession()
        self.host = host
        failure = nil
        guard let host else {
            await go(to: FileManager.default.homeDirectoryForCurrentUser.path)
            return
        }
        guard !opening else { return }
        opening = true
        connecting = true
        defer {
            opening = false
            connecting = false
        }
        do {
            let opened = try await Core.shared.openSFTP(db: db, hostID: host.id)
            session = opened["id"] ?? ""
            await go(to: opened["home"] ?? ".")
        } catch {
            failure = error.localizedDescription
            self.host = nil
        }
    }

    func go(to path: String) async {
        do {
            listing = try await Core.shared.list(session: session, path: path)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    func refresh() async { await go(to: listing.path) }

    func parent() async {
        guard !listing.parent.isEmpty, listing.parent != listing.path else { return }
        await go(to: listing.parent)
    }

    /// A child of what this side is showing.
    func path(_ name: String) -> String {
        listing.path.hasSuffix("/") ? listing.path + name : listing.path + "/" + name
    }

    func localURL(named name: String) -> URL { URL(fileURLWithPath: path(name)) }

    // MARK: changing what is there

    func makeDirectory(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try await Core.shared.makeDirectory(session: session, path: path(trimmed))
            await refresh()
        } catch {
            failure = error.localizedDescription
        }
    }

    func rename(_ entry: RemoteEntry, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != entry.name, !trimmed.contains("/") else { return }
        do {
            try await Core.shared.rename(
                session: session, from: path(entry.name), to: path(trimmed))
            await refresh()
        } catch {
            failure = error.localizedDescription
        }
    }

    func remove(_ entries: [RemoteEntry]) async {
        for entry in entries {
            do {
                try await Core.shared.remove(session: session, path: path(entry.name))
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
        }
        await refresh()
    }

    func closeSession() {
        let id = session
        session = ""
        guard !id.isEmpty else { return }
        Task { await Core.shared.closeSFTP(id: id) }
    }
}

/// The file window: two places, and what is going between them.
@Observable
@MainActor
final class FilesModel {
    let left: FilePlace
    let right: FilePlace
    private(set) var transfers: [Transfer] = []
    /// What is being asked about before anything is carried, if anything.
    /// The view draws it; `answer` settles it.
    private(set) var asking: ReplaceQuestion?

    private let db: String

    init(db: String) {
        self.db = db
        left = FilePlace(db: db)
        right = FilePlace(db: db)
    }

    /// The left side is always this Mac. The right is the host this was
    /// opened on, or nothing at all — opened from no host in particular,
    /// it asks for one rather than showing this Mac twice, which told you
    /// nothing and made you choose anyway.
    func start(on host: Host?) async {
        if left.listing.path.isEmpty { await left.use(nil) }
        if let host, !right.chosen { await right.use(host) }
    }

    /// Points the right side at a host, whatever it was showing.
    ///
    /// `start` only fills a side that has not been chosen yet, which is right
    /// on first appearance and wrong for "SFTP on this host" asked a second
    /// time: there is one browser now, so asking again has to move it.
    func show(_ host: Host) async {
        if left.listing.path.isEmpty { await left.use(nil) }
        await right.use(host)
    }

    /// Copies into the other pane's current directory, whichever way round
    /// the two places happen to be.
    ///
    /// Host to host goes through a file here, because SFTP speaks between one
    /// client and one server: there is no request that tells two servers to
    /// talk to each other.
    /// Everything asked for goes into the queue at once, and then this waits.
    ///
    /// Asking for them one at a time would look the same while it ran — the
    /// engine moves a couple at a time either way — but the strip would only
    /// ever show the file in flight. Dropping forty files and being told
    /// "1 moving, 39 waiting" is the difference between a window that is
    /// working and one that has hung.
    func copy(_ entries: [RemoteEntry], from source: FilePlace, to target: FilePlace) async {
        guard let entries = await settle(entries, into: target) else { return }
        var jobs: [String] = []
        for entry in entries {
            switch (source.isLocal, target.isLocal) {
            case (true, true):
                copyLocally(entry, from: source, to: target)
            case (false, true):
                jobs.append(contentsOf: await enqueue(
                    session: source.session, direction: "download",
                    remote: source.path(entry.name), local: target.path(entry.name),
                    name: entry.name, size: entry.size))
            case (true, false):
                jobs.append(contentsOf: await enqueue(
                    session: target.session, direction: "upload",
                    remote: target.path(entry.name), local: source.path(entry.name),
                    name: entry.name, size: entry.size))
            case (false, false):
                // Two hops with a file of ours in the middle, so this one
                // cannot be handed over and left: the upload has nothing to
                // send until the download has finished.
                await relay(entry, from: source, to: target)
            }
        }
        await watch(jobs)
        await target.refresh()
    }

    /// A local file dropped onto a pane from Finder.
    func bring(_ url: URL, to target: FilePlace) async {
        let name = url.lastPathComponent
        let clashes = Replacing.clashes(
            carrying: [name], arriving: target.listing.entries.map(\.name),
            caseInsensitive: target.isLocal)
        if !clashes.isEmpty, await ask(clashes, into: target) != .replace { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
            ?? 0
        if target.isLocal {
            // Removed first: `copyItem` throws onto a name already there, and
            // the `try?` here swallowed it — a drop from Finder onto an
            // existing file used to do nothing at all, silently.
            try? FileManager.default.removeItem(atPath: target.path(name))
            try? FileManager.default.copyItem(atPath: url.path, toPath: target.path(name))
        } else {
            await run(session: target.session, direction: "upload",
                      remote: target.path(name), local: url.path, name: name, size: size)
        }
        await target.refresh()
    }

    /// What is left to carry once the far end has been asked about.
    ///
    /// `nil` means the whole thing was called off. The target's listing is
    /// already in hand — both panes list what they hold — so this costs no
    /// round trip to the server.
    private func settle(
        _ entries: [RemoteEntry], into target: FilePlace
    ) async -> [RemoteEntry]? {
        let clashes = Replacing.clashes(
            carrying: entries.map(\.name),
            arriving: target.listing.entries.map(\.name),
            caseInsensitive: target.isLocal)
        guard !clashes.isEmpty else { return entries }
        guard let answer = await ask(clashes, into: target) else { return nil }
        let keep = Set(Replacing.carrying(
            entries.map(\.name), clashes: clashes, answer: answer))
        return entries.filter { keep.contains($0.name) }
    }

    /// Puts the question up and waits for it. `nil` is Cancel.
    private func ask(_ clashes: [String], into target: FilePlace) async -> Replacing.Answer? {
        await withCheckedContinuation { continuation in
            asking = ReplaceQuestion(
                clashes: clashes, into: target.title, reply: continuation)
        }
    }

    /// Answers whatever is being asked. Called by the dialog, and by its
    /// dismissal, so the waiting copy is never left hanging.
    func answer(_ answer: Replacing.Answer?) {
        guard let asking else { return }
        self.asking = nil
        asking.reply.resume(returning: answer)
    }

    private func copyLocally(_ entry: RemoteEntry, from source: FilePlace, to target: FilePlace) {
        let at = source.path(entry.name), into = target.path(entry.name)
        guard at != into else { return }
        try? FileManager.default.removeItem(atPath: into)
        do {
            try FileManager.default.copyItem(atPath: at, toPath: into)
        } catch {
            transfers.append(Transfer(
                id: UUID().uuidString, name: entry.name, kind: "file",
                state: TransferQueue.failed,
                error: error.localizedDescription))
        }
    }

    /// Down to a file of ours, then up to the other host. Nothing is left
    /// behind: the middle of a host-to-host copy is not somebody's Downloads
    /// folder.
    private func relay(_ entry: RemoteEntry, from source: FilePlace, to target: FilePlace) async {
        let staging = NSTemporaryDirectory() + "shellhand-relay-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: staging) }
        let waypoint = staging + "/" + entry.name

        await run(session: source.session, direction: "download",
                  remote: source.path(entry.name), local: waypoint,
                  name: entry.name, size: entry.size)
        guard transfers.last?.state == TransferQueue.done else { return }
        transfers.removeLast()
        await run(session: target.session, direction: "upload",
                  remote: target.path(entry.name), local: waypoint,
                  name: entry.name, size: entry.size)
    }

    private func run(
        session: String, direction: String, remote: String, local: String,
        name: String, size: Int64
    ) async {
        await watch(await enqueue(
            session: session, direction: direction, remote: remote, local: local,
            name: name, size: size))
    }

    /// Hands a transfer to the queue and comes straight back. The job's id,
    /// or nothing when it could not even be queued — which is a failure worth
    /// showing in the strip rather than swallowing.
    private func enqueue(
        session: String, direction: String, remote: String, local: String,
        name: String, size: Int64
    ) async -> [String] {
        guard !session.isEmpty else { return [] }
        do {
            let job = try await Core.shared.startTransfer(
                session: session, direction: direction, remotePath: remote, localPath: local)
            transfers.append(Transfer(id: job, name: name, total: size))
            return [job]
        } catch {
            transfers.append(Transfer(
                id: UUID().uuidString, name: name, state: TransferQueue.failed,
                error: error.localizedDescription))
            return []
        }
    }

    /// Follows a run of transfers to the end. What moves when is the engine's
    /// business; this only keeps the strip current.
    private func watch(_ jobs: [String]) async {
        var left = Set(jobs)
        while !left.isEmpty {
            try? await Task.sleep(for: .milliseconds(200))
            for job in left {
                guard let status = try? await Core.shared.transferStatus(id: job) else {
                    left.remove(job)
                    continue
                }
                if let at = transfers.firstIndex(where: { $0.id == job }) { transfers[at] = status }
                if status.finished { left.remove(job) }
            }
        }
    }

    func cancel(_ transfer: Transfer) {
        let id = transfer.id
        Task { await Core.shared.cancelTransfer(id: id) }
    }

    func clearFinished() {
        for transfer in transfers where transfer.finished {
            let id = transfer.id
            Task { await Core.shared.forgetTransfer(id: id) }
        }
        transfers.removeAll(where: \.finished)
    }

    func close() {
        left.closeSession()
        right.closeSession()
    }
}

/// A question about names already at the far end, waiting on an answer.
///
/// It carries the continuation the copy is parked on, so the dialog's buttons
/// and its dismissal both land in the same place — a copy waiting on an
/// answer nobody can give is worse than one that overwrites.
@MainActor
struct ReplaceQuestion: Identifiable {
    let id = UUID()
    let clashes: [String]
    let into: String
    let reply: CheckedContinuation<Replacing.Answer?, Never>

    var said: String { Replacing.question(clashes, into: into) }

    /// Singular where there is one, because "Skip them" over a single file
    /// reads as though something else is being left behind too.
    var skipping: String { clashes.count == 1 ? "Skip it" : "Skip them" }
    var replacing: String { clashes.count == 1 ? "Replace" : "Replace them" }
}
