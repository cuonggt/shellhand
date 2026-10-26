import Foundation
import Testing
@testable import Shellhand

/// `Foundation` is needed here for the directories, and it brings
/// `Foundation.Host` with it, so the app's own is named — as `HostStoreTests`
/// does for the same reason.
private typealias AppHost = Shellhand.Host

/// A file pane, and the two of them together, against directories on this
/// disk.
///
/// Reachable without a server because **a pane pointed at this Mac needs no
/// session at all**: `Core.list` reads the local disk when the session id is
/// empty, and local-to-local copying is a real thing this window does rather
/// than a contrivance for a test. What that buys is the two pieces of
/// orchestration most worth holding still — the guard that keeps a pane from
/// re-opening, and the continuation a copy is parked on while the replace
/// question is up. What a pane *calls* itself is `Places`, and tested there.
@MainActor
@Suite("File panes", .timeLimit(.minutes(1)))
struct FilesTests {
    private func scratchDB() -> String {
        TestScratch.database()
    }

    /// A directory of our own, holding the named files.
    private func folder(_ files: [String: String] = [:]) -> String {
        let path = TestScratch.directory("files")
        for (name, contents) in files {
            try? contents.write(toFile: path + "/" + name, atomically: true, encoding: .utf8)
        }
        return path
    }

    private func read(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// The copy parks on a continuation, so this waits on the clock with a
    /// ceiling: a question that never arrives fails rather than hangs.
    private func waitUntil(_ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if done() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return done()
    }

    /// Both sides local, each in a directory of its own.
    private func twoPanes(from: String, into: String) async -> FilesModel {
        let model = FilesModel(db: scratchDB())
        await model.left.use(nil)
        await model.left.go(to: from)
        await model.right.use(nil)
        await model.right.go(to: into)
        return model
    }

    // MARK: pointing a pane

    @Test("a pane starts as a question and becomes this Mac")
    func pointedAtThisMac() async {
        let place = FilePlace(db: scratchDB())
        #expect(!place.chosen)
        #expect(!place.isLocal)

        await place.use(nil)
        #expect(place.chosen)
        #expect(place.isLocal)
        #expect(!place.listing.path.isEmpty)
    }

    /// The guard that keeps opening to once. Without it every re-entry walks
    /// to the home directory again — and what that cost was worse than a
    /// wasted walk: two opens went through together, the second's walk landed
    /// after the first had navigated away, and a download went to the wrong
    /// folder with the job reporting success.
    @Test("pointing a pane where it already is leaves it where it is")
    func pointingTwiceDoesNothing() async {
        let dir = folder(["a.txt": "one"])
        let place = FilePlace(db: scratchDB())
        await place.use(nil)
        await place.go(to: dir)
        #expect(place.listing.path == dir)

        await place.use(nil)
        // Still where it was walked to, not back at the home directory.
        #expect(place.listing.path == dir)
    }

    @Test("a pane lists what is in the directory it is pointed at")
    func listsTheDirectory() async {
        let dir = folder(["a.txt": "one", "b.txt": "two"])
        let place = FilePlace(db: scratchDB())
        await place.use(nil)
        await place.go(to: dir)
        #expect(place.entries.map(\.name).sorted() == ["a.txt", "b.txt"])
    }

    /// Walks up into a directory of ours rather than wherever the temporary
    /// one happens to live: the first version of this went up into the system
    /// temporary directory and spent **nine seconds** listing every other
    /// process's leavings, which is slow and says nothing twice.
    @Test("a pane walks up to the parent, and names a child under it")
    func walksUp() async {
        let parent = folder()
        let child = parent + "/inner"
        try? FileManager.default.createDirectory(
            atPath: child, withIntermediateDirectories: true)

        let place = FilePlace(db: scratchDB())
        await place.use(nil)
        await place.go(to: child)
        #expect(place.path("a.txt") == child + "/a.txt")

        await place.parent()
        #expect(place.listing.path == parent)
        #expect(place.entries.map(\.name) == ["inner"])
    }

    // MARK: the question a clash puts up, and the copy waiting on it

    @Test("a clash asks first, and carries nothing until it is answered")
    func clashAsksFirst() async throws {
        let from = folder(["a.txt": "new"]), into = folder(["a.txt": "old"])
        let model = await twoPanes(from: from, into: into)
        let entry = try #require(model.left.entries.first { $0.name == "a.txt" })

        let copying = Task { await model.copy([entry], from: model.left, to: model.right) }
        #expect(await waitUntil { model.asking != nil })

        let question = try #require(model.asking)
        #expect(question.clashes == ["a.txt"])
        // Still the old file: the question comes before anything is carried.
        #expect(read(into + "/a.txt") == "old")

        model.answer(.replace)
        await copying.value
        #expect(read(into + "/a.txt") == "new")
        #expect(model.asking == nil)
    }

    /// **The one that matters most.** The dialog's dismissal answers Cancel as
    /// well as its buttons do, because a copy waiting on a question that is no
    /// longer on screen is worse than one that overwrites: it waits for ever.
    @Test("cancelling carries nothing and leaves nothing waiting")
    func cancellingCarriesNothing() async throws {
        let from = folder(["a.txt": "new"]), into = folder(["a.txt": "old"])
        let model = await twoPanes(from: from, into: into)
        let entry = try #require(model.left.entries.first { $0.name == "a.txt" })

        let copying = Task { await model.copy([entry], from: model.left, to: model.right) }
        #expect(await waitUntil { model.asking != nil })

        model.answer(nil)
        // Returns at all, which is the whole point, and carried nothing.
        await copying.value
        #expect(read(into + "/a.txt") == "old")
        #expect(model.asking == nil)
    }

    @Test("skipping keeps what is already there and carries the rest")
    func skippingKeepsIt() async throws {
        let from = folder(["a.txt": "new", "b.txt": "fresh"])
        let into = folder(["a.txt": "old"])
        let model = await twoPanes(from: from, into: into)
        let entries = model.left.entries.filter { ["a.txt", "b.txt"].contains($0.name) }
        #expect(entries.count == 2)

        let copying = Task { await model.copy(entries, from: model.left, to: model.right) }
        #expect(await waitUntil { model.asking != nil })

        model.answer(.skip)
        await copying.value
        #expect(read(into + "/a.txt") == "old")
        #expect(read(into + "/b.txt") == "fresh")
    }

    /// One question for the whole batch, not one per file: forty answered
    /// forty times is a dialog nobody reads by the fourth.
    @Test("two clashes are one question")
    func twoClashesOneQuestion() async throws {
        let from = folder(["a.txt": "new", "b.txt": "new"])
        let into = folder(["a.txt": "old", "b.txt": "old"])
        let model = await twoPanes(from: from, into: into)
        let entries = model.left.entries.filter { ["a.txt", "b.txt"].contains($0.name) }

        let copying = Task { await model.copy(entries, from: model.left, to: model.right) }
        #expect(await waitUntil { model.asking != nil })
        let question = try #require(model.asking)
        #expect(question.clashes.sorted() == ["a.txt", "b.txt"])

        model.answer(.replace)
        await copying.value
        #expect(read(into + "/a.txt") == "new")
        #expect(read(into + "/b.txt") == "new")
    }

    @Test("a name nothing clashes with is carried without asking")
    func noClashNoQuestion() async throws {
        let from = folder(["new.txt": "fresh"]), into = folder(["other.txt": "x"])
        let model = await twoPanes(from: from, into: into)
        let entry = try #require(model.left.entries.first { $0.name == "new.txt" })

        await model.copy([entry], from: model.left, to: model.right)
        #expect(model.asking == nil)
        #expect(read(into + "/new.txt") == "fresh")
        #expect(model.transfers.isEmpty)
    }

    // MARK: a pane asked to open twice at once

    /// A store of our own holding a host nothing answers for. Port 1 refuses
    /// at once, so ssh fails immediately and reaches no machine at all —
    /// which is what makes driving the connecting path cheap enough to do.
    private func refusingHost() async throws -> (db: String, host: AppHost) {
        let db = scratchDB()
        let store = HostStore(dbPath: db)
        await store.refresh()
        let host = try #require(
            await store.save(AppHost(name: "nowhere", addr: "127.0.0.1", port: 1)))
        return (db, host)
    }

    /// The backstop behind the early guard, and the two turn away different
    /// things. The early one refuses a pane pointed where it already is; this
    /// one refuses the **second of two opens in flight at once**, which the
    /// early guard lets straight through — its `listing.path.isEmpty` clause
    /// is true for as long as the first open is still connecting. Letting
    /// both through is what put a download in the wrong folder with the job
    /// reporting success.
    ///
    /// **Both tasks are made before either runs, and nothing here polls.**
    /// Waiting for `connecting` to appear was the first attempt and it does
    /// not work: a refused connection on loopback is quicker than any poll,
    /// so the first call had finished before it could be seen and the second
    /// was a sequential retry measuring nothing. This way needs no timing at
    /// all — whichever task the actor runs first cannot be interrupted before
    /// its `await`, so it gets there with `opening` set, and the other is
    /// turned away whichever order they go in.
    @Test("a pane asked to open twice at once opens once")
    func opensOnceWhenAskedTwice() async throws {
        let (db, host) = try await refusingHost()
        let place = FilePlace(db: db)

        let first = Task { await place.use(host) }
        let second = Task { await place.use(host) }
        await first.value
        await second.value

        #expect(place.opens == 1, "opens=\(place.opens)")
    }

    /// The other side of that guard, and worth its own test: it must not turn
    /// away a **retry**. A host that refused leaves `host` nil, so pointing
    /// the pane at it again is a fresh attempt rather than a re-entry — which
    /// is how someone fixes a typo in a port and tries once more.
    @Test("a pane that failed to open will try again")
    func retriesAfterAFailure() async throws {
        let (db, host) = try await refusingHost()
        let place = FilePlace(db: db)

        await place.use(host)
        #expect(place.opens == 1)
        #expect(place.failure != nil)

        await place.use(host)
        #expect(place.opens == 2, "a second attempt should have been made")
    }

    /// Why `chosen` is set **before** the connecting starts: a host that
    /// refuses has to leave the pane saying what went wrong, rather than
    /// falling back to "Choose a host", which reads as though nothing had
    /// been tried.
    @Test("a host that refuses leaves the pane showing why, not asking again")
    func refusedShowsWhy() async throws {
        let (db, host) = try await refusingHost()
        let place = FilePlace(db: db)

        await place.use(host)
        #expect(place.chosen)
        #expect(place.failure != nil)
        #expect(place.host == nil)
        #expect(!place.connecting)
        #expect(place.opens == 1)
    }
}
