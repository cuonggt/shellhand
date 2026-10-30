import Foundation
import Testing
@testable import Shellhand

@Suite("Reading tags as they were typed")
nonisolated struct TagCleanTests {
    @Test("a comma, a semicolon, a bar or a space all separate")
    func separators() {
        #expect(Tags.clean("web, eu") == ["web", "eu"])
        #expect(Tags.clean("web;eu") == ["web", "eu"])
        #expect(Tags.clean("web|eu") == ["web", "eu"])
        #expect(Tags.clean("web eu") == ["web", "eu"])
        #expect(Tags.clean("web ,; eu") == ["web", "eu"])
    }

    @Test("the order they were typed in is the order they keep")
    func order() {
        #expect(Tags.clean("zulu, alpha, mike") == ["zulu", "alpha", "mike"])
    }

    @Test("the same tag twice is the same tag once, whatever the case")
    func deduped() {
        #expect(Tags.clean("web, Web, WEB") == ["web"])
        #expect(Tags.clean("eu, web, eu") == ["eu", "web"])
    }

    @Test("nothing at all is no tags, not one empty one")
    func empties() {
        #expect(Tags.clean("") == [])
        #expect(Tags.clean("   ") == [])
        #expect(Tags.clean(",,,") == [])
        #expect(Tags.clean(" , web , ") == ["web"])
    }

    @Test("what is read writes back the way the field shows it")
    func roundTrip() {
        #expect(Tags.text(Tags.clean("web,eu")) == "web, eu")
        #expect(Tags.clean(Tags.text(["web", "eu"])) == ["web", "eu"])
    }
}

@Suite("The tags in use")
nonisolated struct TagListTests {
    private let hosts = [
        Host(id: "1", name: "web-1", tags: ["web", "eu"]),
        Host(id: "2", name: "web-2", tags: ["Web", "us"]),
        Host(id: "3", name: "db", tags: ["db"]),
        Host(id: "4", name: "bare"),
    ]

    @Test("every tag any host carries, sorted, each one once")
    func all() {
        #expect(Tags.all(in: hosts) == ["db", "eu", "us", "web"])
    }

    @Test("two spellings of one tag are one chip, spelled as it was first written")
    func caseFolded() {
        let all = Tags.all(in: hosts)
        #expect(all.count(where: { $0.lowercased() == "web" }) == 1)
        #expect(all.contains("web"))
    }

    @Test("no hosts, no tags")
    func none() {
        #expect(Tags.all(in: []).isEmpty)
        #expect(Tags.all(in: [Host(id: "1", name: "bare")]).isEmpty)
    }
}

@Suite("Narrowing by tag")
nonisolated struct TagFilterTests {
    private let hosts = [
        Host(id: "1", name: "web-eu", tags: ["web", "eu"]),
        Host(id: "2", name: "web-us", tags: ["web", "us"]),
        Host(id: "3", name: "db-eu", tags: ["db", "eu"]),
    ]

    @Test("one tag gives the hosts that carry it")
    func one() {
        #expect(Tags.hosts(hosts, taggedWith: ["web"]).map(\.name) == ["web-eu", "web-us"])
    }

    @Test("two tags narrow rather than widen — both, not either")
    func both() {
        #expect(Tags.hosts(hosts, taggedWith: ["web", "eu"]).map(\.name) == ["web-eu"])
    }

    @Test("a combination nothing carries gives nothing, not everything")
    func neither() {
        #expect(Tags.hosts(hosts, taggedWith: ["web", "db"]).isEmpty)
    }

    @Test("no tags chosen is not a filter at all")
    func unfiltered() {
        #expect(Tags.hosts(hosts, taggedWith: []).count == 3)
    }

    @Test("the case of the chip and the case on the host need not agree")
    func caseInsensitive() {
        #expect(Tags.hosts(hosts, taggedWith: ["WEB"]).count == 2)
        #expect(Tags.has("Eu", hosts[0]))
    }
}

@Suite("Renaming and deleting a tag")
nonisolated struct TagEditTests {
    private let hosts = [
        Host(id: "1", name: "web-1", tags: ["web", "eu"]),
        Host(id: "2", name: "web-2", tags: ["Web"]),
        Host(id: "3", name: "db", tags: ["db"]),
    ]

    @Test("only the hosts that carry it are rewritten")
    func touchesWhatItMust() {
        let changed = Tags.renaming("web", to: "frontend", in: hosts)
        #expect(changed.map(\.id).sorted() == ["1", "2"])
        #expect(changed.first { $0.id == "1" }?.tags == ["frontend", "eu"])
    }

    @Test("the case it was written in on each host does not stop the rename")
    func caseInsensitive() {
        let changed = Tags.renaming("WEB", to: "frontend", in: hosts)
        #expect(changed.count == 2)
        #expect(changed.first { $0.id == "2" }?.tags == ["frontend"])
    }

    @Test("renaming onto a tag that already exists merges the two")
    func merges() {
        let changed = Tags.renaming("eu", to: "web", in: hosts)
        // web-1 had both; it should come out with one, not with web twice.
        #expect(changed.first { $0.id == "1" }?.tags == ["web"])
    }

    @Test("renaming a tag to exactly what it is writes nothing")
    func noop() {
        #expect(Tags.renaming("web", to: "web", in: hosts).isEmpty)
        #expect(Tags.renaming("web", to: " web ", in: hosts).isEmpty)
    }

    @Test("a rename that only changes the case settles the spelling everywhere")
    func normalisesCase() {
        // web-1 wrote it `web` and web-2 wrote it `Web`; the chip shows one
        // tag, so this is how the two are made to agree.
        let changed = Tags.renaming("web", to: "WEB", in: hosts)
        #expect(changed.map(\.id).sorted() == ["1", "2"])
        #expect(changed.first { $0.id == "2" }?.tags == ["WEB"])
    }

    @Test("a rename to nothing is refused rather than blanking the tag")
    func refusesEmpty() {
        #expect(Tags.renaming("web", to: "", in: hosts).isEmpty)
        #expect(Tags.renaming("web", to: "  ", in: hosts).isEmpty)
    }

    @Test("a tag nothing carries renames nothing")
    func unknown() {
        #expect(Tags.renaming("nothing", to: "something", in: hosts).isEmpty)
    }

    @Test("deleting takes it off the hosts that carry it and leaves the rest")
    func deletes() {
        let changed = Tags.removing("web", from: hosts)
        #expect(changed.map(\.id).sorted() == ["1", "2"])
        #expect(changed.first { $0.id == "1" }?.tags == ["eu"])
        #expect(changed.first { $0.id == "2" }?.tags == [])
    }

    @Test("a tag nothing carries deletes nothing")
    func deleteUnknown() {
        #expect(Tags.removing("nothing", from: hosts).isEmpty)
    }
}

@Suite("What a tag may be called")
nonisolated struct TagNameTests {
    @Test("a tag needs a name")
    func needsAName() {
        #expect(Tags.problem(withTag: "") != nil)
        #expect(Tags.problem(withTag: "   ") != nil)
    }

    @Test("a tag is one word, and says so rather than quietly making two")
    func oneWord() {
        #expect(Tags.problem(withTag: "north europe") != nil)
        #expect(Tags.problem(withTag: "web,eu") != nil)
    }

    @Test("an ordinary tag is fine")
    func fine() {
        #expect(Tags.problem(withTag: "web") == nil)
        #expect(Tags.problem(withTag: " eu ") == nil)
        #expect(Tags.problem(withTag: "web-1") == nil)
    }
}

@Suite("What ends a tag")
nonisolated struct TagSeparatorTests {
    @Test("a comma, a semicolon, a bar or a space all end one")
    func separators() {
        for character in [",", ";", "|", " ", "\t", "\n"] {
            #expect(Tags.separates(Character(character)), "\(character.debugDescription)")
        }
    }

    @Test("a letter, a digit and a dash do not")
    func notSeparators() {
        for character in ["a", "Z", "7", "-", "_", "."] {
            #expect(!Tags.separates(Character(character)), "\(character)")
        }
    }

    @Test("what splits and what ends a tag are the same rule")
    func sameRule() {
        // Written twice, a tag typed by hand and a tag imported from a sheet
        // would come out spelled differently.
        for character in [",", ";", "|", " "] {
            #expect(Tags.clean("web\(character)eu") == ["web", "eu"], "\(character)")
        }
    }
}

@Suite("What a host is saved with")
nonisolated struct TagSaveTests {
    /// The last tag typed before clicking Save, without pressing Return
    /// first, was dropped: the editor saved only the tags already made.
    @Test("a tag still being typed is kept on save")
    func typingIsKept() {
        #expect(Tags.saved("web, eu", typing: "db") == ["web", "eu", "db"])
        #expect(Tags.saved("", typing: "db") == ["db"])
    }

    @Test("an empty field adds nothing, and a repeat stays once")
    func nothingExtra() {
        #expect(Tags.saved("web, eu", typing: "") == ["web", "eu"])
        #expect(Tags.saved("web", typing: "  ") == ["web"])
        #expect(Tags.saved("web", typing: "WEB") == ["web"])
    }
}
