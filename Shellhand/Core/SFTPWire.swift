import Foundation

/// The SFTP version 3 wire format.
///
/// Version 3 because that is what OpenSSH's server speaks and has since 2001;
/// later drafts exist and nothing ships them. Every packet is a length, a
/// type, and for everything but the two handshake packets a request id, so
/// replies can be matched to what asked for them.
nonisolated enum SFTP {
    enum PacketType: UInt8 {
        case initialise = 1, version = 2, open = 3, close = 4, read = 5, write = 6
        case lstat = 7, fstat = 8, setstat = 9, opendir = 11, readdir = 12
        case remove = 13, mkdir = 14, rmdir = 15, realpath = 16, stat = 17, rename = 18
        case status = 101, handle = 102, data = 103, name = 104, attrs = 105
    }

    /// The status codes worth telling apart. Everything else is a failure with
    /// whatever the server said about it.
    enum Status: UInt32 {
        case ok = 0, eof = 1, noSuchFile = 2, permissionDenied = 3, failure = 4
        case badMessage = 5, noConnection = 6, connectionLost = 7, unsupported = 8
    }

    struct OpenFlags: OptionSet {
        let rawValue: UInt32
        static let read = OpenFlags(rawValue: 0x0000_0001)
        static let write = OpenFlags(rawValue: 0x0000_0002)
        static let append = OpenFlags(rawValue: 0x0000_0004)
        static let create = OpenFlags(rawValue: 0x0000_0008)
        static let truncate = OpenFlags(rawValue: 0x0000_0010)
        static let exclusive = OpenFlags(rawValue: 0x0000_0020)
    }

    struct AttributeFlags {
        static let size: UInt32 = 0x0000_0001
        static let uidgid: UInt32 = 0x0000_0002
        static let permissions: UInt32 = 0x0000_0004
        static let times: UInt32 = 0x0000_0008
    }

    /// What the server knows about a file. Everything is optional on the wire,
    /// so everything is optional here.
    struct Attributes: Sendable, Equatable {
        var size: UInt64?
        var permissions: UInt32?
        var modified: UInt32?

        var isDirectory: Bool { (permissions ?? 0) & 0xF000 == 0x4000 }
        var isSymlink: Bool { (permissions ?? 0) & 0xF000 == 0xA000 }

        /// `drwxr-xr-x`, as a file listing writes it.
        var mode: String {
            guard let permissions else { return "" }
            let kind: Character =
                switch permissions & 0xF000 {
                case 0x4000: "d"
                case 0xA000: "l"
                case 0x8000: "-"
                default: "?"
                }
            var out = String(kind)
            let bits = ["r", "w", "x"]
            for shift in stride(from: 6, through: 0, by: -3) {
                for (i, letter) in bits.enumerated() {
                    let mask = UInt32(1 << (shift + (2 - i)))
                    out += (permissions & mask) != 0 ? letter : "-"
                }
            }
            return out
        }
    }

    /// One entry of a directory.
    struct Entry: Sendable {
        var name = ""
        var attributes = Attributes()
    }

    // MARK: writing

    /// Builds a packet body. Lengths and strings go out big-endian, which is
    /// how every SSH protocol writes a number.
    struct Writer {
        private(set) var bytes: [UInt8] = []

        mutating func byte(_ value: UInt8) { bytes.append(value) }

        mutating func uint32(_ value: UInt32) {
            bytes.append(contentsOf: [
                UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value),
            ])
        }

        mutating func uint64(_ value: UInt64) {
            uint32(UInt32(truncatingIfNeeded: value >> 32))
            uint32(UInt32(truncatingIfNeeded: value))
        }

        /// A length and then the bytes — never a terminator, because a path
        /// may hold anything a file system allows.
        mutating func string(_ value: String) { data(Data(value.utf8)) }

        mutating func data(_ value: Data) {
            uint32(UInt32(value.count))
            bytes.append(contentsOf: value)
        }

        /// A packet, ready for the pipe: its length, its type, then the body.
        static func packet(_ type: PacketType, _ body: [UInt8]) -> Data {
            var out = Writer()
            out.uint32(UInt32(body.count + 1))
            out.byte(type.rawValue)
            return Data(out.bytes + body)
        }
    }

    // MARK: reading

    /// Reads a packet body. Every read is bounds-checked: the far end is a
    /// program on another machine, and a packet that claims more than it
    /// carries must be an error rather than a crash.
    struct Reader {
        private let bytes: [UInt8]
        private var at = 0

        init(_ data: Data) { bytes = Array(data) }

        var isAtEnd: Bool { at >= bytes.count }

        mutating func byte() throws -> UInt8 {
            guard at < bytes.count else { throw SFTPError("the reply ended early") }
            defer { at += 1 }
            return bytes[at]
        }

        mutating func uint32() throws -> UInt32 {
            guard at + 4 <= bytes.count else { throw SFTPError("the reply ended early") }
            defer { at += 4 }
            return (UInt32(bytes[at]) << 24) | (UInt32(bytes[at + 1]) << 16)
                | (UInt32(bytes[at + 2]) << 8) | UInt32(bytes[at + 3])
        }

        mutating func uint64() throws -> UInt64 {
            let high = try uint32(), low = try uint32()
            return (UInt64(high) << 32) | UInt64(low)
        }

        mutating func data() throws -> Data {
            let count = Int(try uint32())
            guard at + count <= bytes.count else { throw SFTPError("the reply ended early") }
            defer { at += count }
            return Data(bytes[at..<(at + count)])
        }

        mutating func string() throws -> String {
            String(decoding: try data(), as: UTF8.self)
        }

        mutating func attributes() throws -> Attributes {
            var out = Attributes()
            let flags = try uint32()
            if flags & AttributeFlags.size != 0 { out.size = try uint64() }
            if flags & AttributeFlags.uidgid != 0 {
                _ = try uint32()
                _ = try uint32()
            }
            if flags & AttributeFlags.permissions != 0 { out.permissions = try uint32() }
            if flags & AttributeFlags.times != 0 {
                _ = try uint32()
                out.modified = try uint32()
            }
            // Extended pairs, which nothing here reads but all of which have
            // to be stepped over for the next field to be in the right place.
            if flags & 0x8000_0000 != 0 {
                let count = try uint32()
                for _ in 0..<count {
                    _ = try data()
                    _ = try data()
                }
            }
            return out
        }
    }
}

nonisolated struct SFTPError: LocalizedError, Sendable, Equatable {
    let message: String
    var status: SFTP.Status?

    init(_ message: String, status: SFTP.Status? = nil) {
        self.message = message
        self.status = status
    }

    var errorDescription: String? { message }
    var isNoSuchFile: Bool { status == .noSuchFile }
}
