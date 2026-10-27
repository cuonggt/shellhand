import Foundation
import Testing

@testable import Shellhand

/// The ssh layer itself, held against macOS's own `sshd`: `SFTPClient.connect`
/// end to end, through the same `ssh` and the same argv the app builds.
///
/// Until this, `ssh` was the one layer nothing checked — connecting, logging
/// in, `-i`, ports, `BatchMode`, jump hosts — and the only answer on record was
/// a Go server and a toolchain to build it. `/usr/sbin/sshd` runs as whoever
/// runs the suite, on a loopback port of its own, with keys made for the run in
/// `TestScratch`, so it needs nothing switched on: Remote Login stays off.
///
/// **Every connection here is kept off its user's own `~/.ssh`**, and that is
/// the whole of the care this suite takes. `LocalSSHD.isolation` goes to
/// `connect` as settings nothing may override, so it leads every hop, a jump's
/// own `ssh` included. The last test checks that the real known_hosts is
/// exactly as it was, rather than trusting that it must be.
///
/// While a test runs, this is a login server as you on loopback, for whoever
/// holds a key that lives in `TestScratch` — your own trust boundary, but a
/// real one — so each server lives only as long as its test.
@Suite("ssh against macOS's own sshd", .timeLimit(.minutes(1)))
nonisolated struct SSHTransportTests {
    @Test("connect reaches a real sshd, and the session it opens works")
    func connects() async throws {
        let server = try LocalSSHD()
        defer { server.stop() }
        let dir = try LocalSSHD.settled(TestScratch.directory("over-ssh"))
        FileManager.default.createFile(atPath: dir + "/hello.txt", contents: Data("hi".utf8))

        let home = try LocalSSHD.settled(NSHomeDirectory())

        try await server.session { client in
            // sshd starts a session in the account's home, and `begin` asked.
            #expect(await client.home == home)
            let names = try await client.list(dir).map(\.name)
            #expect(names == ["hello.txt"])
        }
    }

    @Test("a download over real ssh is byte for byte what was there")
    func downloads() async throws {
        let server = try LocalSSHD()
        defer { server.stop() }
        let held = SFTPRealServerTests.bytes(600_001)
        let source = try LocalSSHD.settled(TestScratch.directory("ssh-source")) + "/held.bin"
        FileManager.default.createFile(atPath: source, contents: held)
        let local = TestScratch.directory("ssh-download") + "/held.bin"

        try await server.session { client in try await client.download(source, to: local) }
        #expect(FileManager.default.contents(atPath: local) == held)
    }

    /// The path `connect` takes when ssh will not let it in — the one that
    /// reads ssh's own stderr, and the one that had to let go of the client
    /// first or wait on a live child for ever.
    @Test("a key the server does not take fails with ssh's own sentence")
    func keyNotTaken() async throws {
        let server = try LocalSSHD()
        defer { server.stop() }
        let stranger = try LocalSSHD.key(in: TestScratch.directory("stranger"))

        do {
            _ = try await SFTPClient.connect(
                server.resolved(identity: stranger), fixed: server.isolation())
            Issue.record("a key nobody authorised should not have got in")
        } catch let error as SFTPError {
            #expect(error.message.contains("Permission denied"), "ssh said: \(error.message)")
        }
    }

    /// BatchMode and strict checking together refuse an unknown host rather
    /// than ask, and must not write its key down anywhere — not even here.
    @Test("a host whose key is not known is refused, and nothing is written")
    func hostKeyNotKnown() async throws {
        let server = try LocalSSHD()
        defer { server.stop() }
        let empty = TestScratch.directory("no-hosts") + "/known_hosts"
        FileManager.default.createFile(atPath: empty, contents: Data())

        do {
            _ = try await SFTPClient.connect(
                server.resolved(), fixed: server.isolation(knownHosts: empty))
            Issue.record("an unknown host key should have been refused")
        } catch let error as SFTPError {
            #expect(error.message.contains("Host key verification failed"), "ssh said: \(error.message)")
        }
        #expect(FileManager.default.contents(atPath: empty) == Data())
    }

    /// A jump spelled the way the app spells one — a nested `ssh -W` as the
    /// `ProxyCommand`, carrying the same fixed settings — through this server
    /// to itself. Two logins prove the hop was gone through rather than round.
    @Test("a jump host is gone through, not around")
    func jumpHost() async throws {
        let server = try LocalSSHD()
        defer { server.stop() }
        var resolved = server.resolved()
        resolved.jumps = [
            Hop(name: "hop", addr: "127.0.0.1", port: server.port, user: server.user,
                identity: server.clientKey)
        ]

        try await server.session(resolved) { client in _ = try await client.list(server.root) }
        let logins = await server.loginsSettled(at: 2)
        #expect(logins == 2, "sshd let somebody in \(logins) times, so the hop was not taken")
    }

    /// The promise this suite makes, checked rather than trusted: size and
    /// modification time, read and never opened.
    @Test("your own known_hosts is exactly as it was")
    func ownKnownHostsUntouched() async throws {
        let mine = NSHomeDirectory() + "/.ssh/known_hosts"
        let before = Self.fingerprint(mine)
        let server = try LocalSSHD()
        defer { server.stop() }

        try await server.session { client in _ = try await client.list(server.root) }
        #expect(Self.fingerprint(mine) == before)
    }

    static func fingerprint(_ path: String) -> String {
        guard let found = try? FileManager.default.attributesOfItem(atPath: path) else { return "absent" }
        let modified = (found[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(found[.size] ?? 0) bytes, modified \(modified)"
    }
}

/// macOS's own `sshd`, run as whoever runs the suite on a loopback port of its
/// own, with keys made for it in `TestScratch` and a log of its own there.
///
/// `nonisolated` for the reason every test type here is: the app target
/// defaults to MainActor and `Tests/` is compiled into it.
nonisolated final class LocalSSHD: @unchecked Sendable {
    /// Its scratch directory, symlinks settled: somewhere real to list.
    let root: String
    let port: Int
    let user = NSUserName()
    /// The one key this server takes.
    let clientKey: String
    /// A known_hosts holding this server's key and nothing else.
    let knownHosts: String
    private let log: String
    private let process = Process()

    init() throws {
        root = try Self.settled(TestScratch.directory("sshd"))
        log = root + "/sshd.log"
        let hostKey = try Self.key(in: root, named: "host")
        clientKey = try Self.key(in: root, named: "client")
        try FileManager.default.copyItem(atPath: clientKey + ".pub", toPath: root + "/authorized_keys")
        port = Self.freePort()

        // Read-only, because the session starts in the real home directory with
        // no jail around it: a stray path in a test should fail, not write.
        // `UsePAM` and `StrictModes` are off because a non-root `sshd` can use
        // neither, and the scratch directory is not as private as `~/.ssh`.
        let config = root + "/sshd_config"
        try """
            ListenAddress 127.0.0.1
            Port \(port)
            HostKey \(hostKey)
            PidFile \(root)/sshd.pid
            AuthorizedKeysFile \(root)/authorized_keys
            PubkeyAuthentication yes
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            UsePAM no
            StrictModes no
            AllowUsers \(user)
            Subsystem sftp /usr/libexec/sftp-server -R

            """.write(toFile: config, atomically: true, encoding: .utf8)
        let hostPublic = try String(contentsOfFile: hostKey + ".pub", encoding: .utf8)
            .split(separator: " ").prefix(2).joined(separator: " ")
        knownHosts = root + "/known_hosts"
        try "[127.0.0.1]:\(port) \(hostPublic)\n".write(toFile: knownHosts, atomically: true, encoding: .utf8)

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
        process.arguments = ["-D", "-E", log, "-f", config]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        // Up when it says it is listening, which it writes once it is.
        let until = Date().addingTimeInterval(10)
        while !logText.contains("Server listening on 127.0.0.1 port \(port)") {
            guard process.isRunning, Date() < until else {
                stop()
                throw SFTPError("sshd did not start listening: \(logText.suffix(400))")
            }
            usleep(20_000)
        }
    }

    /// What every connection to this server is handed, as settings nothing may
    /// override, so that it reads and writes none of its user's own files.
    ///
    /// `-F /dev/null` matters most: without it `~/.ssh/config` is read, and a
    /// `Host *` there — a `ProxyCommand`, a `ControlMaster`, a `Match exec`
    /// that runs a program — joins in. The rest close what ssh reaches without
    /// any config at all: the agent `SSH_AUTH_SOCK` names, the keys in `~/.ssh`
    /// it tries by default, and the known_hosts it would both read and write.
    /// `StrictHostKeyChecking=yes` makes a broken isolation fail at the door
    /// rather than write a key anywhere.
    ///
    /// **Two settings are deliberately absent.** These lead, so a
    /// `ProxyCommand=none` would beat the very `ProxyCommand` that `SSHArgs`
    /// spells a jump with, and `ClearAllForwardings` could take the hop's `-W`
    /// with it. `-F /dev/null` already keeps out every forward a config holds.
    func isolation(knownHosts: String? = nil) -> [String] {
        [
            "-F", "/dev/null",
            "-o", "UserKnownHostsFile=" + (knownHosts ?? self.knownHosts),
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UpdateHostKeys=no",
            "-o", "IdentityAgent=none",
            "-o", "IdentitiesOnly=yes",
            "-o", "ControlMaster=no",
            "-o", "ControlPath=none",
        ]
    }

    /// This server, as the app would resolve a host pointed at it.
    func resolved(identity: String? = nil) -> Resolved {
        Resolved(
            host: Shellhand.Host(name: "local-sshd", addr: "127.0.0.1", port: port),
            user: user, identity: identity ?? clientKey)
    }

    /// Connects, runs `body`, and lets the client go whether or not it threw —
    /// a client left open keeps its `ssh` and a session's `sshd` alive past
    /// the server that let it in.
    func session(
        _ resolved: Resolved? = nil, _ body: (SFTPClient) async throws -> Void
    ) async throws {
        let client = try await SFTPClient.connect(resolved ?? self.resolved(), fixed: isolation())
        do {
            try await body(client)
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

    /// How many times this server has let somebody in, once the count has had
    /// a moment to reach `expected` — each session's `sshd` writes its own
    /// line, so the last can land a little after the connection is up.
    func loginsSettled(at expected: Int) async -> Int {
        for _ in 0..<100 where logins < expected {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return logins
    }

    var logins: Int { logText.components(separatedBy: "Accepted publickey").count - 1 }

    private var logText: String { (try? String(contentsOfFile: log, encoding: .utf8)) ?? "" }

    /// Ends the server, boundedly. Sessions already open are their clients'
    /// to end, which `session` does.
    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let until = Date().addingTimeInterval(5)
        while process.isRunning && Date() < until { usleep(10_000) }
    }

    /// A fresh ed25519 key pair with no passphrase; the private half's path.
    /// Input is closed so that a prompt, were there ever one, ends rather than
    /// waits.
    static func key(in dir: String, named name: String = "id") throws -> String {
        let path = dir + "/" + name
        let keygen = Process()
        keygen.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        keygen.arguments = ["-t", "ed25519", "-N", "", "-q", "-f", path]
        keygen.standardInput = FileHandle.nullDevice
        keygen.standardOutput = FileHandle.nullDevice
        keygen.standardError = FileHandle.nullDevice
        try keygen.run()
        keygen.waitUntilExit()
        guard keygen.terminationStatus == 0 else { throw SFTPError("ssh-keygen could not make \(path)") }
        return path
    }

    /// A port nothing is listening on, by asking the system for one — under
    /// `Forking`'s lock, because a socket is born inheritable on this platform
    /// and a terminal forked while it is open would hold the port.
    static func freePort() -> Int {
        Forking.exclusively {
            let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            defer { Darwin.close(socket) }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socket, $0, length) == 0 ? getsockname(socket, $0, &length) : -1
                }
            }
            return Int(UInt16(bigEndian: address.sin_port))
        }
    }

    static func settled(_ path: String) throws -> String {
        guard let settled = Darwin.realpath(path, nil) else {
            throw SFTPError("\(path) could not be resolved")
        }
        defer { free(settled) }
        return String(cString: settled)
    }
}
