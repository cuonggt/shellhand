import Foundation
import Yams

/// The host list as a file: what an export writes and an import reads.
///
/// Records name each other by name here rather than by id, because this file
/// is meant for a dotfiles repository and an id means nothing outside the
/// store that minted it. Nothing in it is a secret.
nonisolated enum Portable {
    struct Document: Sendable, Equatable {
        var version = 1
        /// The logins the file declares, which its hosts and groups name.
        var identities: [Identity] = []
        var groups: [Group] = []
        var hosts: [Host] = []
        /// What the file said that this app no longer keeps, in words an
        /// import can list — "credentials", "snippets", "startup snippets".
        /// Accepted and dropped rather than refused, for the reason the
        /// parser gives, and said rather than passed over in silence.
        var passedOver: [String] = []

        var isEmpty: Bool { groups.isEmpty && hosts.isEmpty && identities.isEmpty }
    }

    /// A login the file declares, named by the hosts and groups that use it.
    /// Nothing secret: a key is a path, as it is everywhere else here.
    struct Identity: Sendable, Equatable {
        var name = ""
        var user = ""
        var keyPath = ""
    }

    struct Group: Sendable, Equatable {
        var name = ""
        var parent = ""
        var user = ""
        var keyPath = ""
        /// The identity it points at, by name — `identity:` in a document at
        /// version 5 or later. Below that the word meant the key path, which
        /// is what `keyPath` above carries.
        var identity = ""
        var jump = ""
        var options: [String] = []
        var forwardAgent: Bool?
        var theme = ""
    }

    struct Host: Sendable, Equatable {
        var name = ""
        var addr = ""
        var port = 0
        var user = ""
        var keyPath = ""
        var identity = ""
        var jump = ""
        var group = ""
        var tags: [String] = []
        var options: [String] = []
        var forwardAgent: Bool?
        var theme = ""
        /// Whether the file carried forwarding rules for this host. The rules
        /// themselves are not kept — this app no longer forwards ports — but
        /// the key is accepted rather than refused, and what was passed over
        /// is said. See the parser for why.
        var hadForwards = false
    }

    // MARK: reading

    /// Reads a document, refusing anything it cannot account for.
    ///
    /// A key that is not a field is an error rather than something to skip
    /// past: a file whose `hosts` were spelled `host` would import nothing and
    /// say nothing, which is the one outcome worth ruling out.
    static func parse(_ raw: String) throws -> Document {
        let documents: [Any]
        do {
            documents = try YAMLDocuments.read(raw)
        } catch {
            throw PortableError("this is not valid YAML — \(error)")
        }
        guard documents.count <= 1 else {
            throw PortableError(
                "this is more than one YAML document — everything after the --- would be skipped")
        }
        guard let first = documents.first else { return Document() }
        guard let top = first as? [String: Any] else {
            throw PortableError("the top of this file should be version, groups and hosts")
        }
        try reject(
            unknown: top,
            allowed: ["version", "credentials", "groups", "hosts", "identities", "snippets"],
            in: "this file")

        var out = Document()
        /// What records named that this app no longer keeps. A set, because
        /// forty hosts naming a credential is still one thing to say.
        var dropped: Set<String> = []
        if let version = top["version"] {
            guard let n = version as? Int else { throw PortableError("version should be a number") }
            out.version = n
        }
        // Keys, credentials and snippets are gone, but every export written
        // before they were cut carries the sections. A file is refused whole
        // when it holds something unknown, so refusing these would make those
        // files unimportable over features that no longer exist — the rule
        // `forwards` already set. They are accepted, dropped, and listed in
        // `passedOver`.
        //
        // Dropping a credential can leave a host with no user, since that is
        // one of the two things a credential filled in, which is exactly why
        // an import says so rather than quietly importing a host that cannot
        // log in.
        if top["credentials"] != nil { out.passedOver.append("credentials") }
        if top["snippets"] != nil { out.passedOver.append("snippets") }

        // **What `identity` means depends on the version the file declares.**
        // From 5 it names one of the identities above and `key` carries the
        // key path; below 5 there were no identities, and `identity` *was*
        // the key path — which is what every file written before this means,
        // so that is what it goes on meaning. The version is read above, and
        // the fields a record may hold follow from it, so a file claiming 1
        // and carrying a `key` is refused with the usual list rather than
        // read two ways.
        let named = out.version >= identitiesFrom

        out.identities = try each(top["identities"], "identities") { fields in
            try reject(unknown: fields, allowed: ["name", "user", "key"], in: "an identity")
            return Identity(
                name: try text(fields, "name", required: true, in: "an identity"),
                user: try text(fields, "user", in: "an identity"),
                keyPath: try text(fields, "key", in: "an identity"))
        }
        if !out.identities.isEmpty, !named {
            throw PortableError(
                "this file says version \(out.version) and has identities, which came in at "
                    + "version \(identitiesFrom)")
        }

        out.groups = try each(top["groups"], "groups") { fields in
            try reject(unknown: fields,
                       allowed: Set(["name", "parent", "user", "identity", "jump", "credential",
                                 "options", "forward_agent", "theme", "startup"])
                           .union(named ? ["key"] : []),
                       in: "a group")
            if fields["credential"] != nil { dropped.insert("credentials") }
            if fields["startup"] != nil { dropped.insert("startup snippets") }
            return Group(
                name: try text(fields, "name", required: true, in: "a group"),
                parent: try text(fields, "parent", in: "a group"),
                user: try text(fields, "user", in: "a group"),
                keyPath: try text(fields, named ? "key" : "identity", in: "a group"),
                identity: named ? try text(fields, "identity", in: "a group") : "",
                jump: try text(fields, "jump", in: "a group"),
                options: try strings(fields, "options", in: "a group"),
                forwardAgent: try flag(fields, "forward_agent", in: "a group"),
                theme: try text(fields, "theme", in: "a group"))
        }
        out.hosts = try each(top["hosts"], "hosts") { fields in
            try reject(unknown: fields,
                       allowed: Set(["name", "addr", "port", "user", "identity", "jump", "group",
                                 "credential", "tags", "options", "forward_agent", "theme",
                                 "startup", "forwards"])
                           .union(named ? ["key"] : []),
                       in: "a host")
            if fields["credential"] != nil { dropped.insert("credentials") }
            if fields["startup"] != nil { dropped.insert("startup snippets") }
            var host = Host(
                name: try text(fields, "name", required: true, in: "a host"),
                addr: try text(fields, "addr", in: "a host"),
                port: try number(fields, "port", in: "a host"),
                user: try text(fields, "user", in: "a host"),
                keyPath: try text(fields, named ? "key" : "identity", in: "a host"),
                identity: named ? try text(fields, "identity", in: "a host") : "",
                jump: try text(fields, "jump", in: "a host"),
                group: try text(fields, "group", in: "a host"))
            if let tags = fields["tags"] {
                guard let list = tags as? [Any] else {
                    throw PortableError("the tags of host \"\(host.name)\" should be a list")
                }
                host.tags = try list.map {
                    guard let tag = $0 as? String else {
                        throw PortableError("every tag of host \"\(host.name)\" should be text")
                    }
                    return tag
                }
            }
            host.options = try strings(fields, "options", in: "a host")
            host.forwardAgent = try flag(fields, "forward_agent", in: "a host")
            host.theme = try text(fields, "theme", in: "a host")
            // Accepted, dropped and reported, for the reason above.
            host.hadForwards = fields["forwards"] != nil
            return host
        }
        // Whatever any record named, after the sections, each said once.
        for what in ["credentials", "startup snippets"] where dropped.contains(what) {
            if !out.passedOver.contains(what) { out.passedOver.append(what) }
        }
        try out.validate()
        return out
    }

    // MARK: writing

    /// The store as a file, in the order the document declares things:
    /// identities, then groups, then hosts, so a name is declared above every
    /// record that uses it.
    ///
    /// **The key path is written as `key` only where the file says version 5
    /// or later**, since below that the word for it is `identity`. A list
    /// with no identities is still written as a 1 or a 4, so it imports into
    /// a copy of this app that has never heard of them.
    static func export(
        groups: [Shellhand.Group], hosts: [Shellhand.Host],
        identities: [Shellhand.Identity] = []
    ) throws -> String {
        let groupByID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let identityByID = Dictionary(
            identities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sorted = { (a: String, b: String) in a.lowercased() < b.lowercased() }
        let groups = groups.sorted { sorted($0.name, $1.name) }
        let hosts = hosts.sorted { sorted($0.name, $1.name) }
        // Only the ones something points at, and only where there are any:
        // an identity nothing uses is still worth carrying, since it is a
        // record somebody made, so this is every one of them.
        let identities = identities.sorted { sorted($0.name, $1.name) }

        let number = version(
            settings: hosts.contains { !$0.sshOptions.isEmpty || $0.forwardAgent != nil }
                || groups.contains { !$0.sshOptions.isEmpty || $0.forwardAgent != nil },
            identities: !identities.isEmpty)
        let named = number >= identitiesFrom
        /// What this file calls a key path.
        let keyField = named ? "key" : "identity"

        var top: [(String, Node)] = [("version", Node(String(number), Tag(.int)))]

        if !identities.isEmpty {
            top.append(("identities", sequence(identities.map { identity in
                var fields: [(String, Node)] = [("name", Node(identity.name))]
                if !identity.user.isEmpty { fields.append(("user", Node(identity.user))) }
                if !identity.keyPath.isEmpty { fields.append(("key", Node(identity.keyPath))) }
                return mapping(fields)
            })))
        }
        if !groups.isEmpty {
            top.append(("groups", sequence(groups.map { group in
                var fields: [(String, Node)] = [("name", Node(group.name))]
                if let parent = groupByID[group.parentId] {
                    fields.append(("parent", Node(parent.name)))
                }
                if !group.user.isEmpty { fields.append(("user", Node(group.user))) }
                if named, let identity = identityByID[group.identityId] {
                    fields.append(("identity", Node(identity.name)))
                }
                if !group.keyPath.isEmpty { fields.append((keyField, Node(group.keyPath))) }
                if !group.proxyJump.isEmpty { fields.append(("jump", Node(group.proxyJump))) }
                fields += written(group.sshOptions, group.forwardAgent, group.theme)
                return mapping(fields)
            })))
        }
        if !hosts.isEmpty {
            top.append(("hosts", sequence(hosts.map { host in
                var fields: [(String, Node)] = [
                    ("name", Node(host.name)), ("addr", Node(host.addr)),
                ]
                if host.port != 0 { fields.append(("port", Node(String(host.port), Tag(.int)))) }
                if !host.user.isEmpty { fields.append(("user", Node(host.user))) }
                if named, let identity = identityByID[host.identityId] {
                    fields.append(("identity", Node(identity.name)))
                }
                if !host.keyPath.isEmpty { fields.append((keyField, Node(host.keyPath))) }
                if !host.proxyJump.isEmpty { fields.append(("jump", Node(host.proxyJump))) }
                if let group = groupByID[host.groupId] {
                    fields.append(("group", Node(group.name)))
                }
                if !host.tags.isEmpty {
                    // Flow style: a list of short words reads better on one
                    // line than as five bullets.
                    fields.append(("tags", Node.sequence(
                        Node.Sequence(host.tags.map { Node($0) }, Tag(.seq), .flow))))
                }
                fields += written(host.sshOptions, host.forwardAgent, host.theme)
                return mapping(fields)
            })))
        }
        let header = """
            # Shellhand host list. Fold it into another machine with File ▸ Import.
            # Records match by name, so ids differing between machines does not matter.
            # No secrets here: a key is a path to one, never the key itself.

            """
        return header + (try Yams.serialize(node: mapping(top)))
    }

    /// The `-o` settings, the agent flag and the palette, where there are any
    /// to write.
    private static func written(
        _ options: [String], _ forwardAgent: Bool?, _ theme: String
    ) -> [(String, Node)] {
        var out: [(String, Node)] = []
        if !options.isEmpty {
            out.append(("options", sequence(options.map { Node($0) })))
        }
        if let forwardAgent {
            out.append(("forward_agent", Node(forwardAgent ? "true" : "false", Tag(.bool))))
        }
        if !theme.isEmpty { out.append(("theme", Node(theme))) }
        return out
    }

    /// The version the identities section came in at, and with it the change
    /// of meaning: from here on `identity` on a host or a group names an
    /// identity and `key` carries the key path, where below it `identity`
    /// *was* the key path.
    ///
    /// This number is as permanent as the files written under it. Changing it
    /// would reinterpret every list anyone has exported.
    static let identitiesFrom = 5

    /// What a reader has to understand to read this file.
    ///
    /// 2 and 3 were the credential and snippet sections, which this app no
    /// longer writes. The numbers are not reused: a file announcing 3 means
    /// those sections wherever it came from, and the sections are still read.
    ///
    /// A list with no identities is still a 1 or a 4, so nothing that could
    /// read it before stops being able to.
    static func version(settings: Bool = false, identities: Bool = false) -> Int {
        if identities { return identitiesFrom }
        return settings ? 4 : 1
    }

    // MARK: reading helpers

    private static func each<T>(
        _ value: Any?, _ what: String, _ build: ([String: Any]) throws -> T
    ) throws -> [T] {
        guard let value else { return [] }
        guard let list = value as? [Any] else {
            throw PortableError("\(what) should be a list")
        }
        return try list.map { item in
            guard let fields = item as? [String: Any] else {
                throw PortableError("every entry under \(what) should have named fields")
            }
            return try build(fields)
        }
    }

    private static func reject(
        unknown fields: [String: Any], allowed: Set<String>, in what: String
    ) throws {
        for key in fields.keys.sorted() where !allowed.contains(key) {
            throw PortableError(
                "\(what) has a \(key), which is not a field — they are "
                    + allowed.sorted().joined(separator: ", "))
        }
    }

    private static func text(
        _ fields: [String: Any], _ key: String, required: Bool = false, in what: String
    ) throws -> String {
        guard let value = fields[key] else {
            if required { throw PortableError("\(what) has no \(key)") }
            return ""
        }
        // A script written as a number or a date is still a script.
        if let string = value as? String { return string }
        if let number = value as? Int { return String(number) }
        throw PortableError("the \(key) of \(what) should be text")
    }

    private static func strings(
        _ fields: [String: Any], _ key: String, in what: String
    ) throws -> [String] {
        guard let value = fields[key] else { return [] }
        guard let list = value as? [Any] else {
            throw PortableError("the \(key) of \(what) should be a list")
        }
        return try list.map {
            guard let text = $0 as? String else {
                throw PortableError("every one of the \(key) of \(what) should be text")
            }
            return text
        }
    }

    private static func flag(
        _ fields: [String: Any], _ key: String, in what: String
    ) throws -> Bool? {
        guard let value = fields[key] else { return nil }
        guard let flag = value as? Bool else {
            throw PortableError("the \(key) of \(what) should be true or false")
        }
        return flag
    }

    private static func number(_ fields: [String: Any], _ key: String, in what: String) throws -> Int {
        guard let value = fields[key] else { return 0 }
        guard let number = value as? Int else {
            throw PortableError("the \(key) of \(what) should be a number")
        }
        return number
    }

    private static func sequence(_ nodes: [Node]) -> Node {
        Node.sequence(Node.Sequence(nodes, Tag(.seq), .block))
    }

    private static func mapping(_ pairs: [(String, Node)]) -> Node {
        Node.mapping(Node.Mapping(pairs.map { (Node($0.0), $0.1) }, Tag(.map), .block))
    }
}

extension Portable.Document {
    /// What has to hold before a document is worth merging: a name on every
    /// record, no two records of a kind sharing one, and an address on every
    /// host.
    nonisolated func validate() throws {
        guard (1...Portable.identitiesFrom).contains(version) else {
            throw PortableError(
                "this file says version \(version); this reads up to version "
                    + "\(Portable.identitiesFrom)")
        }
        try unique(groups.map(\.name), "group")
        try unique(hosts.map(\.name), "host")
        try unique(identities.map(\.name), "identity")
        for host in hosts where host.addr.trimmingCharacters(in: .whitespaces).isEmpty {
            throw PortableError("host \"\(host.name)\" has no addr")
        }
    }

    nonisolated private func unique(_ names: [String], _ kind: String) throws {
        var seen: Set<String> = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { throw PortableError("a \(kind) has no name") }
            let key = trimmed.lowercased()
            if seen.contains(key) {
                throw PortableError("there are two \(kind)s called \"\(trimmed)\"")
            }
            seen.insert(key)
        }
    }
}

nonisolated struct PortableError: LocalizedError, Sendable, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
