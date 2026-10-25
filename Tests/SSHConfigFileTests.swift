import Foundation
import Testing
@testable import Shellhand

@Suite("ssh config")
nonisolated struct SSHConfigFileTests {
    private func write(_ text: String, named name: String = "config") throws -> String {
        let folder = NSTemporaryDirectory() + "shellhand-ssh-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let path = (folder as NSString).appendingPathComponent(name)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test("a block becomes a host, by the name the file gives it")
    func plain() throws {
        let path = try write("""
            Host web
                HostName 10.0.0.1
                User deploy
                Port 2222
                IdentityFile ~/.ssh/id_deploy
            """)
        let host = try #require(try SSHConfigFile.read(path: path).hosts.first)
        #expect(host.name == "web")
        #expect(host.addr == "10.0.0.1")
        #expect(host.user == "deploy")
        #expect(host.port == 2222)
        #expect(host.identity.hasSuffix("/.ssh/id_deploy"))
        #expect(!host.identity.hasPrefix("~"))
    }

    @Test("a name with no HostName is the address, which is how many are written")
    func nameIsAddress() throws {
        let path = try write("Host myserver.example.com\n    User deploy\n")
        #expect(try SSHConfigFile.read(path: path).hosts.first?.addr == "myserver.example.com")
    }

    @Test("port 22 is left unset, because that is what ssh does anyway")
    func defaultPort() throws {
        let path = try write("Host web\n    HostName 10.0.0.1\n    Port 22\n")
        #expect(try SSHConfigFile.read(path: path).hosts.first?.port == 0)
    }

    @Test("a pattern is a rule about many machines, not a machine")
    func patternsAreNotHosts() throws {
        let path = try write("""
            Host *
                ServerAliveInterval 30
            Host 10.0.1.?
                User deploy
            Host web
                HostName 10.0.0.1
            """)
        #expect(try SSHConfigFile.read(path: path).hosts.map(\.name) == ["web"])
    }

    @Test("settings from a pattern still reach the hosts it covers")
    func patternSettingsApply() throws {
        let path = try write("""
            Host *
                User deploy
            Host web
                HostName 10.0.0.1
            """)
        #expect(try SSHConfigFile.read(path: path).hosts.first?.user == "deploy")
    }

    @Test("the first value wins, which is ssh's own rule")
    func firstWins() throws {
        let path = try write("""
            Host web
                User fromOwnBlock
            Host *
                User fromPattern
            """)
        #expect(try SSHConfigFile.read(path: path).hosts.first?.user == "fromOwnBlock")
    }

    @Test("settings written before any Host line reach everything")
    func preamble() throws {
        let path = try write("""
            User everywhere
            Host web
                HostName 10.0.0.1
            """)
        #expect(try SSHConfigFile.read(path: path).hosts.first?.user == "everywhere")
    }

    @Test("a jump host is taken, and none means none")
    func jump() throws {
        let path = try write("""
            Host web
                HostName 10.0.0.1
                ProxyJump bastion
            Host db
                HostName 10.0.0.2
                ProxyJump none
            """)
        let hosts = try SSHConfigFile.read(path: path).hosts
        #expect(hosts.first { $0.name == "web" }?.jump == "bastion")
        #expect(hosts.first { $0.name == "db" }?.jump == "")
    }

    @Test("%h in a HostName is the name the block was written under")
    func percentH() throws {
        let path = try write("Host web\n    HostName %h.internal\n")
        #expect(try SSHConfigFile.read(path: path).hosts.first?.addr == "web.internal")
    }

    @Test("a name declared twice is one host, with both blocks' settings")
    func declaredTwice() throws {
        let path = try write("""
            Host web
                HostName 10.0.0.1
            Host web
                User deploy
            """)
        let hosts = try SSHConfigFile.read(path: path).hosts
        #expect(hosts.count == 1)
        #expect(hosts.first?.user == "deploy")
        #expect(hosts.first?.addr == "10.0.0.1")
    }

    @Test("several names on one Host line are several hosts")
    func severalNames() throws {
        let path = try write("Host web db\n    User deploy\n")
        #expect(try SSHConfigFile.read(path: path).hosts.map(\.name) == ["db", "web"])
    }

    @Test("an Include is read where it is written")
    func include() throws {
        let path = try write("Host web\n    HostName 10.0.0.1\n")
        let folder = (path as NSString).deletingLastPathComponent
        let extra = (folder as NSString).appendingPathComponent("extra")
        try "Host db\n    HostName 10.0.0.2\n".write(toFile: extra, atomically: true, encoding: .utf8)
        let main = (folder as NSString).appendingPathComponent("main")
        try "Include extra\nHost web\n    HostName 10.0.0.1\n"
            .write(toFile: main, atomically: true, encoding: .utf8)

        let hosts = try SSHConfigFile.read(path: main).hosts
        #expect(hosts.map(\.name) == ["db", "web"])
    }

    @Test("a Match nobody can answer from here is carried but not applied")
    func unsupportedMatch() throws {
        let path = try write("""
            Match exec "true"
                User fromExec
            Host web
                HostName 10.0.0.1
            """)
        #expect(try SSHConfigFile.read(path: path).hosts.first?.user == "")
    }

    @Test("Match all reaches everything, and Match host the names it covers")
    func matchBlocks() throws {
        let path = try write("""
            Host web
                HostName 10.0.0.1
            Host db
                HostName 10.0.0.2
            Match host web
                User onlyWeb
            Match all
                Port 2222
            """)
        let hosts = try SSHConfigFile.read(path: path).hosts
        #expect(hosts.first { $0.name == "web" }?.user == "onlyWeb")
        #expect(hosts.first { $0.name == "db" }?.user == "")
        #expect(hosts.allSatisfy { $0.port == 2222 })
    }

    @Test("a missing file is no hosts rather than a failure")
    func missing() throws {
        #expect(try SSHConfigFile.read(path: "/nowhere/ssh/config").hosts.isEmpty)
    }

    @Test("keyword and value may be separated by an = or by spaces")
    func separators() throws {
        let path = try write("Host web\n    HostName=10.0.0.1\n    User = deploy\n")
        let host = try #require(try SSHConfigFile.read(path: path).hosts.first)
        #expect(host.addr == "10.0.0.1")
        #expect(host.user == "deploy")
    }

    @Test("patterns match as ssh matches them, negation included")
    func globbing() {
        #expect(SSHConfigFile.glob("*", "anything"))
        #expect(SSHConfigFile.glob("10.0.1.?", "10.0.1.5"))
        #expect(!SSHConfigFile.glob("10.0.1.?", "10.0.1.55"))
        #expect(SSHConfigFile.glob("*.example.com", "web.example.com"))
        #expect(!SSHConfigFile.glob("*.example.com", "web.example.org"))
        #expect(SSHConfigFile.glob("WEB", "web"))
        #expect(SSHConfigFile.matches("web", ["*.corp", "web"]))
        #expect(!SSHConfigFile.matches("web", ["*", "!web"]))
    }

    @Test("what the file names can be folded into the list")
    func mergesIn() throws {
        let path = try write("""
            Host web
                HostName 10.0.0.1
                User deploy
            """)
        let document = try SSHConfigFile.read(path: path)
        let plan = try Portable.merge(document, into: Snapshot())
        #expect(plan.hosts.map(\.name) == ["web"])
        #expect(plan.hosts.first?.user == "deploy")
    }
}
