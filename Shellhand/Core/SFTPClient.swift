import Foundation

/// A file session on a host.
///
/// OpenSSH does the transport and this does the packets: `ssh -s sftp` starts
/// the server on the far end and hands back a pipe, so the connection is made
/// by the same ssh, with the same key, config, jump hosts and host-key checks
/// as every other connection the app makes. Nothing here implements any part
/// of SSH itself.
actor SFTPClient {
    private let process: Process
    private let toServer: FileHandle
    /// Taken once, while the handle is certainly open, because asking a closed
    /// `FileHandle` for its descriptor raises one of the very exceptions this
    /// exists to avoid.
    private let outDescriptor: Int32
    private let fromServer: FileHandle
    private var nextRequest: UInt32 = 1
    private var waiting: [UInt32: CheckedContinuation<Reply, Error>] = [:]
    private var ended: SFTPError?
    /// Replies that arrived with an id nothing was waiting for. More than
    /// none means the conversation has lost its place.
    private(set) var strayReplies = 0

    /// The directory the session started in, which is where the browser opens.
    private(set) var home = "."

    struct Reply: Sendable {
        var type: SFTP.PacketType
        var body: Data
    }

    private init(process: Process, toServer: FileHandle, fromServer: FileHandle) {
        self.process = process
        self.toServer = toServer
        self.outDescriptor = toServer.fileDescriptor
        self.fromServer = fromServer
        // A write to a pipe nothing is reading raises SIGPIPE, which ends the
        // process outright instead of returning — so turning that signal off
        // for this one descriptor is what makes the error reportable at all.
        // Measured: without it a broken pipe killed the test host with no
        // exception and no message, which reads as a vanished process rather
        // than a failed write. Per descriptor rather than
        // `signal(SIGPIPE, SIG_IGN)`, which would be a decision about the
        // whole app made from inside one file session.
        _ = fcntl(outDescriptor, F_SETNOSIGPIPE, 1)
    }

    /// Opens a session to a host.
    ///
    /// BatchMode is fixed rather than preferred: the child's stdin carries the
    /// protocol, so a password prompt is one nobody can answer, and a single
    /// `-o BatchMode=no` from the config was once enough to leave a session
    /// waiting at one forever.
    static func connect(_ resolved: Resolved) async throws -> SFTPClient {
        let args = SSHArgs.subsystem(resolved, "sftp", fixed: SSHArgs.unattended)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = args
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw SFTPError("ssh could not be started: \(error.localizedDescription)")
        }

        let client = SFTPClient(
            process: process, toServer: input.fileHandleForWriting,
            fromServer: output.fileHandleForReading)
        await client.startReading()
        do {
            try await client.handshake()
        } catch {
            // ssh says why on its own stream, and that sentence is the useful
            // one: "Permission denied", "Host key verification failed".
            let said = (try? errors.fileHandleForReading.readToEnd())
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
            await client.close()
            let detail = said.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SFTPError(detail.isEmpty ? (error as? SFTPError)?.message ?? "the file session could not be opened" : detail)
        }
        let home = (try? await client.realpath(".")) ?? "."
        await client.setHome(home)
        return client
    }

    private func setHome(_ path: String) { home = path }

    /// A client speaking to handles somebody else owns, already reading.
    ///
    /// The one seam for tests. Everything below this line is the SFTP
    /// conversation, and the only reason it has never been checked is that
    /// `connect` insists on spawning `ssh` to reach a real server — so the
    /// conversation could only be exercised against one. Handed two pipes
    /// instead, it can be held against a server that misbehaves **on
    /// purpose**: one that answers a read with fewer bytes than it promised,
    /// or replies to a request nobody made. Neither is something a real
    /// server can be asked to do.
    ///
    /// The `Process` here is never started, so **do not call `close()` on a
    /// client made this way** — terminating a process that never ran raises.
    /// Close the handles instead.
    static func speaking(to toServer: FileHandle, from fromServer: FileHandle) async -> SFTPClient {
        let client = SFTPClient(
            process: Process(), toServer: toServer, fromServer: fromServer)
        await client.startReading()
        return client
    }

    func close() {
        guard ended == nil else { return }
        finish(SFTPError("the file session was closed"))
        try? toServer.close()
        process.terminate()
    }

    var isRunning: Bool { ended == nil && process.isRunning }

    // MARK: the conversation

    private func handshake() async throws {
        var body = SFTP.Writer()
        body.uint32(3)
        let reply = try await send(.initialise, body.bytes, id: 0)
        guard reply.type == .version else { throw SFTPError("the far end did not say its version") }
        var reader = SFTP.Reader(reply.body)
        let version = try reader.uint32()
        guard version >= 3 else {
            throw SFTPError("the far end speaks SFTP version \(version); this speaks 3")
        }
    }

    /// Sends one packet and waits for the reply that carries its id.
    private func send(_ type: SFTP.PacketType, _ body: [UInt8], id: UInt32) async throws -> Reply {
        if let ended { throw ended }
        return try await withCheckedThrowingContinuation { continuation in
            waiting[id] = continuation
            do {
                try writeToServer(SFTP.Writer.packet(type, body))
            } catch {
                waiting[id] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Writes the whole packet to the descriptor rather than through the
    /// `FileHandle`.
    ///
    /// `FileHandle.write(contentsOf:)` raises an **ObjC** exception when the
    /// handle is closed or its far end has gone, and no Swift `catch` can see
    /// one — so the `catch` above, which is the whole of what a dead far end
    /// was supposed to come out as, could never run, and the process died
    /// instead. `Darwin.write` only returns, which is how `startReading`
    /// already reads: a closed descriptor comes back `EBADF` and a far end
    /// that has gone `EPIPE`, both of them errors this can carry. A short
    /// write is ordinary on a pipe, so the loop is the point rather than a
    /// precaution, and nought counts as a failure so that it cannot spin.
    private func writeToServer(_ packet: Data) throws {
        try packet.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let wrote = Darwin.write(
                    outDescriptor, bytes.baseAddress! + sent, bytes.count - sent)
                if wrote > 0 {
                    sent += wrote
                } else if wrote < 0 && errno == EINTR {
                    continue
                } else {
                    throw SFTPError(
                        "the file session stopped listening: "
                            + String(cString: strerror(errno)))
                }
            }
        }
    }

    /// A request with an id of its own, which is everything but the handshake.
    private func request(_ type: SFTP.PacketType, _ fill: (inout SFTP.Writer) -> Void) async throws
        -> Reply
    {
        let id = nextRequest
        nextRequest &+= 1
        if nextRequest == 0 { nextRequest = 1 }
        var body = SFTP.Writer()
        body.uint32(id)
        fill(&body)
        return try await send(type, body.bytes, id: id)
    }

    /// A reply that should be nothing but "that worked".
    private func expectOK(_ reply: Reply) throws {
        guard reply.type == .status else {
            throw SFTPError("the far end replied with something unexpected")
        }
        try check(reply.body)
    }

    private func check(_ body: Data) throws {
        var reader = SFTP.Reader(body)
        let code = try reader.uint32()
        guard code != SFTP.Status.ok.rawValue else { return }
        let said = (try? reader.string()) ?? ""
        let status = SFTP.Status(rawValue: code)
        throw SFTPError(said.isEmpty ? describe(status, code) : said, status: status)
    }

    private func describe(_ status: SFTP.Status?, _ code: UInt32) -> String {
        switch status {
        case .noSuchFile: "there is no such file"
        case .permissionDenied: "permission denied"
        case .unsupported: "the far end does not support that"
        case .connectionLost, .noConnection: "the connection was lost"
        default: "the far end refused that (status \(code))"
        }
    }

    // MARK: what the browser asks for

    func realpath(_ path: String) async throws -> String {
        let reply = try await request(.realpath) { $0.string(path) }
        guard reply.type == .name else {
            try expectOK(reply)
            throw SFTPError("the far end did not say where that is")
        }
        var reader = SFTP.Reader(reply.body)
        _ = try reader.uint32()  // how many names; realpath answers with one
        return try reader.string()
    }

    func stat(_ path: String) async throws -> SFTP.Attributes {
        let reply = try await request(.stat) { $0.string(path) }
        guard reply.type == .attrs else {
            try expectOK(reply)
            throw SFTPError("the far end said nothing about that file")
        }
        var reader = SFTP.Reader(reply.body)
        return try reader.attributes()
    }

    /// Everything in a directory, `.` and `..` left out: they are not entries
    /// anyone wants to see in a browser, and the parent has its own button.
    func list(_ path: String) async throws -> [SFTP.Entry] {
        let handle = try await openDirectory(path)
        defer { Task { try? await self.closeHandle(handle) } }

        var out: [SFTP.Entry] = []
        while true {
            let reply = try await request(.readdir) { $0.data(handle) }
            if reply.type == .status {
                // EOF is how a directory ends, not a failure.
                var reader = SFTP.Reader(reply.body)
                if try reader.uint32() == SFTP.Status.eof.rawValue { break }
                try check(reply.body)
                break
            }
            guard reply.type == .name else { break }
            var reader = SFTP.Reader(reply.body)
            let count = try reader.uint32()
            for _ in 0..<count {
                let name = try reader.string()
                _ = try reader.string()  // the long name, which this builds itself
                let attributes = try reader.attributes()
                guard name != ".", name != ".." else { continue }
                out.append(SFTP.Entry(name: name, attributes: attributes))
            }
        }
        return out
    }

    func mkdir(_ path: String) async throws {
        let reply = try await request(.mkdir) { body in
            body.string(path)
            body.uint32(0)  // no attributes; the far end's umask decides
        }
        try expectOK(reply)
    }

    /// Removes a file, or a directory once it is empty. Which one it is is
    /// asked first, because the protocol has a different request for each and
    /// answering "is a directory" to a delete would be no help.
    func remove(_ path: String) async throws {
        let attributes = try await stat(path)
        let reply = try await request(attributes.isDirectory ? .rmdir : .remove) { $0.string(path) }
        try expectOK(reply)
    }

    func rename(_ from: String, to: String) async throws {
        let reply = try await request(.rename) { body in
            body.string(from)
            body.string(to)
        }
        try expectOK(reply)
    }

    // MARK: handles

    private func openDirectory(_ path: String) async throws -> Data {
        let reply = try await request(.opendir) { $0.string(path) }
        return try handle(from: reply)
    }

    func openFile(_ path: String, flags: SFTP.OpenFlags) async throws -> Data {
        let reply = try await request(.open) { body in
            body.string(path)
            body.uint32(flags.rawValue)
            body.uint32(0)  // no attributes
        }
        return try handle(from: reply)
    }

    private func handle(from reply: Reply) throws -> Data {
        guard reply.type == .handle else {
            try expectOK(reply)
            throw SFTPError("the far end gave nothing to read from")
        }
        var reader = SFTP.Reader(reply.body)
        return try reader.data()
    }

    func closeHandle(_ handle: Data) async throws {
        try expectOK(try await request(.close) { $0.data(handle) })
    }

    /// Reads one run of bytes. An empty result means the end of the file.
    func read(_ handle: Data, at offset: UInt64, count: UInt32) async throws -> Data {
        let reply = try await request(.read) { body in
            body.data(handle)
            body.uint64(offset)
            body.uint32(count)
        }
        if reply.type == .data {
            var reader = SFTP.Reader(reply.body)
            return try reader.data()
        }
        guard reply.type == .status else {
            // Anything else here would be read as an end of file, and a
            // download that stops early without saying so writes a file with
            // a piece missing.
            throw SFTPError("the far end answered a read with \(reply.type)")
        }
        var reader = SFTP.Reader(reply.body)
        if try reader.uint32() == SFTP.Status.eof.rawValue { return Data() }
        try check(reply.body)
        return Data()
    }

    func write(_ handle: Data, at offset: UInt64, _ bytes: Data) async throws {
        let reply = try await request(.write) { body in
            body.data(handle)
            body.uint64(offset)
            body.data(bytes)
        }
        try expectOK(reply)
    }

    // MARK: the pipe

    /// A thread rather than a readability handler: the reads are blocking and
    /// the packets have to be reassembled in order, which is exactly what a
    /// loop of its own is for.
    private func startReading() {
        let descriptor = fromServer.fileDescriptor
        let thread = Thread { [weak self] in
            var pending = Data()
            var chunk = [UInt8](repeating: 0, count: 64 << 10)
            while true {
                let got = chunk.withUnsafeMutableBytes { buffer in
                    Darwin.read(descriptor, buffer.baseAddress, buffer.count)
                }
                guard got > 0 else { break }
                pending.append(contentsOf: chunk[0..<got])
                while pending.count >= 4 {
                    let length = pending.prefix(4).reduce(0) { Int($0) << 8 | Int($1) }
                    guard length > 0, pending.count >= 4 + length else { break }
                    let packet = pending.subdata(in: 4..<(4 + length))
                    pending.removeSubrange(0..<(4 + length))
                    guard let self else { return }
                    Task { await self.deliver(packet) }
                }
            }
            guard let self else { return }
            Task { await self.finish(SFTPError("the file session ended")) }
        }
        thread.stackSize = 512 << 10
        thread.start()
    }

    private func deliver(_ packet: Data) {
        guard let first = packet.first, let type = SFTP.PacketType(rawValue: first) else { return }
        let body = packet.dropFirst()
        // The handshake answers without an id; everything else carries one.
        if type == .version {
            waiting.removeValue(forKey: 0)?.resume(returning: Reply(type: type, body: Data(body)))
            return
        }
        var reader = SFTP.Reader(Data(body))
        guard let id = try? reader.uint32() else { return }
        guard let waiter = waiting.removeValue(forKey: id) else {
            strayReplies += 1
            return
        }
        waiter.resume(returning: Reply(type: type, body: Data(body.dropFirst(4))))
    }

    /// Everything still waiting is answered, because a request whose session
    /// has gone would otherwise wait for a reply that cannot arrive.
    private func finish(_ error: SFTPError) {
        if ended == nil { ended = error }
        let outstanding = waiting
        waiting = [:]
        for (_, continuation) in outstanding { continuation.resume(throwing: error) }
    }
}
