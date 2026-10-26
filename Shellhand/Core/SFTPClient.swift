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
    private let handshakeDeadline: Duration
    private let replyDeadline: Duration
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

    /// How long one request may go unanswered before it is called a failure.
    ///
    /// Nothing in SFTP carries a timeout of its own, so without these a reply
    /// that never comes is waited on for ever: the continuation in `send` is
    /// resumed by the reply or by `finish`, and `finish` fires only when the
    /// pipes break or the child dies. A far end that is wedged while its pipes
    /// are perfectly healthy is neither — and that has been seen, a run of the
    /// suite sitting sixteen minutes on one conversation with both reader
    /// threads idle in `read` and nothing left that was ever going to resume
    /// it. In the app the same thing is a file pane stuck on "Connecting…"
    /// that cannot even be retried, because the guard on `FilePlace.opening`
    /// is cleared in a `defer` a parked request never reaches.
    ///
    /// Neither of these explains that, and neither is a connect timeout. They
    /// are what makes the next sighting cheap: a named failure saying which
    /// request went unanswered, where there was an unbounded wait.
    enum Deadline {
        /// A request to a server that is already answering. One of those is a
        /// single packet against a 32KiB chunk at most, so this is tens of
        /// times a bad link's round trip rather than a budget to work within.
        static let reply: Duration = .seconds(30)

        /// The handshake's own, which is waiting for very much more: ssh
        /// resolving the name, reaching the host, working along a jump chain,
        /// authenticating, and starting the subsystem. Nothing here sets
        /// `ConnectTimeout`, so ssh's own patience is the system's TCP timeout
        /// and can run past a minute. This sits above that **deliberately**,
        /// so a host that is merely slow or unreachable still fails with ssh's
        /// own sentence, which says far more than this one can.
        static let handshake: Duration = .seconds(120)
    }

    private init(
        process: Process, toServer: FileHandle, fromServer: FileHandle,
        handshakeDeadline: Duration, replyDeadline: Duration
    ) {
        self.process = process
        self.toServer = toServer
        self.outDescriptor = toServer.fileDescriptor
        self.fromServer = fromServer
        self.handshakeDeadline = handshakeDeadline
        self.replyDeadline = replyDeadline
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
            fromServer: output.fileHandleForReading,
            handshakeDeadline: Deadline.handshake, replyDeadline: Deadline.reply)
        await client.startReading()
        do {
            try await client.handshake()
        } catch {
            // The client is let go of **first**, and the order is
            // load-bearing: reading ssh's stderr waits for an end of file,
            // which comes only once ssh itself has gone. Where the handshake
            // failed because the child had already died, that is true the
            // moment it is asked — but it is not true of a far end answering
            // with a version this cannot speak, nor of one that stopped
            // answering at all, and in either of those this waited on a live
            // child for ever. Terminating it first bounds the read and loses
            // nothing, since what ssh said is already in the pipe. The proven
            // path is untouched: `close()` does nothing once `ended` is set,
            // and that is exactly the case where the child is gone and its own
            // sentence is the one worth reporting.
            await client.close()
            // ssh says why on its own stream, and that sentence is the useful
            // one: "Permission denied", "Host key verification failed".
            let said = (try? errors.fileHandleForReading.readToEnd())
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
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
    ///
    /// `answeringWithin` is here for the same reason the seam is: a test that
    /// means to watch a deadline expire cannot sit through the shipped one. It
    /// sets both, since on a pair of pipes the handshake is no slower to answer
    /// than anything else.
    static func speaking(
        to toServer: FileHandle, from fromServer: FileHandle,
        answeringWithin deadline: Duration = Deadline.reply
    ) async -> SFTPClient {
        let client = SFTPClient(
            process: Process(), toServer: toServer, fromServer: fromServer,
            handshakeDeadline: deadline, replyDeadline: deadline)
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

    /// Sends one packet and waits for the reply that carries its id — though
    /// not for ever; see `Deadline`.
    private func send(_ type: SFTP.PacketType, _ body: [UInt8], id: UInt32) async throws -> Reply {
        if let ended { throw ended }
        let deadline = id == 0 ? handshakeDeadline : replyDeadline
        // A cancelled sleep throws, so whenever the reply wins this race the
        // task ends at the `try` and never reaches `giveUp`. The `defer` is
        // what cancels it, which also means the strong `self` this task holds
        // is held only for as long as the request is outstanding.
        let watchdog = Task {
            try await Task.sleep(for: deadline)
            giveUp(on: id, type: type, after: deadline)
        }
        defer { watchdog.cancel() }
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

    /// Answers one request that has waited past its deadline.
    ///
    /// Taking the waiter out of `waiting` before resuming it is what keeps
    /// this and `deliver` from both answering the same request: each runs on
    /// the actor, and whichever arrives second finds nothing and returns — so
    /// a reply that comes in late is counted a stray rather than resuming a
    /// continuation twice, which would trap.
    ///
    /// Only this one request fails. The session is left alone, because a reply
    /// that never arrived has not lost the conversation its place — packets
    /// are length-prefixed, so the next one still frames correctly — and the
    /// caller can report and retry rather than having a session that is merely
    /// slow destroyed under it. `ended` is deliberately not set either:
    /// `close()` refuses to do anything once it is, which would leave the
    /// `ssh` child running with nothing left to end it.
    private func giveUp(on id: UInt32, type: SFTP.PacketType, after deadline: Duration) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        continuation.resume(
            throwing: SFTPError("the far end did not answer \(type) within \(deadline)"))
    }

    private func writeToServer(_ packet: Data) throws {
        try Self.writeAll(
            packet, to: outDescriptor, failing: "the file session stopped listening")
    }

    /// Writes the whole of `bytes` to a descriptor, or throws saying why.
    ///
    /// **Nothing here writes through a `FileHandle`, and this is the reason.**
    /// `FileHandle.write(contentsOf:)` raises an **ObjC** exception when the
    /// handle is closed, when its far end has gone, or when the write itself
    /// fails — and no Swift `catch` can see one, so the error a caller means
    /// to report never arrives and the process dies instead. It killed a whole
    /// test run that way before it was understood. `Darwin.write` only
    /// returns, which is how `startReading` already reads: `EBADF` for a
    /// closed descriptor, `EPIPE` for a far end that has gone, `ENOSPC` for a
    /// disk with no room, each of them an error this can carry.
    /// A short write is ordinary rather than exceptional, so the loop is the
    /// point and not a precaution, and nought counts as a failure so that it
    /// cannot spin. Both directions share it: the packets going out to `ssh`,
    /// and the bytes coming down into a local file.
    nonisolated static func writeAll(
        _ bytes: Data, to descriptor: Int32, failing what: String
    ) throws {
        try bytes.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let wrote = Darwin.write(
                    descriptor, buffer.baseAddress! + sent, buffer.count - sent)
                if wrote > 0 {
                    sent += wrote
                } else if wrote < 0 && errno == EINTR {
                    continue
                } else {
                    throw SFTPError("\(what): " + String(cString: strerror(errno)))
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
