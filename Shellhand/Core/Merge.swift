import Foundation

nonisolated extension Portable {
    /// Everything an import would do: the records to write, with ids already
    /// assigned, and a line for each.
    ///
    /// Worked out separately from applying it, which is what makes a dry run
    /// exactly the real thing rather than a second implementation that
    /// predicts it.
    nonisolated struct Plan: Sendable {
        var groups: [Shellhand.Group] = []
        var hosts: [Shellhand.Host] = []
        var changes: [Change] = []
        var unchanged = 0
        /// Sections and fields the file carried that this app no longer
        /// keeps, said once each.
        var passedOver: [String] = []

        var isEmpty: Bool { changes.isEmpty }

        var result: MergeResult {
            MergeResult(
                changes: changes,
                added: changes.count { $0.action == "add" },
                updated: changes.count { $0.action == "update" },
                unchanged: unchanged,
                passedOver: passedOver)
        }

        fileprivate mutating func note(_ kind: String, _ name: String, _ action: String) {
            changes.append(Change(kind: kind, name: name, action: action))
        }
    }

    /// Folds a document into what the store already holds.
    ///
    /// A record already present keeps its id, so importing does not orphan
    /// what hangs off it — the host you have connected to forty times is still
    /// that host afterwards.
    ///
    /// A field the document leaves empty keeps the value already in the store.
    /// Import fills in and corrects; it does not blank things. That is what
    /// lets an ssh config be imported twice without the second pass wiping a
    /// user or a tag added here in between, and the cost is that a field
    /// cannot be cleared by importing — which the editor does instead.
    ///
    /// `newHostsIn` is the group typed into the import sheet, for the hosts
    /// this import adds and the file leaves loose: thirty machines out of an
    /// ssh config land in one place rather than at the top of the list. A
    /// host **already in the list stays where it was filed**, and one the
    /// file files itself goes where the file says. The group was given to
    /// every loose host before the merge could tell new from old, so
    /// importing an ssh config again with a group typed moved hosts filed
    /// in Production into it, the sheet saying "Put new hosts in" all along.
    static func merge(
        _ document: Document, into snapshot: Snapshot, newHostsIn: String = ""
    ) throws -> Plan {
        try document.validate()
        var plan = Plan()

        // What the file carried that this app no longer keeps. Carried
        // through rather than noted as a change: nothing is written for it.
        plan.passedOver = document.passedOver

        // Every group the document names gets an id up front, so a parent
        // still resolves when the document lists the child first.
        var groupsByName: [String: Shellhand.Group] = [:]
        for group in snapshot.groups { groupsByName[key(group.name)] = group }
        var fresh: Set<String> = []
        func ensure(_ name: String) -> Shellhand.Group {
            let k = key(name)
            if let group = groupsByName[k] { return group }
            var group = Shellhand.Group()
            group.id = Store.newID()
            group.name = name
            groupsByName[k] = group
            fresh.insert(k)
            return group
        }
        // Which groups the report has already spoken for, so one declared once
        // and named by ten hosts is counted once.
        var accounted: Set<String> = []
        for group in document.groups {
            _ = ensure(group.name)
            accounted.insert(key(group.name))
        }
        for input in document.groups {
            let k = key(input.name)
            let was = groupsByName[k] ?? Shellhand.Group()
            var now = was
            now.user = pick(input.user, was.user)
            now.identity = pick(input.identity, was.identity)
            now.proxyJump = pick(input.jump, was.proxyJump)
            now.sshOptions = input.options.isEmpty ? was.sshOptions : input.options
            now.forwardAgent = input.forwardAgent ?? was.forwardAgent
            now.theme = pick(input.theme, was.theme)
            if !input.parent.isEmpty {
                guard let parent = groupsByName[key(input.parent)] else {
                    throw PortableError(
                        "group \"\(input.name)\" names parent \"\(input.parent)\", which is "
                            + "neither in this document nor already here")
                }
                now.parentId = parent.id
            }
            groupsByName[k] = now
            if fresh.contains(k) {
                plan.groups.append(now)
                plan.note("group", now.name, "add")
            } else if now != was {
                plan.groups.append(now)
                plan.note("group", now.name, "update")
            } else {
                plan.unchanged += 1
            }
        }

        var hostsByName: [String: Shellhand.Host] = [:]
        for host in snapshot.hosts { hostsByName[key(host.name)] = host }
        for input in document.hosts {
            let k = key(input.name)
            let was = hostsByName[k]
            var now = was ?? Shellhand.Host()
            now.name = input.name
            now.addr = pick(input.addr, was?.addr ?? "")
            now.port = input.port != 0 ? input.port : (was?.port ?? 0)
            now.user = pick(input.user, was?.user ?? "")
            now.identity = pick(input.identity, was?.identity ?? "")
            now.proxyJump = pick(input.jump, was?.proxyJump ?? "")
            if !input.tags.isEmpty { now.tags = input.tags }
            if !input.options.isEmpty { now.sshOptions = input.options }
            now.forwardAgent = input.forwardAgent ?? was?.forwardAgent
            now.theme = pick(input.theme, was?.theme ?? "")
            // Where the file files it, or — a new host it leaves loose — the
            // group the import was given. A host naming a group nothing has
            // heard of creates it, exactly as typing an unknown group into
            // the host form does.
            let filing = !input.group.isEmpty ? input.group
                : was == nil ? newHostsIn.trimmingCharacters(in: .whitespaces) : ""
            if !filing.isEmpty {
                let group = ensure(filing)
                now.groupId = group.id
                let gk = key(filing)
                if !accounted.contains(gk) {
                    accounted.insert(gk)
                    if fresh.contains(gk) {
                        plan.groups.append(group)
                        plan.note("group", group.name, "add")
                    } else {
                        plan.unchanged += 1
                    }
                }
            }
            if was == nil {
                now.id = Store.newID()
                plan.hosts.append(now)
                plan.note("host", now.name, "add")
            } else if !same(now, was!) {
                plan.hosts.append(now)
                plan.note("host", now.name, "update")
            } else {
                plan.unchanged += 1
            }
            // Said rather than dropped in silence, the way a CSV reports a
            // column it could make nothing of.
            if input.hadForwards {
                plan.note("host", now.name, "forwarding rules passed over")
            }
            hostsByName[k] = now
        }

        // The store checks for cycles against what it holds, which cannot see
        // groups this plan has not written yet, so the document's own tree is
        // checked here rather than failing halfway through applying it.
        try acyclic(groupsByName)
        return plan
    }

    static func key(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// What the document says, or what the store already had.
    private static func pick(_ fromDocument: String, _ existing: String) -> String {
        fromDocument.isEmpty ? existing : fromDocument
    }

    private static func same(_ a: Shellhand.Host, _ b: Shellhand.Host) -> Bool {
        a.id == b.id && a.name == b.name && a.addr == b.addr && a.port == b.port
            && a.user == b.user && a.identity == b.identity && a.proxyJump == b.proxyJump
            && a.groupId == b.groupId && a.tags == b.tags
            && a.sshOptions == b.sshOptions && a.forwardAgent == b.forwardAgent
            && a.theme == b.theme
    }

    private static func acyclic(_ byName: [String: Shellhand.Group]) throws {
        var byID: [String: Shellhand.Group] = [:]
        for group in byName.values { byID[group.id] = group }
        for group in byName.values {
            var seen: Set<String> = [group.id]
            var parent = group.parentId
            while !parent.isEmpty {
                if seen.contains(parent) {
                    throw PortableError("group \"\(group.name)\" is its own ancestor")
                }
                seen.insert(parent)
                parent = byID[parent]?.parentId ?? ""
            }
        }
    }
}
