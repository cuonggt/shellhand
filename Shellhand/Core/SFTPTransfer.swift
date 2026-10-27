import Foundation

extension SFTPClient {
    /// How much is asked for at once. 32 KiB is what OpenSSH's own client
    /// uses, and what its server will answer in one packet.
    static var chunk: Int { 32 << 10 }
    /// How many reads are in the air at once. One at a time spends most of a
    /// transfer waiting for the network rather than using it; a window of
    /// eight keeps it busy without asking the far end to buffer much.
    static var window: Int { 8 }

    /// Brings a file down, saying how far along it is as it goes.
    ///
    /// Only whole chunks are committed. A server may answer a read with fewer
    /// bytes than were asked for — it is allowed to — and the window would
    /// otherwise skip the rest of that chunk and write a file with a hole in
    /// it, which is the kind of corruption nobody notices until much later.
    func download(
        _ remote: String, to local: String, onProgress: @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws {
        let attributes = try? await stat(remote)
        /// What the far end says the file is, or nil where it would not say.
        /// **Not the same as zero**, which is why this is an optional: see the
        /// check at the end.
        let expected = attributes?.size.map { Int64($0) }
        let total = expected ?? 0
        let handle = try await openFile(remote, flags: .read)
        defer { Task { try? await self.closeHandle(handle) } }

        FileManager.default.createFile(atPath: local, contents: nil)
        guard let out = FileHandle(forWritingAtPath: local) else {
            throw SFTPError("\(local) could not be written")
        }
        // Taken once, while the handle is certainly open: asking a closed
        // `FileHandle` for its descriptor raises the same ObjC exception that
        // writing through one does.
        let localDescriptor = out.fileDescriptor
        defer { try? out.close() }

        var offset: UInt64 = 0
        var done: Int64 = 0
        onProgress(0, total)
        while true {
            try Task.checkCancellation()
            let size = SFTPClient.chunk
            let offsets = (0..<SFTPClient.window).map { offset + UInt64($0 * size) }
            let parts = try await withThrowingTaskGroup(of: (UInt64, Data).self) { group in
                for at in offsets {
                    group.addTask {
                        (at, try await self.read(handle, at: at, count: UInt32(size)))
                    }
                }
                var collected: [UInt64: Data] = [:]
                for try await (at, data) in group { collected[at] = data }
                return collected
            }

            var advanced = 0
            var finished = false
            for at in offsets {
                let data = parts[at] ?? Data()
                if data.isEmpty {
                    finished = true
                    break
                }
                try Self.writeAll(
                    data, to: localDescriptor, failing: "\(local) could not be written")
                advanced += data.count
                done += Int64(data.count)
                // A short answer means the rest of that chunk is still to
                // come, so the next pass starts there.
                if data.count < size {
                    break
                }
            }
            onProgress(done, max(total, done))
            offset += UInt64(advanced)
            if finished || advanced == 0 { break }
        }

        // A file that arrives short is a file with a piece missing, and
        // nothing downstream would notice: the handle closes, the job says
        // done, and what is on disk is wrong. Nothing at all is the same
        // failure, and the one that was happening.
        //
        // What counts as short depends on whether the far end gave a size at
        // all. Where it did, the answer has to match it exactly — and that
        // includes matching **zero**, because an empty file is a real file and
        // nothing arriving is exactly right for one. Reading "stat said zero"
        // and "stat would not say" as the same number made every empty file
        // impossible to carry: `done == 0` fired on both. Where there is no
        // size to check against, nothing at all is still worth catching.
        let short = expected.map { done != $0 } ?? (done == 0)
        if short {
            let stray = strayReplies
            throw SFTPError(
                "\(remote): \(done) of \(total) bytes arrived"
                    + (stray > 0 ? " — \(stray) replies came back unasked for" : ""))
        }
    }

    /// Sends a file up. Written in order, because the bytes come off a local
    /// disk faster than they can be put on the wire anyway.
    func upload(
        _ local: String, to remote: String,
        onProgress: @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws {
        guard let input = FileHandle(forReadingAtPath: local) else {
            throw SFTPError("\(local) could not be read")
        }
        defer { try? input.close() }
        let total = Int64(
            (try? FileManager.default.attributesOfItem(atPath: local)[.size] as? Int64) ?? 0)

        let handle = try await openFile(remote, flags: [.write, .create, .truncate])
        defer { Task { try? await self.closeHandle(handle) } }

        var offset: UInt64 = 0
        var done: Int64 = 0
        onProgress(0, total)
        while true {
            try Task.checkCancellation()
            guard let data = try input.read(upToCount: SFTPClient.chunk), !data.isEmpty else {
                break
            }
            try await write(handle, at: offset, data)
            offset += UInt64(data.count)
            done += Int64(data.count)
            onProgress(done, max(total, done))
        }
    }

    /// A directory and everything under it, in whichever direction.
    ///
    /// The count is of bytes rather than files, so a folder of one large file
    /// and a folder of a thousand small ones both report something that moves
    /// at a sensible rate.
    ///
    /// **Every folder is made before any file is written** — the destination
    /// itself first. A folder used to be made only as the parent of a file
    /// about to land in it, so one with no file beneath it at any depth was
    /// never made at all: every empty folder in a tree was left out, and an
    /// empty folder downloaded as nothing while the transfer reported success.
    /// Uploads always made each folder they met, so the two directions
    /// disagreed, and a folder sent up and brought back lost them on the way.
    func downloadDirectory(
        _ remote: String, to local: String,
        onProgress: @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws {
        var folders = [local]
        var files: [(String, String, Int64)] = []
        try await walk(remote, local: local, folders: &folders, files: &files)
        for folder in folders {
            try FileManager.default.createDirectory(
                atPath: folder, withIntermediateDirectories: true)
        }
        let total = files.reduce(0) { $0 + $1.2 }
        var done: Int64 = 0
        for (from, to, size) in files {
            try Task.checkCancellation()
            let before = done
            try await download(from, to: to) { moved, _ in
                onProgress(before + moved, total)
            }
            done = before + size
            onProgress(done, total)
        }
    }

    /// Every folder and file under `remote`, mapped to where it lands under
    /// `local`, each folder before what is in it.
    private func walk(
        _ remote: String, local: String,
        folders: inout [String], files: inout [(String, String, Int64)]
    ) async throws {
        for entry in try await list(remote) {
            let from = remote.hasSuffix("/") ? remote + entry.name : remote + "/" + entry.name
            let to = (local as NSString).appendingPathComponent(entry.name)
            if entry.attributes.isDirectory {
                folders.append(to)
                try await walk(from, local: to, folders: &folders, files: &files)
            } else if !entry.attributes.isSymlink {
                files.append((from, to, Int64(entry.attributes.size ?? 0)))
            }
        }
    }

    /// Makes a folder, treating one already there as made and every other
    /// refusal as a failure.
    ///
    /// This replaces a `try?`, half of which was deliberate: carrying a folder
    /// onto one that already exists has to merge rather than fail, so an
    /// upload cannot simply insist on making every folder. It swallowed a real
    /// refusal with it — and an **empty** folder is where nothing else would
    /// notice, since a folder with files under it surfaces the refusal through
    /// the files' own failures while an empty one vanishes with the job
    /// reporting done. That is the download side's bug from 0.0.8 wearing the
    /// other direction's clothes.
    ///
    /// The far end is **asked** rather than the status read, the way `remove`
    /// asks what a path is before deciding what to send: SFTP 3 has no
    /// "already exists" status — that arrived in version 4 — so OpenSSH
    /// answers a name already taken with the same `SSH_FX_FAILURE` it gives a
    /// read-only disk, and no code can tell them apart. The original error is
    /// what gets thrown, not the `stat`'s, because it carries the far end's
    /// own sentence about what it refused.
    private func makeFolder(_ path: String) async throws {
        do {
            try await mkdir(path)
        } catch {
            guard let there = try? await stat(path), there.isDirectory else { throw error }
        }
    }

    func uploadDirectory(
        _ local: String, to remote: String,
        onProgress: @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws {
        let base = (local as NSString).lastPathComponent
        let root = remote.hasSuffix("/") ? remote + base : remote + "/" + base
        try await makeFolder(root)

        let manager = FileManager.default
        var files: [(String, String, Int64)] = []
        let enumerator = manager.enumerator(atPath: local)
        while let relative = enumerator?.nextObject() as? String {
            let from = (local as NSString).appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: from, isDirectory: &isDirectory) else { continue }
            let to = root + "/" + relative
            if isDirectory.boolValue {
                try await makeFolder(to)
            } else {
                let size = (try? manager.attributesOfItem(atPath: from)[.size] as? Int64) ?? 0
                files.append((from, to, size))
            }
        }

        let total = files.reduce(0) { $0 + $1.2 }
        var done: Int64 = 0
        for (from, to, size) in files {
            try Task.checkCancellation()
            let before = done
            try await upload(from, to: to) { moved, _ in onProgress(before + moved, total) }
            done = before + size
            onProgress(done, total)
        }
    }
}
