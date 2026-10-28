import Foundation
import Testing

@testable import Shellhand

/// Configs that include themselves, which people write by accident.
///
/// This matters more than it used to. `parse` ran only when somebody asked
/// to import; the resolver reads the config now, on the first snapshot and
/// whenever it changes — so a config that cannot be parsed quickly is a
/// window that does not open rather than an import that takes a while.
@Suite("configs that include themselves")
nonisolated struct IncludeCycleTests {
    private func write(_ text: String, to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    @Test("a config that includes itself is read once and still read")
    func includesItself() throws {
        let path = TestScratch.directory("self") + "/config"
        try write("Include \(path)\nHost web\n  HostName 10.0.0.1\n", to: path)

        let hosts = SSHConfigFile.read(path: path).hosts
        #expect(hosts.map(\.name) == ["web"])
        #expect(hosts.first?.addr == "10.0.0.1")
    }

    @Test("two configs that include each other are each read once")
    func includeEachOther() throws {
        let root = TestScratch.directory("pair")
        let a = root + "/a", b = root + "/b"
        try write("Include \(b)\nHost web\n  HostName 10.0.0.1\n", to: a)
        try write("Include \(a)\nHost db\n  HostName 10.0.0.2\n", to: b)

        let hosts = SSHConfigFile.read(path: a).hosts
        #expect(hosts.map(\.name).sorted() == ["db", "web"])
    }

    /// **The one the depth cap could not save.** A cap terminates a cycle and
    /// does nothing about its width: `Include conf.d/*` written inside a file
    /// that is itself in `conf.d` branches by however many files are there,
    /// at every level. With a cap of 8 and nothing else this was measured at
    /// 29ms for two files, 346ms for three and 2.4 seconds for four — so the
    /// ten a real `conf.d` holds would never have finished.
    ///
    /// Six files, measured both ways on the same machine: **48 seconds**
    /// with each file read as many times as it is reached, about a
    /// millisecond when it is read once.
    ///
    /// **This is the only test here that fails without the fix.** The two
    /// above pass either way, because a cap does handle a cycle that does not
    /// branch — which is exactly why they are not the guard and this is.
    @Test("a glob include that loops back on itself finishes at once")
    func branchingCycle() throws {
        let root = TestScratch.directory("branching")
        let folder = root + "/conf.d"
        for i in 0..<6 {
            try write("Include \(folder)/*\nHost leaf-\(i)\n  HostName 10.0.0.\(i)\n",
                      to: "\(folder)/\(i).conf")
        }
        let main = root + "/config"
        try write("Include \(folder)/*\n", to: main)

        let began = Date()
        let hosts = SSHConfigFile.read(path: main).hosts
        let took = Date().timeIntervalSince(began)

        #expect(hosts.map(\.name) == (0..<6).map { "leaf-\($0)" })
        #expect(took < 1, "took \(Int(took * 1000))ms")
    }

    /// Reading a file once is not weaker than reading it twice, which is the
    /// claim the fix rests on: ssh keeps a setting's **first** value, so a
    /// second copy of the same blocks could never have won anything. Here one
    /// file is reached two ways, and what it says still stands.
    @Test("a file reached two ways still says what it says")
    func diamond() throws {
        let root = TestScratch.directory("diamond")
        let common = root + "/common"
        try write("Host shared\n  HostName 10.0.0.9\n  User alice\n", to: common)
        try write("Include \(common)\n", to: root + "/a")
        try write("Include \(common)\n", to: root + "/b")
        let main = root + "/config"
        try write("Include \(root)/a\nInclude \(root)/b\n", to: main)

        let hosts = SSHConfigFile.read(path: main).hosts
        #expect(hosts.map(\.name) == ["shared"])
        #expect(hosts.first?.user == "alice")
        #expect(hosts.first?.addr == "10.0.0.9")
    }
}
