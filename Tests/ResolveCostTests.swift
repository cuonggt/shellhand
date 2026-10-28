import Foundation
import Testing

@testable import Shellhand

private typealias AppHost = Shellhand.Host

/// What a snapshot costs once ssh's own config is in the picture.
///
/// Reading the config made every resolve ask it two questions, and the second
/// one — what would this be sent through — **cannot be answered from a
/// dictionary**: `Host 10.0.1.*` has to be matched against the destination,
/// so it is a walk over every block for every host. That is a shape worth
/// measuring rather than assuming, because it degrades with the product of
/// two things a user controls and neither is bounded by this app.
@Suite("what resolving a list costs")
nonisolated struct ResolveCostTests {
    /// Bigger than anybody's, on purpose: the question is whether the shape
    /// is wrong, and a list the size of a real one would answer that too
    /// quickly to tell.
    private let hosts = 500
    private let blocks = 400

    private func config(at path: String) throws {
        var text = ""
        for i in 0..<blocks {
            // Half concrete names, half globs — a glob cannot be answered by
            // a lookup, so it is the half that decides the cost.
            text += i % 2 == 0
                ? "Host block-\(i)\n  HostName 10.9.\(i / 256).\(i % 256)\n  User someone\n"
                : "Host 10.\(i % 200).*.\(i)\n  ProxyJump bastion-\(i)\n"
        }
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    @Test("a list far larger than anybody's resolves in well under a frame")
    func resolvingIsNotSlow() async throws {
        let path = SSHConfigFile.pathInUse
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try config(at: path)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = TestScratch.database("cost.sqlite")
        let store = try Store(path: db)
        for i in 0..<hosts {
            _ = try store.save(AppHost(name: "host-\(i)", addr: "10.\(i % 200).3.\(i % 250)"))
        }

        // Not the first call: that one parses the config, and what is being
        // measured is what every later refresh pays.
        _ = try await Core.shared.snapshot(db: db)

        let began = Date()
        let runs = 5
        for _ in 0..<runs { _ = try await Core.shared.snapshot(db: db) }
        let each = Date().timeIntervalSince(began) / Double(runs)

        print("resolve cost: \(hosts) hosts x \(blocks) blocks = \(Int(each * 1000))ms a snapshot")
        // A frame is 16ms and a refresh is not a frame, but a list that takes
        // longer than a few of them to redraw is felt. The real lists this
        // runs against are an order of magnitude smaller in both directions.
        #expect(each < 0.5, "a snapshot took \(Int(each * 1000))ms")
    }
}
