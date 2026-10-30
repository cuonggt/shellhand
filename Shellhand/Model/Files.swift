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

    /// Try Again, on a host that would not open: the host's name stays on
    /// the pane, so another go is what the pane can offer.
    func tryAgain() async {
        guard let host else { return }
        await use(host)
    }

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
    /// The side the window's keys act on: the one whose list was last used.
    /// ⌘R and ⇧⌘N are its own buttons', so there is no asking which side.
    var active: FilePlace
    private(set) var transfers: [Transfer] = []
    /// What is being asked about before anything is carried, if anything.
    /// The view draws it; `answer` settles it.
    private(set) var asking: ReplaceQuestion?

    private let db: String
    /// For writing a folder on this Mac from `~` in the strip.
    private let home: String
    /// How each transfer in the strip was started, so that a failed one can
    /// be started again: the engine keeps no paths once a job has ended, and
    /// a relay between two hosts is two jobs with a file in the middle.
    private var recipes: [String: Recipe] = [:]

    init(db: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.db = db
        self.home = home
        let left = FilePlace(db: db, home: home)
        self.left = left
        right = FilePlace(db: db, home: home)
        active = left
    }

    /// One file or folder handed to the engine.
    private struct Carry {
        var session: String
        var direction: String
        var remote: String
        var local: String
        var name: String
        var size: Int64
    }

    private enum Recipe {
        case carry(Carry)
        /// Down from one host and up to the other, through a file of ours
        /// made afresh each time.
        case relay(name: String, size: Int64, from: String, source: String, into: String, target: String)
        case local(from: String, to: String, name: String)
    }

    /// Which way a transfer goes, as the strip says it.
    private struct Way {
        var from: String
        var to: String
        var into: String
    }

    private func heading(from source: FilePlace, to target: FilePlace) -> Way {
        let folder = target.listing.path
        return Way(from: source.title, to: target.title,
                   into: target.isLocal ? Places.abbreviated(folder, home: home) : folder)
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
        let way = heading(from: source, to: target)
        var jobs: [String] = []
        for entry in entries {
            switch (source.isLocal, target.isLocal) {
            case (true, true):
                copyLocally(entry, from: source, to: target, way: way)
            case (false, true):
                jobs.append(contentsOf: await enqueue(Carry(
                    session: from, direction: "download",
                    remote: source.path(entry.name), local: target.path(entry.name),
                    name: entry.name, size: entry.size), way: way))
            case (true, false):
                jobs.append(contentsOf: await enqueue(Carry(
                    session: into, direction: "upload",
                    remote: target.path(entry.name), local: source.path(entry.name),
                    name: entry.name, size: entry.size), way: way))
            case (false, false):
                // Two hops with a file of ours in the middle, so this one
                // cannot be handed over and left: the upload has nothing to
                // send until the download has finished.
                await relay(name: entry.name, size: entry.size,
                            from: from, source: source.path(entry.name),
                            into: into, target: target.path(entry.name), way: way)
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
        let way = Way(from: Places.title(chosen: true, host: nil), to: target.title,
                      into: heading(from: target, to: target).into)
        if target.isLocal {
            copyOnThisDisk(from: url.path, to: target.path(name), name: name, way: way)
        } else {
            await watch(await enqueue(Carry(
                session: into, direction: "upload",
                remote: target.path(name), local: url.path, name: name, size: size), way: way))
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

    private func copyLocally(
        _ entry: RemoteEntry, from source: FilePlace, to target: FilePlace, way: Way
    ) {
        let at = source.path(entry.name), into = target.path(entry.name)
        guard at != into else { return }
        copyOnThisDisk(from: at, to: into, name: entry.name, way: way)
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
    @discardableResult
    private func copyOnThisDisk(
        from: String, to: String, name: String, way: Way, at index: Int? = nil
    ) -> Bool {
        try? FileManager.default.removeItem(atPath: to)
        do {
            try FileManager.default.copyItem(atPath: from, toPath: to)
            return true
        } catch {
            let row = Transfer(
                id: UUID().uuidString, name: name, kind: "file",
                state: TransferQueue.failed, error: error.localizedDescription,
                from: way.from, to: way.to, into: way.into)
            put(row, at: index)
            recipes[row.id] = .local(from: from, to: to, name: name)
            return false
        }
    }

    /// Down to a file of ours, then up to the other host. Nothing is left
    /// behind: the middle of a host-to-host copy is not somebody's Downloads
    /// folder.
    private func relay(
        name: String, size: Int64, from: String, source: String,
        into: String, target: String, way: Way, at index: Int? = nil
    ) async {
        let recipe = Recipe.relay(
            name: name, size: size, from: from, source: source, into: into, target: target)
        let staging = NSTemporaryDirectory() + "shellhand-relay-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: staging) }
        let waypoint = staging + "/" + name

        let down = await enqueue(Carry(
            session: from, direction: "download", remote: source, local: waypoint,
            name: name, size: size), way: way, at: index, recipe: recipe)
        await watch(down)
        // Found by its own id: with other copies under way, the last row in
        // the strip need not be this one.
        guard let job = down.first, let row = transfers.firstIndex(where: { $0.id == job }),
              transfers[row].state == TransferQueue.done else { return }
        transfers.remove(at: row)
        recipes[job] = nil
        Task { await Core.shared.forgetTransfer(id: job) }
        await watch(await enqueue(Carry(
            session: into, direction: "upload", remote: target, local: waypoint,
            name: name, size: size), way: way, at: row, recipe: recipe))
    }

    /// Hands a transfer to the queue and comes straight back. The job's id,
    /// or nothing when it could not even be queued — which is a failure worth
    /// showing in the strip rather than swallowing.
    private func enqueue(
        _ carry: Carry, way: Way, at index: Int? = nil, recipe: Recipe? = nil
    ) async -> [String] {
        guard !carry.session.isEmpty else { return [] }
        let row: Transfer
        var jobs: [String] = []
        do {
            let job = try await Core.shared.startTransfer(
                session: carry.session, direction: carry.direction,
                remotePath: carry.remote, localPath: carry.local)
            row = Transfer(id: job, name: carry.name, total: carry.size,
                           from: way.from, to: way.to, into: way.into)
            jobs = [job]
        } catch {
            row = Transfer(
                id: UUID().uuidString, name: carry.name, state: TransferQueue.failed,
                error: error.localizedDescription,
                from: way.from, to: way.to, into: way.into)
        }
        put(row, at: index)
        recipes[row.id] = recipe ?? .carry(carry)
        return jobs
    }

    /// A row in the strip: at the end, or where the row it retries stood.
    private func put(_ row: Transfer, at index: Int?) {
        if let index, index <= transfers.count {
            transfers.insert(row, at: index)
        } else {
            transfers.append(row)
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
                if let at = transfers.firstIndex(where: { $0.id == job }) {
                    transfers[at] = status.labelled(like: transfers[at])
                }
                if status.finished { left.remove(job) }
            }
        }
    }

    func cancel(_ transfer: Transfer) {
        let id = transfer.id
        Task { await Core.shared.cancelTransfer(id: id) }
    }

    /// Whether a failed transfer can be started again: the sessions it went
    /// through are still the panes' own. A pane pointed somewhere else since
    /// has closed the one it used, and a retry into that would only fail.
    func canRetry(_ transfer: Transfer) -> Bool {
        guard transfer.state == TransferQueue.failed, let recipe = recipes[transfer.id] else {
            return false
        }
        let open = Set([left.via, right.via].compactMap { $0 })
        switch recipe {
        case let .carry(carry): return open.contains(carry.session)
        case let .relay(_, _, from, _, into, _): return open.contains(from) && open.contains(into)
        case .local: return true
        }
    }

    /// Starts a failed transfer again, in its own row's place in the strip.
    func retry(_ transfer: Transfer) async {
        guard canRetry(transfer), let recipe = recipes[transfer.id],
              let index = transfers.firstIndex(where: { $0.id == transfer.id })
        else { return }
        transfers.remove(at: index)
        recipes[transfer.id] = nil
        let id = transfer.id
        Task { await Core.shared.forgetTransfer(id: id) }
        let way = Way(from: transfer.from, to: transfer.to, into: transfer.into)
        switch recipe {
        case let .carry(carry):
            await watch(await enqueue(carry, way: way, at: index))
        case let .relay(name, size, from, source, into, target):
            await relay(name: name, size: size, from: from, source: source,
                        into: into, target: target, way: way, at: index)
        case let .local(from, to, name):
            // A first copy on this disk that works leaves no row behind; one
            // that works when retried leaves its own, so the retry is seen.
            if copyOnThisDisk(from: from, to: to, name: name, way: way, at: index) {
                put(Transfer(id: UUID().uuidString, name: name, kind: "file",
                             state: TransferQueue.done,
                             from: way.from, to: way.to, into: way.into), at: index)
            }
        }
        await left.refresh()
        await right.refresh()
    }

    func clearFinished() {
        for transfer in transfers where transfer.finished {
            let id = transfer.id
            recipes[id] = nil
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
