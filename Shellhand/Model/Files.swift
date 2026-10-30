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
    /// How many times a session has actually been opened.
    ///
    /// The guard on `opening` is the only thing stopping two calls in flight
    /// at once from becoming two connections, and it has **no other outward
    /// sign**: one open and two look identical from outside once both have
    /// finished, which is exactly how the bug it prevents went unnoticed.
    /// `ticks` on a terminal session is here for the same reason.
    private(set) var opens = 0
    private let db: String
    /// Where this Mac opens. The home directory, except under test: a pane
    /// opened on the real one reads the attributes of Desktop, Documents and
    /// Downloads, which puts up a privacy prompt whenever the build's
    /// signature is not the one macOS remembers — and the read waits until
    /// somebody answers it.
    private let home: String

    init(db: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.db = db
        self.home = home
    }

    /// The session this side's operations go through, or nil while it has
    /// none to offer. `Places.session` says why that is not just `session`.
    var via: String? { Places.session(chosen: chosen, onAHost: host != nil, open: session) }

    // The rules themselves are in `Places`, where they can be asked without
    // opening a session to find out the answer.
    var isLocal: Bool { Places.isLocal(chosen: chosen, onAHost: host != nil) }
    var title: String { Places.title(chosen: chosen, host: host?.name) }

    var entries: [RemoteEntry] { Places.shown(listing.entries, hidden: showHidden) }

    var hiddenCount: Int { Places.hiddenCount(listing.entries, hidden: showHidden) }

    // MARK: where it is pointed

    /// Points this side at a host, or at this Mac. The session it had goes
    /// with it: a pane showing one machine has no use for another's.
    func use(_ host: Host?) async {
        guard host?.id != self.host?.id || listing.path.isEmpty || !chosen else { return }
        // Set before the connecting starts, so a host that refuses leaves the
        // pane saying what went wrong rather than going back to a question.
        chosen = true
        closeSession()
        // What the last place held goes now, not when the next one answers.
        // Left up, it could be acted on with no session behind it — and no
        // session is this Mac, so a Delete removed the same path here while
        // the dialog named the host.
        listing = Listing()
        self.host = host
        failure = nil
        guard let host else {
            await go(to: home)
            return
        }
        guard !opening else { return }
        opening = true
        opens += 1
        connecting = true
        defer {
            opening = false
            connecting = false
        }
        do {
            let opened = try await Core.shared.openSFTP(db: db, hostID: host.id)
            // Pointed somewhere else while this was connecting: what it opened
            // is not what the pane names, so it goes rather than being listed
            // under the other host's name.
            guard self.host?.id == host.id else {
                if let id = opened["id"] { Task { await Core.shared.closeSFTP(id: id) } }
                return
            }
            session = opened["id"] ?? ""
            await go(to: opened["home"] ?? ".")
        } catch {
            // The host stays named: the pane is still pointed at it, and says
            // why it shows nothing, rather than calling itself this Mac.
            guard self.host?.id == host.id else { return }
            failure = error.localizedDescription
        }
    }

    func go(to path: String) async {
        guard let via else { return }
        do {
            listing = try await Core.shared.list(session: via, path: path)
            failure = nil
        } catch {
            failure = "Couldn't open \(path): \(error.localizedDescription)"
        }
    }

    /// Takes what went wrong off the pane, once it has been read.
    func clearFailure() { failure = nil }

    func refresh() async { await go(to: listing.path) }

    func parent() async {
        guard !listing.parent.isEmpty, listing.parent != listing.path else { return }
        await go(to: listing.parent)
    }

    /// A child of what this side is showing.
    func path(_ name: String) -> String { Places.path(listing.path, name) }

    func localURL(named name: String) -> URL { URL(fileURLWithPath: path(name)) }

    // MARK: changing what is there

    func makeDirectory(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let via else { return }
        do {
            try await Core.shared.makeDirectory(session: via, path: path(trimmed))
            await refresh()
        } catch {
            failure = "Couldn't make the folder “\(trimmed)”: \(error.localizedDescription)"
        }
    }

    func rename(_ entry: RemoteEntry, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != entry.name, !trimmed.contains("/"),
              let via else { return }
        do {
            try await Core.shared.rename(
                session: via, from: path(entry.name), to: path(trimmed))
            await refresh()
        } catch {
            failure = "Couldn't rename “\(entry.name)”: \(error.localizedDescription)"
        }
    }

    func remove(_ entries: [RemoteEntry]) async {
        guard let via else { return }
        var refused: String?
        for entry in entries {
            do {
                try await Core.shared.remove(session: via, path: path(entry.name))
            } catch {
                // SFTP removes a folder only once it is empty, and a server
                // says no to that in the same words as to anything else.
                let why = entry.isDir && !isLocal
                    ? " SFTP deletes a folder only once it is empty." : ""
                refused = "Couldn't delete “\(entry.name)”: "
                    + Places.sentence(error.localizedDescription) + why
            }
        }
        await refresh()
        // After the refresh, which clears a failure when the listing comes
        // back, so that what went wrong is still there to read.
        if let refused { failure = refused }
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

    init(db: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.db = db
        left = FilePlace(db: db, home: home)
        right = FilePlace(db: db, home: home)
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
        // Both ends have to be somewhere. A pane still connecting, or turned
        // away, has no session, and to the engine no session is this Mac.
        guard let from = source.via, let into = target.via else { return }
        guard let entries = await settle(entries, into: target) else { return }
        var jobs: [String] = []
        for entry in entries {
            switch (source.isLocal, target.isLocal) {
            case (true, true):
                copyLocally(entry, from: source, to: target)
            case (false, true):
                jobs.append(contentsOf: await enqueue(
                    session: from, direction: "download",
                    remote: source.path(entry.name), local: target.path(entry.name),
                    name: entry.name, size: entry.size))
            case (true, false):
                jobs.append(contentsOf: await enqueue(
                    session: into, direction: "upload",
                    remote: target.path(entry.name), local: source.path(entry.name),
                    name: entry.name, size: entry.size))
            case (false, false):
                // Two hops with a file of ours in the middle, so this one
                // cannot be handed over and left: the upload has nothing to
                // send until the download has finished.
                await relay(entry, from: source, through: from, to: target, through: into)
            }
        }
        await watch(jobs)
        await target.refresh()
    }

    /// A local file dropped onto a pane from Finder.
    func bring(_ url: URL, to target: FilePlace) async {
        guard let into = target.via else { return }
        let name = url.lastPathComponent
        let clashes = Replacing.clashes(
            carrying: [name], arriving: target.listing.entries.map(\.name),
            caseInsensitive: target.isLocal)
        if !clashes.isEmpty, await ask(clashes, into: target) != .replace { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
            ?? 0
        if target.isLocal {
            copyOnThisDisk(from: url.path, to: target.path(name), name: name)
        } else {
            await run(session: into, direction: "upload",
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
        copyOnThisDisk(from: at, to: into, name: entry.name)
    }

    /// A copy on this disk, with a refusal reported rather than swallowed.
    ///
    /// **Both local paths go through here, and that is the point.** A drag
    /// between the two panes caught a failed `copyItem` and filed it; a drop
    /// from Finder used `try?` for the identical call, so a copy the disk
    /// refused — no permission on the destination, a full disk, the source
    /// gone between the drop and the copy — did nothing and said nothing. No
    /// row, no error, and the pane redrawn without the file, which reads as a
    /// drop nobody asked for. Two copies of one decision is how they drifted,
    /// the same way two copies of a write loop let the harness keep a bug the
    /// engine had already had fixed.
    ///
    /// Removing first is deliberate and stays a `try?`: `copyItem` throws onto
    /// a name already there, the replace question has been answered by the
    /// time anything reaches here, and a remove that fails because there was
    /// nothing to remove is not a failure. A remove that fails for a real
    /// reason surfaces as the copy failing a line later.
    private func copyOnThisDisk(from: String, to: String, name: String) {
        try? FileManager.default.removeItem(atPath: to)
        do {
            try FileManager.default.copyItem(atPath: from, toPath: to)
        } catch {
            transfers.append(Transfer(
                id: UUID().uuidString, name: name, kind: "file",
                state: TransferQueue.failed,
                error: error.localizedDescription))
        }
    }

    /// Down to a file of ours, then up to the other host. Nothing is left
    /// behind: the middle of a host-to-host copy is not somebody's Downloads
    /// folder.
    private func relay(
        _ entry: RemoteEntry, from source: FilePlace, through from: String,
        to target: FilePlace, through into: String
    ) async {
        let staging = NSTemporaryDirectory() + "shellhand-relay-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: staging) }
        let waypoint = staging + "/" + entry.name

        await run(session: from, direction: "download",
                  remote: source.path(entry.name), local: waypoint,
                  name: entry.name, size: entry.size)
        guard transfers.last?.state == TransferQueue.done else { return }
        transfers.removeLast()
        await run(session: into, direction: "upload",
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

    /// Letting go of the window: both sessions end, and anything still being
    /// asked is answered.
    ///
    /// The question goes **first**, and the answer is Cancel. First, because
    /// closing the sessions underneath a parked copy would resume it into a
    /// session that has gone and report a failed transfer in a window that is
    /// on its way out; Cancel, because nothing should be carried on the way
    /// through a door. This is also the one dismissal the dialog's own binding
    /// cannot cover — it answers Cancel when `isPresented` is set to false,
    /// and here there is no view left to set it.
    func close() {
        answer(nil)
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

    var skipping: String { Places.skipping(clashes.count) }
    var replacing: String { Places.replacing(clashes.count) }
}
