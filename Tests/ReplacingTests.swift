import Testing
@testable import Shellhand

@Suite("What is already there")
nonisolated struct ReplacingTests {
    @Test("nothing arriving means nothing clashes")
    func emptyCarrying() {
        #expect(Replacing.clashes(
            carrying: [], arriving: ["a", "b"], caseInsensitive: false).isEmpty)
    }

    @Test("an empty folder means nothing clashes")
    func emptyArriving() {
        #expect(Replacing.clashes(
            carrying: ["a"], arriving: [], caseInsensitive: false).isEmpty)
    }

    @Test("only the names the far end already has")
    func some() {
        #expect(Replacing.clashes(
            carrying: ["a", "b", "c"], arriving: ["b", "d"],
            caseInsensitive: false) == ["b"])
    }

    @Test("the order asked for is kept, so the question reads like the drag")
    func keepsOrder() {
        #expect(Replacing.clashes(
            carrying: ["c", "a", "b"], arriving: ["a", "b", "c"],
            caseInsensitive: false) == ["c", "a", "b"])
    }

    @Test("a server that minds case does not clash on spelling alone")
    func caseSensitive() {
        #expect(Replacing.clashes(
            carrying: ["README"], arriving: ["readme"],
            caseInsensitive: false).isEmpty)
    }

    @Test("this Mac's disk does not mind, so the same two names do clash")
    func caseInsensitive() {
        #expect(Replacing.clashes(
            carrying: ["README"], arriving: ["readme"],
            caseInsensitive: true) == ["README"])
    }

    @Test("replacing carries everything, clashes and all")
    func replaceCarriesAll() {
        #expect(Replacing.carrying(
            ["a", "b", "c"], clashes: ["b"], answer: .replace) == ["a", "b", "c"])
    }

    @Test("skipping leaves the clashes behind and carries the rest")
    func skipLeavesClashes() {
        #expect(Replacing.carrying(
            ["a", "b", "c"], clashes: ["b"], answer: .skip) == ["a", "c"])
    }

    @Test("skipping everything carries nothing, rather than carrying all")
    func skipEverything() {
        #expect(Replacing.carrying(
            ["a", "b"], clashes: ["a", "b"], answer: .skip).isEmpty)
    }

    @Test("one clash is named, several are counted")
    func wording() {
        #expect(Replacing.question(["notes.txt"], into: "Documents")
            == "“notes.txt” is already in Documents.")
        #expect(Replacing.question(["a", "b", "c"], into: "Documents")
            == "3 of these are already in Documents.")
    }
}
