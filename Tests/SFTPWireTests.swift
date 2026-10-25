import Foundation
import Testing
@testable import Shellhand

@Suite("SFTP wire")
nonisolated struct SFTPWireTests {
    @Test("numbers go out big-endian, which is how every SSH protocol writes one")
    func numbers() {
        var writer = SFTP.Writer()
        writer.uint32(0x0102_0304)
        #expect(writer.bytes == [1, 2, 3, 4])

        writer = SFTP.Writer()
        writer.uint64(0x0102_0304_0506_0708)
        #expect(writer.bytes == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test("a string is a length and then the bytes, never a terminator")
    func strings() throws {
        var writer = SFTP.Writer()
        writer.string("/tmp")
        #expect(writer.bytes == [0, 0, 0, 4, 0x2F, 0x74, 0x6D, 0x70])

        var reader = SFTP.Reader(Data(writer.bytes))
        #expect(try reader.string() == "/tmp")
        #expect(reader.isAtEnd)
    }

    @Test("a path with anything in it survives the trip")
    func awkwardPath() throws {
        let path = "/tmp/a file — with ünicode/and:colons"
        var writer = SFTP.Writer()
        writer.string(path)
        var reader = SFTP.Reader(Data(writer.bytes))
        #expect(try reader.string() == path)
    }

    @Test("a packet is its length, its type, then the body")
    func packet() {
        var body = SFTP.Writer()
        body.uint32(3)
        let packet = SFTP.Writer.packet(.initialise, body.bytes)
        #expect(Array(packet) == [0, 0, 0, 5, 1, 0, 0, 0, 3])
    }

    @Test("a reply that claims more than it carries is an error, not a crash")
    func shortReply() {
        var reader = SFTP.Reader(Data([0, 0, 0, 10, 1, 2]))
        #expect(throws: SFTPError.self) { try reader.data() }

        var empty = SFTP.Reader(Data())
        #expect(throws: SFTPError.self) { try empty.uint32() }
    }

    @Test("attributes are read in the order the flags say, so the next field lands right")
    func attributes() throws {
        var writer = SFTP.Writer()
        writer.uint32(SFTP.AttributeFlags.size | SFTP.AttributeFlags.permissions
            | SFTP.AttributeFlags.times)
        writer.uint64(4096)
        writer.uint32(0o040755)
        writer.uint32(111)  // access time, stepped over
        writer.uint32(222)  // modified
        // What follows has to still be readable, which is the point.
        writer.string("next")

        var reader = SFTP.Reader(Data(writer.bytes))
        let attributes = try reader.attributes()
        #expect(attributes.size == 4096)
        #expect(attributes.modified == 222)
        #expect(attributes.isDirectory)
        #expect(try reader.string() == "next")
    }

    @Test("extended pairs are stepped over, however many there are")
    func extended() throws {
        var writer = SFTP.Writer()
        writer.uint32(SFTP.AttributeFlags.size | 0x8000_0000)
        writer.uint64(7)
        writer.uint32(2)
        writer.string("a")
        writer.string("1")
        writer.string("b")
        writer.string("2")
        writer.string("after")

        var reader = SFTP.Reader(Data(writer.bytes))
        #expect(try reader.attributes().size == 7)
        #expect(try reader.string() == "after")
    }

    @Test("a mode reads the way a listing writes it")
    func mode() {
        #expect(SFTP.Attributes(permissions: 0o040755).mode == "drwxr-xr-x")
        #expect(SFTP.Attributes(permissions: 0o100644).mode == "-rw-r--r--")
        #expect(SFTP.Attributes(permissions: 0o120777).mode == "lrwxrwxrwx")
        #expect(SFTP.Attributes(permissions: 0o100600).mode == "-rw-------")
        #expect(SFTP.Attributes().mode == "")
    }

    @Test("a directory, a link and a file are told apart")
    func kinds() {
        #expect(SFTP.Attributes(permissions: 0o040755).isDirectory)
        #expect(!SFTP.Attributes(permissions: 0o100644).isDirectory)
        #expect(SFTP.Attributes(permissions: 0o120777).isSymlink)
    }

    @Test("the flags a read and a write ask for are the ones the protocol names")
    func openFlags() {
        #expect(SFTP.OpenFlags.read.rawValue == 0x1)
        #expect([SFTP.OpenFlags.write, .create, .truncate].reduce(into: SFTP.OpenFlags()) {
            $0.insert($1)
        }.rawValue == 0x1A)
    }
}
