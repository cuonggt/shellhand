import Foundation
import Testing
@testable import Shellhand

@Suite("Reading a CSV")
nonisolated struct CSVGrammarTests {
    @Test("values are separated by commas, and spaces around them are not part of them")
    func plain() {
        let rows = CSVHosts.rows("a, b ,c\n1,2,3\n", separator: ",")
        #expect(rows == [["a", "b", "c"], ["1", "2", "3"]])
    }

    @Test("a quoted value may hold the separator")
    func quotedSeparator() {
        let rows = CSVHosts.rows("name,note\nweb,\"London, UK\"\n", separator: ",")
        #expect(rows == [["name", "note"], ["web", "London, UK"]])
    }

    @Test("a doubled quote inside a quoted value is one quote")
    func doubledQuote() {
        let rows = CSVHosts.rows("a\n\"say \"\"hi\"\"\"\n", separator: ",")
        #expect(rows == [["a"], ["say \"hi\""]])
    }

    @Test("a quoted value may run over a line break")
    func quotedNewline() {
        let rows = CSVHosts.rows("a,b\n\"one\ntwo\",3\n", separator: ",")
        #expect(rows == [["a", "b"], ["one\ntwo", "3"]])
    }

    @Test("a quoted value keeps the spaces it was given")
    func quotedKeepsSpaces() {
        let rows = CSVHosts.rows("a\n\"  padded  \"\n", separator: ",")
        #expect(rows == [["a"], ["  padded  "]])
    }

    @Test("lines end however the machine that wrote them ended lines")
    func lineEndings() {
        #expect(CSVHosts.rows("a,b\r\n1,2\r\n", separator: ",") == [["a", "b"], ["1", "2"]])
        #expect(CSVHosts.rows("a,b\r1,2\r", separator: ",") == [["a", "b"], ["1", "2"]])
        #expect(CSVHosts.rows("a,b\n1,2", separator: ",") == [["a", "b"], ["1", "2"]])
    }

    @Test("a blank line is kept, so a complaint can name the line it is about")
    func blankLinesKept() {
        let rows = CSVHosts.rows("a\n\n1\n", separator: ",")
        #expect(rows.count == 3)
        #expect(rows[1] == [""])
    }

    @Test("a quote in the middle of a word is just a character")
    func strayQuote() {
        let rows = CSVHosts.rows("a\nit's 5\" wide\n", separator: ",")
        #expect(rows == [["a"], ["it's 5\" wide"]])
    }

    @Test("the separator is whichever one the first line actually uses")
    func separator() {
        #expect(CSVHosts.separator("name,addr\n") == ",")
        #expect(CSVHosts.separator("name;addr;port\n") == ";")
        #expect(CSVHosts.separator("name\taddr\tport\n") == "\t")
        // Nothing to go on: a one-column file is still a comma-separated one.
        #expect(CSVHosts.separator("name\nweb\n") == ",")
    }
}

@Suite("A CSV as a host list")
nonisolated struct CSVHostsTests {
    @Test("the columns are read by name, in whatever order they come")
    func columns() throws {
        let reading = try CSVHosts.read("""
            user,Port,Name,Address
            deploy,2222,bastion,10.0.0.1
            """)
        let host = try #require(reading.document.hosts.first)
        #expect(host.name == "bastion")
        #expect(host.addr == "10.0.0.1")
        #expect(host.port == 2222)
        #expect(host.user == "deploy")
    }

    @Test("a header is matched on its letters, however it is spaced or punctuated")
    func headerSpelling() throws {
        let reading = try CSVHosts.read("""
            Host Name,user_name,Identity File
            10.0.0.1,deploy,~/.ssh/id_ed25519
            """)
        let host = try #require(reading.document.hosts.first)
        #expect(host.addr == "10.0.0.1")
        #expect(host.user == "deploy")
        #expect(host.identity.hasSuffix("/.ssh/id_ed25519"))
        #expect(!host.identity.hasPrefix("~"))
    }

    @Test("port 22 is left unset, because it is what ssh does anyway")
    func defaultPort() throws {
        let reading = try CSVHosts.read("name,port\nweb,22\n")
        #expect(reading.document.hosts.first?.port == 0)
    }

    @Test("a name with no address answers to its own name")
    func nameOnly() throws {
        let reading = try CSVHosts.read("name\nbastion\n")
        let host = try #require(reading.document.hosts.first)
        #expect(host.name == "bastion")
        #expect(host.addr == "bastion")
    }

    @Test("an address with no name is known by its address")
    func addressOnly() throws {
        let reading = try CSVHosts.read("address\n10.0.0.1\n")
        let host = try #require(reading.document.hosts.first)
        #expect(host.name == "10.0.0.1")
        #expect(host.addr == "10.0.0.1")
    }

    @Test("host means the address, unless a hostname column has already taken it")
    func hostColumn() throws {
        let flat = try CSVHosts.read("host,user\n10.0.0.1,deploy\n")
        #expect(flat.document.hosts.first?.addr == "10.0.0.1")

        // The shape of an ssh config, where HostName carries the address.
        let shaped = try CSVHosts.read("host,hostname\nbastion,10.0.0.1\n")
        let host = try #require(shaped.document.hosts.first)
        #expect(host.name == "bastion")
        #expect(host.addr == "10.0.0.1")
    }

    @Test("tags in one cell are split on anything but the file's own separator")
    func tags() throws {
        let reading = try CSVHosts.read("name,tags\nweb,\"edge;live prod\"\n")
        #expect(reading.document.hosts.first?.tags == ["edge", "live", "prod"])
    }

    @Test("the groups the rows ask for are declared, so the merge can make them")
    func groups() throws {
        let reading = try CSVHosts.read("""
            name,group
            web-1,Production
            web-2,Production
            db,Staging
            """)
        #expect(reading.document.groups.map(\.name).sorted() == ["Production", "Staging"])
    }

    @Test("a column nothing can be made of is reported rather than dropped quietly")
    func ignoredColumns() throws {
        let reading = try CSVHosts.read("""
            Name,Password,Notes
            web,hunter2,the one by the window
            """)
        #expect(reading.used == ["Name"])
        #expect(reading.ignored == ["Password", "Notes"])
        #expect(reading.document.hosts.count == 1)
    }

    @Test("two columns claiming one field: the first wins and the second is reported")
    func duplicateColumns() throws {
        let reading = try CSVHosts.read("name,label\nweb,other\n")
        #expect(reading.document.hosts.first?.name == "web")
        #expect(reading.ignored == ["label"])
    }

    @Test("blank lines between rows are skipped")
    func blankRows() throws {
        let reading = try CSVHosts.read("name\nweb\n\n\ndb\n")
        #expect(reading.document.hosts.map(\.name) == ["web", "db"])
    }

    @Test("a semicolon file from a spreadsheet reads the same way")
    func semicolons() throws {
        let reading = try CSVHosts.read("name;address;port\nweb;10.0.0.1;2222\n")
        let host = try #require(reading.document.hosts.first)
        #expect(host.addr == "10.0.0.1")
        #expect(host.port == 2222)
    }

    @Test("a header naming nothing we understand is refused, and says what it takes")
    func noUsableHeader() {
        #expect(throws: PortableError.self) {
            try CSVHosts.read("colour,size\nred,large\n")
        }
    }

    @Test("a port that is not one stops the import at the line it is on")
    func badPort() throws {
        let error = #expect(throws: PortableError.self) {
            try CSVHosts.read("name,port\nweb,22\ndb,http\n")
        }
        #expect(try #require(error).message.contains("line 3"))
    }

    @Test("a row with more values than there are columns is refused")
    func tooManyValues() {
        #expect(throws: PortableError.self) {
            try CSVHosts.read("name,port\nweb,22,extra\n")
        }
    }

    @Test("an empty file, and one with only a header, are both refused")
    func nothingThere() {
        #expect(throws: PortableError.self) { try CSVHosts.read("") }
        #expect(throws: PortableError.self) { try CSVHosts.read("name,address\n") }
    }
}

@Suite("Filing an import under a group")
nonisolated struct GroupedTests {
    private var document: Portable.Document {
        Portable.Document(
            groups: [Portable.Group(name: "Staging")],
            hosts: [
                Portable.Host(name: "loose", addr: "10.0.0.1"),
                Portable.Host(name: "filed", addr: "10.0.0.2", group: "Staging"),
            ])
    }

    private func filed(_ name: String, in plan: Portable.Plan) -> String? {
        guard let host = plan.hosts.first(where: { $0.name == name }) else { return nil }
        return plan.groups.first { $0.id == host.groupId }?.name ?? ""
    }

    @Test("a new host that names no group goes into the one asked for")
    func fillsIn() throws {
        let plan = try Portable.merge(document, into: Snapshot(), newHostsIn: "Imported")
        #expect(filed("loose", in: plan) == "Imported")
    }

    @Test("a host the file files stays where the file put it")
    func leavesFiledAlone() throws {
        let plan = try Portable.merge(document, into: Snapshot(), newHostsIn: "Imported")
        #expect(filed("filed", in: plan) == "Staging")
    }

    @Test("the group asked for is made, once, even when the file names it too")
    func makesTheGroup() throws {
        let plan = try Portable.merge(document, into: Snapshot(), newHostsIn: "Imported")
        #expect(plan.groups.map(\.name).sorted() == ["Imported", "Staging"])
        let same = try Portable.merge(document, into: Snapshot(), newHostsIn: "staging")
        #expect(same.groups.map(\.name) == ["Staging"])
        #expect(filed("loose", in: same) == "Staging")
    }

    @Test("no group asked for files nothing")
    func nothingAsked() throws {
        for blank in ["", "   "] {
            let plan = try Portable.merge(document, into: Snapshot(), newHostsIn: blank)
            #expect(plan.hosts.first { $0.name == "loose" }?.groupId == "")
            #expect(plan.groups.map(\.name) == ["Staging"])
        }
    }

    /// The bug: the group went to every loose host before the merge could
    /// tell new from old, so importing an ssh config a second time with a
    /// group typed moved hosts filed in Production into it. One already in
    /// the list stays put, and a group nothing new lands in is not made.
    @Test("a host already in the list stays where it was filed")
    func leavesTheListAlone() throws {
        let production = Shellhand.Group(id: "p", name: "Production")
        let web = Shellhand.Host(id: "w", name: "loose", addr: "10.0.0.1", groupId: "p")
        let plan = try Portable.merge(
            document, into: Snapshot(groups: [production], hosts: [web]), newHostsIn: "Imported")
        #expect(plan.hosts.first { $0.name == "loose" } == nil, "it was moved: \(plan.changes)")
        #expect(!plan.groups.map(\.name).contains("Imported"))
    }
}

/// The whole path a CSV takes: read, filed under a group, folded into what is
/// already there, written. Against a scratch store, never the real list.
@Suite("A CSV into the store")
nonisolated struct CSVRoundTripTests {
    private let sheet = """
        Label,Hostname,Port,Username,Folder,Tags,Password,Notes
        bastion,10.0.0.1,22,deploy,Production,edge,hunter2,the one by the window
        web-1,10.0.1.7,2222,deploy,Production,web;live,,
        loose,10.9.9.9,,root,,,,
        """

    private func scratch() throws -> Store {
        try Store(path: TestScratch.database())
    }

    @discardableResult
    private func bring(_ csv: String, group: String = "", into store: Store) throws -> MergeResult {
        let document = try CSVHosts.read(csv).document
        let plan = try Portable.merge(
            document, into: try store.snapshot(), newHostsIn: group)
        try store.apply(plan)
        return plan.result
    }

    @Test("the rows land as hosts, in the groups the file named")
    func lands() throws {
        let store = try scratch()
        try bring(sheet, into: store)
        let snapshot = try store.snapshot()
        #expect(snapshot.hosts.count == 3)
        let web = try #require(snapshot.hosts.first { $0.name == "web-1" })
        #expect(web.addr == "10.0.1.7")
        #expect(web.port == 2222)
        #expect(web.user == "deploy")
        #expect(web.tags.sorted() == ["live", "web"])
        let production = try #require(snapshot.groups.first { $0.name == "Production" })
        #expect(web.groupId == production.id)
    }

    @Test("a group asked for takes the rows the file left loose, and only those")
    func groupsTheLoose() throws {
        let store = try scratch()
        try bring(sheet, group: "Imported", into: store)
        let snapshot = try store.snapshot()
        let imported = try #require(snapshot.groups.first { $0.name == "Imported" })
        let production = try #require(snapshot.groups.first { $0.name == "Production" })
        #expect(snapshot.hosts.first { $0.name == "loose" }?.groupId == imported.id)
        #expect(snapshot.hosts.first { $0.name == "bastion" }?.groupId == production.id)
    }

    /// Against a store: the same sheet again with a group typed moves
    /// nothing already in it — loose stays loose, Production keeps its own —
    /// and only a row that is new goes into the group.
    @Test("a group asked for on a second import takes only what is new")
    func secondImportMovesNothing() throws {
        let store = try scratch()
        try bring(sheet, into: store)
        try bring(sheet + "\nnewcomer,10.9.9.10,,root,,,,", group: "Imported", into: store)
        let snapshot = try store.snapshot()
        let imported = try #require(snapshot.groups.first { $0.name == "Imported" })
        let production = try #require(snapshot.groups.first { $0.name == "Production" })
        #expect(snapshot.hosts.first { $0.name == "loose" }?.groupId == "")
        #expect(snapshot.hosts.first { $0.name == "bastion" }?.groupId == production.id)
        #expect(snapshot.hosts.first { $0.name == "newcomer" }?.groupId == imported.id)
    }

    @Test("the same file twice changes nothing the second time")
    func twiceIsOnce() throws {
        let store = try scratch()
        let first = try bring(sheet, into: store)
        #expect(first.added > 0)

        let again = try bring(sheet, into: store)
        #expect(again.added == 0)
        #expect(again.updated == 0)
        #expect(again.changes.isEmpty)
        #expect(try store.snapshot().hosts.count == 3)
    }

    @Test("a host keeps its id, so what hangs off it is not orphaned")
    func keepsItsID() throws {
        let store = try scratch()
        try bring(sheet, into: store)
        let before = try #require(try store.snapshot().hosts.first { $0.name == "bastion" })

        // The same machine, moved to a different port in the sheet.
        try bring(sheet.replacingOccurrences(of: "10.0.0.1,22,", with: "10.0.0.1,2200,"),
                  into: store)
        let after = try #require(try store.snapshot().hosts.first { $0.name == "bastion" })
        #expect(after.id == before.id)
        #expect(after.port == 2200)
    }
}
