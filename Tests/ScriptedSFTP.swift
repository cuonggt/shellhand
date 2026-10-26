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

    private let clientToPeer = Pipe()
    private let peerToClient = Pipe()
    private var sentIntruder = false

    init(contents: Data = Data(), claimedSize: Int64? = nil, intruder: Data? = nil) {
        self.contents = contents
        self.claimedSize = claimedSize ?? Int64(contents.count)
        self.intruder = intruder
    }

    /// A client wired to this server, already reading.
    func client() async -> SFTPClient {
        start()
        return await SFTPClient.speaking(
            to: clientToPeer.fileHandleForWriting, from: peerToClient.fileHandleForReading)
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
        let outgoing = peerToClient.fileHandleForWriting
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
                        try? outgoing.write(contentsOf: reply)
                    }
                }
            }
        }
        thread.stackSize = 512 << 10
        thread.start()
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
            var body = SFTP.Writer()
            body.uint32(id)
            body.data(Data([0xAB]))
            out.append(SFTP.Writer.packet(.handle, body.bytes))
        case .read:
            _ = try? reader.data()             // the handle
            let offset = (try? reader.uint64()) ?? 0
            let count = (try? reader.uint32()) ?? 0
            out.append(readReply(id: id, offset: offset, count: count))
        case .close:
            out.append(Self.status(id: id, .ok))
        default:
            out.append(Self.status(id: id, .ok))
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

    static func status(id: UInt32, _ code: SFTP.Status) -> Data {
        var body = SFTP.Writer()
        body.uint32(id)
        body.uint32(code.rawValue)
        body.string("")
        body.string("")
        return SFTP.Writer.packet(.status, body.bytes)
    }
}
