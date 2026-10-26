import Foundation
@testable import Shellhand

/// An SFTP server that exists only in this process, on a pair of pipes.
///
/// This is what replaced the loopback server the spikes used to run. That one
/// was Go, with a module of its own, and it made a Go toolchain a prerequisite
/// for `xcodebuild test` in a project that is otherwise Swift all the way
/// down. More to the point, a real server is **well behaved**, and the code
/// here that has never been exercised is the code that handles a server which
/// is not: one that answers a read with fewer bytes than its own `stat`
/// promised, or sends a reply to a request nobody made.
///
/// What it gives up is real: it answers from this file's idea of SFTP, so a
/// misunderstanding shared by both ends would go unnoticed. `SFTPWireTests`
/// pins the encoding separately, which is what makes that risk bearable.
nonisolated final class ScriptedSFTP: @unchecked Sendable {
    /// The bytes a read will actually return.
    private let contents: Data
    /// What `stat` claims the file is. Set it larger than `contents` to make
    /// the server promise more than it delivers.
    private let claimedSize: Int64
    /// A reply to send unasked, once, after the first request.
    private let intruder: Data?

    /// Answer every write with a failure, to see what the client does when
    /// the far end will not take the bytes.
    private let refuseWrites: Bool
    /// Names to hand back from `readdir`, one batch per call, then EOF. A
    /// directory arriving in pieces is the normal case, not an edge one.
    private let directory: [[String]]
    /// Answer anything that expects a plain "that worked" with this instead.
    private let refusal: (code: SFTP.Status, said: String)?

    private let clientToPeer = Pipe()
    private let peerToClient = Pipe()
    private var sentIntruder = false

    /// Touched from the peer's own thread and read from the test's, so both
    /// go through the lock.
    private let lock = NSLock()
    private var storedWrites: [UInt64: Data] = [:]
    private var storedFlags: UInt32?
    private var servedBatches = 0

    init(
        contents: Data = Data(), claimedSize: Int64? = nil,
        intruder: Data? = nil, refuseWrites: Bool = false,
        directory: [[String]] = [], refusal: (code: SFTP.Status, said: String)? = nil
    ) {
        self.contents = contents
        self.claimedSize = claimedSize ?? Int64(contents.count)
        self.intruder = intruder
        self.refuseWrites = refuseWrites
        self.directory = directory
        self.refusal = refusal
    }

    /// Everything the client wrote — the file as it would have landed.
    ///
    /// `upload` writes sequentially from zero and never overlaps, so joining
    /// the chunks in offset order is the whole of it.
    var received: Data {
        lock.withLock {
            storedWrites.keys.sorted().reduce(into: Data()) { $0.append(storedWrites[$1]!) }
        }
    }

    /// The flags the client asked to open with, once it has.
    var openFlags: UInt32? { lock.withLock { storedFlags } }

    /// A client wired to this server, already reading.
    /// `answeringWithin` is passed straight through, for a test that wants a
    /// conversation held to a deadline far shorter than the shipped one.
    func client(answeringWithin deadline: Duration = SFTPClient.Deadline.reply) async -> SFTPClient
    {
        start()
        return await SFTPClient.speaking(
            to: clientToPeer.fileHandleForWriting, from: peerToClient.fileHandleForReading,
            answeringWithin: deadline)
    }

    /// Lets go of both ends. Never `close()` the client — its `Process` was
    /// never started.
    func stop() {
        try? clientToPeer.fileHandleForWriting.close()
        try? peerToClient.fileHandleForWriting.close()
    }

    // MARK: answering

    private func start() {
        let incoming = clientToPeer.fileHandleForReading.fileDescriptor
        // A descriptor, like `incoming`, and for a reason that cost a whole
        // run: `FileHandle.write(contentsOf:)` raises an **ObjC** exception
        // once `stop()` has closed this end underneath the thread, `try?`
        // cannot catch one, and the test host dies with every test already
        // passed. The same mistake was in `SFTPClient.send`.
        let outgoing = peerToClient.fileHandleForWriting.fileDescriptor
        // Writing to a pipe nothing reads raises SIGPIPE, which ends the
        // process outright; off for this descriptor only.
        _ = fcntl(outgoing, F_SETNOSIGPIPE, 1)
        let thread = Thread { [weak self] in
            var pending = Data()
            var chunk = [UInt8](repeating: 0, count: 64 << 10)
            while true {
                let got = chunk.withUnsafeMutableBytes { Darwin.read(incoming, $0.baseAddress, $0.count) }
                guard got > 0, let self else { break }
                pending.append(contentsOf: chunk[0..<got])
                // Same reassembly the client does: a length, then that many
                // bytes, and a packet can arrive in pieces.
                while pending.count >= 4 {
                    let length = pending.prefix(4).reduce(0) { Int($0) << 8 | Int($1) }
                    guard length > 0, pending.count >= 4 + length else { break }
                    let packet = pending.subdata(in: 4..<(4 + length))
                    pending.removeSubrange(0..<(4 + length))
                    for reply in self.answer(packet) {
                        Self.hand(reply, to: outgoing)
                    }
                }
            }
        }
        thread.stackSize = 512 << 10
        thread.start()
    }

    /// Writes what it can and gives up quietly. By the time this fails the
    /// test has called `stop()` and there is nobody left to tell — which is
    /// what the old `try?` was reaching for and could not do.
    private static func hand(_ reply: Data, to descriptor: Int32) {
        reply.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let wrote = Darwin.write(
                    descriptor, bytes.baseAddress! + sent, bytes.count - sent)
                if wrote > 0 {
                    sent += wrote
                } else if wrote < 0 && errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    private func answer(_ packet: Data) -> [Data] {
        guard let first = packet.first,
              let type = SFTP.PacketType(rawValue: first) else { return [] }
        var reader = SFTP.Reader(Data(packet.dropFirst()))

        if type == .initialise {
            var body = SFTP.Writer()
            body.uint32(3)
            return [SFTP.Writer.packet(.version, body.bytes)]
        }
        guard let id = try? reader.uint32() else { return [] }

        var out: [Data] = []
        if let intruder, !sentIntruder {
            sentIntruder = true
            out.append(intruder)
        }

        switch type {
        case .stat, .lstat, .fstat:
            var body = SFTP.Writer()
            body.uint32(id)
            body.uint32(0x0000_0001)          // only the size is present
            body.uint64(UInt64(claimedSize))
            out.append(SFTP.Writer.packet(.attrs, body.bytes))
        case .open:
            _ = try? reader.string()           // the path
            if let flags = try? reader.uint32() {
                lock.withLock { storedFlags = flags }
            }
            var body = SFTP.Writer()
            body.uint32(id)
            body.data(Data([0xAB]))
            out.append(SFTP.Writer.packet(.handle, body.bytes))
        case .write:
            _ = try? reader.data()             // the handle
            let offset = (try? reader.uint64()) ?? 0
            let bytes = (try? reader.data()) ?? Data()
            if refuseWrites {
                out.append(Self.status(id: id, .failure))
            } else {
                lock.withLock { storedWrites[offset] = bytes }
                out.append(Self.status(id: id, .ok))
            }
        case .read:
            _ = try? reader.data()             // the handle
            let offset = (try? reader.uint64()) ?? 0
            let count = (try? reader.uint32()) ?? 0
            out.append(readReply(id: id, offset: offset, count: count))
        case .opendir:
            var body = SFTP.Writer()
            body.uint32(id)
            body.data(Data([0xCD]))
            out.append(SFTP.Writer.packet(.handle, body.bytes))
        case .readdir:
            let batch = lock.withLock { () -> [String]? in
                guard servedBatches < directory.count else { return nil }
                defer { servedBatches += 1 }
                return directory[servedBatches]
            }
            guard let batch else {
                out.append(Self.status(id: id, .eof))
                break
            }
            var body = SFTP.Writer()
            body.uint32(id)
            body.uint32(UInt32(batch.count))
            for name in batch {
                body.string(name)
                body.string("-rw-r--r--  1 someone  staff  0 Jan  1 00:00 \(name)")
                body.uint32(0)                 // no attributes present
            }
            out.append(SFTP.Writer.packet(.name, body.bytes))
        case .close:
            out.append(Self.status(id: id, .ok))
        default:
            if let refusal {
                out.append(Self.status(id: id, refusal.code, said: refusal.said))
            } else {
                out.append(Self.status(id: id, .ok))
            }
        }
        return out
    }

    private func readReply(id: UInt32, offset: UInt64, count: UInt32) -> Data {
        let start = Int(offset)
        guard start < contents.count else { return Self.status(id: id, .eof) }
        let end = min(start + Int(count), contents.count)
        var body = SFTP.Writer()
        body.uint32(id)
        body.data(contents.subdata(in: start..<end))
        return SFTP.Writer.packet(.data, body.bytes)
    }

    // MARK: packets a test can hand in

    static func status(id: UInt32, _ code: SFTP.Status, said: String = "") -> Data {
        var body = SFTP.Writer()
        body.uint32(id)
        body.uint32(code.rawValue)
        body.string(said)
        body.string("")
        return SFTP.Writer.packet(.status, body.bytes)
    }
}
