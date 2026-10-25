import Foundation
import GRDB

/// Shellhand's own host list, in SQLite.
///
/// SQLite rather than a file this app encodes itself, because the list is
/// relational — hosts sit in groups, groups sit in groups — and because
/// deleting a group has to re-parent what was under it in the same breath
/// that removes it.
///
/// One connection is held open for the life of the process, which is what
/// makes a snapshot of a few hundred hosts a millisecond or two. Nothing
/// outside this app writes the file, so there is nobody to share it with.
nonisolated final class Store: Sendable {
    let path: String
    private let db: DatabaseQueue

    init(path: String) throws {
        self.path = path
        let folder = (path as NSString).deletingLastPathComponent
        if !folder.isEmpty {
            try FileManager.default.createDirectory(
                atPath: folder, withIntermediateDirectories: true)
        }
        var configuration = Configuration()
        configuration.foreignKeysEnabled = false
        db = try DatabaseQueue(path: path, configuration: configuration)
        try Store.migrator.migrate(db)
    }

    /// Where the list lives when nothing says otherwise.
    static var defaultPath: String {
        NSString(string: "~/Library/Application Support/Shellhand/shellhand.sqlite")
            .expandingTildeInPath
    }

    // MARK: the schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // `groups` is a keyword in SQLite's window-function grammar, so the
        // table is host_groups and the type is still Group.
        migrator.registerMigration("v1") { db in
            try db.create(table: "host_groups") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().defaults(to: "")
                t.column("parentId", .text).notNull().defaults(to: "")
                t.column("user", .text).notNull().defaults(to: "")
                t.column("identity", .text).notNull().defaults(to: "")
                t.column("proxyJump", .text).notNull().defaults(to: "")
                t.column("credentialId", .text).notNull().defaults(to: "")
            }
            try db.create(table: "hosts") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().defaults(to: "")
                t.column("addr", .text).notNull().defaults(to: "")
                t.column("port", .integer).notNull().defaults(to: 0)
                t.column("user", .text).notNull().defaults(to: "")
                t.column("identity", .text).notNull().defaults(to: "")
                t.column("proxyJump", .text).notNull().defaults(to: "")
                t.column("groupId", .text).notNull().defaults(to: "")
                t.column("credentialId", .text).notNull().defaults(to: "")
                // A JSON array. Tags are read with the host and never queried
                // on their own, so a table of their own would buy nothing.
                t.column("tags", .text).notNull().defaults(to: "[]")
            }
            try db.create(indexOn: "hosts", columns: ["groupId"])
            try db.create(table: "credentials") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().defaults(to: "")
                t.column("kind", .text).notNull().defaults(to: "key")
                t.column("user", .text).notNull().defaults(to: "")
                t.column("identity", .text).notNull().defaults(to: "")
            }
            try db.create(table: "snippets") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().defaults(to: "")
                t.column("script", .text).notNull().defaults(to: "")
            }
            try db.create(table: "forwards") { t in
                t.primaryKey("id", .text)
                t.column("hostId", .text).notNull().defaults(to: "")
                t.column("kind", .text).notNull().defaults(to: "local")
                t.column("listen", .text).notNull().defaults(to: "")
                t.column("listenPort", .integer).notNull().defaults(to: 0)
                t.column("dest", .text).notNull().defaults(to: "")
                t.column("destPort", .integer).notNull().defaults(to: 0)
            }
            try db.create(indexOn: "forwards", columns: ["hostId"])
        }
        // Settings a host or a group carries to ssh itself, rather than only
        // the ones the config gives every connection.
        migrator.registerMigration("v2") { db in
            for table in ["host_groups", "hosts"] {
                try db.alter(table: table) { t in
                    t.add(column: "sshOptions", .text).notNull().defaults(to: "[]")
                    // Null means "ask the group above".
                    t.add(column: "forwardAgent", .boolean)
                }
            }
        }
        // A palette, inherited like everything else a group hands down, so a
        // production machine can be told from a staging one before anything is
        // typed into it.
        migrator.registerMigration("v3") { db in
            for table in ["host_groups", "hosts"] {
                try db.alter(table: table) { t in
                    // Empty means "ask the group above"; a name nothing
                    // answers to falls back rather than blanking the terminal.
                    t.add(column: "theme", .text).notNull().defaults(to: "")
                }
            }
        }
        // A snippet, by name, run on connecting — inherited like the rest.
        migrator.registerMigration("v4") { db in
            for table in ["host_groups", "hosts"] {
                try db.alter(table: table) { t in
                    t.add(column: "startup", .text).notNull().defaults(to: "")
                }
            }
        }
        // The hosts a snippet is usually run on, so they do not have to be
        // picked out of the list every time.
        migrator.registerMigration("v5") { db in
            try db.alter(table: "snippets") { t in
                t.add(column: "targets", .text).notNull().defaults(to: "[]")
            }
        }
        // Port forwarding is gone. v1 is left as it was rather than edited:
        // migrations are append-only, and every store in existence has
        // already run it — rewriting history would leave those stores with a
        // table the migrator thinks it never made.
        migrator.registerMigration("v6") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS forwards")
        }
        // Keys, credentials and snippets are gone, and the two tables and the
        // four columns go with them. Like v6 this is a migration of its own
        // rather than an edit to v1 and v4, which every store in existence
        // has already run. The columns are looked up before they are dropped:
        // an `ALTER TABLE … DROP COLUMN` for one that is not there throws, and
        // a store that cannot be opened is the whole host list lost.
        migrator.registerMigration("v7") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS credentials")
            try db.execute(sql: "DROP TABLE IF EXISTS snippets")
            for table in ["host_groups", "hosts"] {
                let held = try String.fetchAll(
                    db, sql: "SELECT name FROM pragma_table_info(?)", arguments: [table])
                for column in ["credentialId", "startup"] where held.contains(column) {
                    try db.alter(table: table) { t in t.drop(column: column) }
                }
            }
        }
        return migrator
    }

    // MARK: reading

    /// The whole list in one go, which is how the window reads it: a few
    /// hundred hosts is nothing to SQLite, and a window that asked per row
    /// would ask a few hundred times.
    func snapshot() throws -> Snapshot {
        try db.read { db in
            Snapshot(
                groups: try Group.fetchAll(db),
                hosts: try Host.fetchAll(db))
        }
    }


    func host(_ id: String) throws -> Host? {
        try db.read { db in
            try Host.fetchOne(db, sql: "SELECT * FROM hosts WHERE id = ?", arguments: [id])
        }
    }

    // MARK: writing

    /// Saves a host, giving it an id if it arrived without one, and hands back
    /// what was written rather than what was asked for — the caller wants the
    /// id, and a trimmed name is the store's business.
    @discardableResult
    func save(_ host: Host) throws -> Host {
        var out = host
        out.id = out.id.isEmpty ? Store.newID() : out.id
        out.name = out.name.trimmingCharacters(in: .whitespaces)
        try db.write { db in try out.upsert(db) }
        return out
    }

    @discardableResult
    func save(_ group: Group) throws -> Group {
        var out = group
        out.id = out.id.isEmpty ? Store.newID() : out.id
        out.name = out.name.trimmingCharacters(in: .whitespaces)
        // A group that is its own parent would make the sidebar walk forever.
        if out.parentId == out.id { out.parentId = "" }
        try db.write { db in try out.upsert(db) }
        return out
    }

    func deleteHost(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM hosts WHERE id = ?", arguments: [id])
        }
    }

    /// Deleting a group hands what was under it to the group above, rather
    /// than deleting hosts somebody meant to keep or leaving them pointing at
    /// a group that is gone. One transaction, so what is re-parented is
    /// decided from the state it is written into.
    func deleteGroup(id: String) throws {
        try db.write { db in
            let parent = try String.fetchOne(
                db, sql: "SELECT parentId FROM host_groups WHERE id = ?", arguments: [id]) ?? ""
            try db.execute(
                sql: "UPDATE host_groups SET parentId = ? WHERE parentId = ?",
                arguments: [parent, id])
            try db.execute(
                sql: "UPDATE hosts SET groupId = ? WHERE groupId = ?", arguments: [parent, id])
            try db.execute(sql: "DELETE FROM host_groups WHERE id = ?", arguments: [id])
        }
    }

    /// Everything at once, for an import: one transaction, so a file that
    /// fails half way through leaves the list as it was.
    func replaceAll(groups: [Group], hosts: [Host]) throws {
        try db.write { db in
            for table in ["host_groups", "hosts"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            for g in groups { try g.upsert(db) }
            for h in hosts { try h.upsert(db) }
        }
    }

    /// Writes everything an import planned, in one transaction: a document
    /// that fails half way through leaves the list as it was. The records
    /// arrive with their ids already decided, which is what lets the dry run
    /// be exactly this.
    func apply(_ plan: Portable.Plan) throws {
        try db.write { db in
            for group in plan.groups { try group.upsert(db) }
            for host in plan.hosts { try host.upsert(db) }
        }
    }

    /// Short and random. Ids never leave this app — an export names hosts by
    /// name — so they only have to be unique here.
    static func newID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
    }
}

// MARK: - the records
//
// Mapped by hand rather than by Codable: `Host.effective` is worked out by the
// resolver and belongs to no column, and `tags` is JSON in one.

extension Group: FetchableRecord, PersistableRecord {
    nonisolated static var databaseTableName: String { "host_groups" }

    nonisolated init(row: Row) {
        self.init()
        id = row["id"]
        name = row["name"]
        parentId = row["parentId"]
        user = row["user"]
        identity = row["identity"]
        proxyJump = row["proxyJump"]
        sshOptions = Host.decodeTags(row["sshOptions"])
        forwardAgent = row["forwardAgent"]
        theme = row["theme"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["parentId"] = parentId
        container["user"] = user
        container["identity"] = identity
        container["proxyJump"] = proxyJump
        container["sshOptions"] = Host.encodeTags(sshOptions)
        container["forwardAgent"] = forwardAgent
        container["theme"] = theme
    }
}

extension Host: FetchableRecord, PersistableRecord {
    nonisolated static var databaseTableName: String { "hosts" }

    nonisolated init(row: Row) {
        self.init()
        id = row["id"]
        name = row["name"]
        addr = row["addr"]
        port = row["port"]
        user = row["user"]
        identity = row["identity"]
        proxyJump = row["proxyJump"]
        groupId = row["groupId"]
        tags = Host.decodeTags(row["tags"])
        sshOptions = Host.decodeTags(row["sshOptions"])
        forwardAgent = row["forwardAgent"]
        theme = row["theme"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["addr"] = addr
        container["port"] = port
        container["user"] = user
        container["identity"] = identity
        container["proxyJump"] = proxyJump
        container["groupId"] = groupId
        container["tags"] = Host.encodeTags(tags)
        container["sshOptions"] = Host.encodeTags(sshOptions)
        container["forwardAgent"] = forwardAgent
        container["theme"] = theme
    }

    /// A tag list that cannot be read is no tags, not a host that fails to
    /// load: the rest of the row is still worth having.
    nonisolated static func decodeTags(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return tags
    }

    nonisolated static func encodeTags(_ tags: [String]) -> String {
        guard let data = try? JSONEncoder().encode(tags),
              let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }
}
