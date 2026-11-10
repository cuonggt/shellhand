import Foundation

/// What stops a record being saved, in words a form can show.
///
/// Here rather than in the sheet that shows it, because these are rules about
/// the data and not about the dialog: a name that two hosts share breaks the
/// export, the import and the jump host field whoever typed it.
nonisolated enum Validation {
    /// The sentence every deletion question ends on, its spaces ones a line
    /// is not broken at, so it stands whole: "Delete EU?" broke before its
    /// last word and left "undone." alone on a line.
    static let cannotBeUndone = "This\u{00A0}cannot\u{00A0}be\u{00A0}undone."

    /// `others` is the rest of the list — the host being edited is skipped by
    /// its own id, so saving it under the name it already has is not a clash
    /// with itself.
    static func problem(with host: Host, among others: [Host]) -> String? {
        let name = host.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "A host needs a name." }
        if host.addr.trimmingCharacters(in: .whitespaces).isEmpty {
            return "A host needs an address."
        }
        // Nought is not a port: it is this app's way of saying "whatever ssh
        // does", which is 22.
        if host.port != 0, !(1...65535).contains(host.port) {
            return "A port is between 1 and 65535."
        }
        if others.contains(where: {
            $0.id != host.id && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return "There is already a host called \(name)."
        }
        // A host that jumps through itself would be its own bastion, which is
        // a loop the resolver stops at rather than a route.
        if !host.proxyJump.isEmpty,
           host.proxyJump.caseInsensitiveCompare(name) == .orderedSame {
            return "A host cannot be its own jump host."
        }
        return problem(withOptions: host.sshOptions)
    }

    /// An `-o` setting ssh would refuse is refused here, where it can be
    /// read, rather than on every connection afterwards.
    static func problem(withOptions options: [String]) -> String? {
        for option in options {
            if let said = SSHArgs.optionProblem(option) {
                return "The option \(option.debugDescription) \(said)."
            }
        }
        return nil
    }

    /// What deleting a host takes with it besides itself: the hosts and
    /// groups that reach their machines through it. Their jump field names
    /// it, and once it is gone ssh is handed that name to make sense of on
    /// its own — which the warning, "This cannot be undone.", never said.
    static func deletionWarning(
        for host: Host, hosts: [Host] = [], groups: [Group] = []
    ) -> String {
        let name = host.name.trimmingCharacters(in: .whitespaces)
        guard let through = goingThrough(host, named: name, hosts: hosts, groups: groups)
        else { return cannotBeUndone }
        return "\(name) is the jump host for \(through.who). Without it, ssh "
            + "is left to find a machine called \(name) by itself. \(cannotBeUndone)"
    }

    /// What renaming a host takes with it: every other host's and group's
    /// jump field that names it, rewritten to the new name, so what went
    /// through it still does. Up to 0.1.3 nothing did, and a rename broke
    /// them without a word. Only the records that change come back, as
    /// `Tags.renaming` hands back only the hosts a tag is on.
    ///
    /// Nothing follows while another host still answers to the old name: a
    /// field naming it still reaches a machine, and rewriting it could send
    /// it through this one instead. Saving refuses a name another host has,
    /// so only a list from before that rule can be in that state.
    static func renaming(
        _ host: Host, from old: String, hosts: [Host], groups: [Group]
    ) -> (hosts: [Host], groups: [Group]) {
        let new = host.name.trimmingCharacters(in: .whitespaces)
        let was = old.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, !was.isEmpty, new != was,
            !hosts.contains(where: { $0.id != host.id && names($0.name, was) })
        else { return ([], []) }
        let movedHosts = hosts.compactMap { other -> Host? in
            guard other.id != host.id, names(other.proxyJump, was), other.proxyJump != new
            else { return nil }
            var moved = other
            moved.proxyJump = new
            return moved
        }
        let movedGroups = groups.compactMap { group -> Group? in
            guard names(group.proxyJump, was), group.proxyJump != new else { return nil }
            var moved = group
            moved.proxyJump = new
            return moved
        }
        return (movedHosts, movedGroups)
    }

    /// What the host editor says while a name is changed and something goes
    /// through the host by it: before Save, rather than leaving the jump
    /// fields to be found changed. Nil when nothing would follow.
    static func renameNote(
        for host: Host, from old: String, hosts: [Host], groups: [Group]
    ) -> String? {
        let was = old.trimmingCharacters(in: .whitespaces)
        let following = renaming(host, from: was, hosts: hosts, groups: groups)
        guard !following.hosts.isEmpty || !following.groups.isEmpty,
            let through = goingThrough(host, named: was, hosts: hosts, groups: groups)
        else { return nil }
        let who = through.who.prefix(1).uppercased() + through.who.dropFirst()
        return through.count == 1
            ? "\(who) goes through \(was), and will follow the new name."
            : "\(who) go through \(was), and will follow the new name."
    }

    /// Whether a jump field names a host, as the resolver reads one: trimmed,
    /// and without regard to case.
    private static func names(_ field: String, _ name: String) -> Bool {
        !name.isEmpty
            && field.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame
    }

    /// The hosts and groups that go through a host by this name, said the way
    /// a person counts them — "6 hosts and the groups EU and US" — and how
    /// many that is. Nil when nothing does.
    ///
    /// A host is counted by what reaches it, `effective`, as well as by its
    /// own field: "the jump host for 2 groups" said nothing of the six hosts
    /// in them. The groups are named, since that is where it would be
    /// changed.
    private static func goingThrough(
        _ host: Host, named name: String, hosts: [Host], groups: [Group]
    ) -> (who: String, count: Int)? {
        let jumping = hosts.filter {
            $0.id != host.id && (names($0.proxyJump, name) || names($0.effective.proxyJump, name))
        }.count
        let groupsJumping = groups.filter { names($0.proxyJump, name) }.map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var who: [String] = []
        if jumping > 0 { who.append(jumping == 1 ? "1 host" : "\(jumping) hosts") }
        switch groupsJumping.count {
        case 0: break
        case 1: who.append("the group \(groupsJumping[0])")
        case 2...3:
            who.append("the groups \(groupsJumping.dropLast().joined(separator: ", ")) and \(groupsJumping.last!)")
        default: who.append("\(groupsJumping.count) groups")
        }
        guard !who.isEmpty else { return nil }
        return (who.joined(separator: " and "), jumping + groupsJumping.count)
    }

    /// Deleting a group keeps what was under it, which is the part worth
    /// saying: nothing is lost but the group, and what it gives the hosts
    /// beneath it.
    ///
    /// **What moves is what the store moves** (`Store.deleteGroup`): the
    /// hosts filed in it, and the groups inside it, which take their own
    /// hosts along. It said "Its 7 hosts move to the top of the list" of a
    /// group holding one, the other six staying in EU and US — and nothing
    /// of the user, the key and the palette it gave all seven, which reach
    /// none of them afterwards.
    ///
    /// **Where they land is named as the sidebar and the editors name it**:
    /// the group above, or with none, Ungrouped for the hosts and "a group
    /// of its own", as the group editor's Inside says, for the groups. "The
    /// top of the list" named both, and the hosts land at its foot.
    static func deletionWarning(
        for group: Group, groups: [Group], hosts: [Host]
    ) -> String {
        let parent = groups.first { $0.id == group.parentId }
        let hostsGo = "to \(parent?.name ?? "Ungrouped")"

        // Everything beneath, however deep: whom what it sets reaches.
        var beneath: Set<String> = [group.id]
        var frontier = [group.id]
        while let id = frontier.popLast() {
            for child in groups where child.parentId == id && !beneath.contains(child.id) {
                beneath.insert(child.id)
                frontier.append(child.id)
            }
        }
        let own = hosts.count(where: { $0.groupId == group.id })
        let reached = hosts.count(where: { beneath.contains($0.groupId) })
        let inside = groups.count(where: { $0.parentId == group.id })
        guard own + inside > 0 else { return "Nothing is filed under it. \(cannotBeUndone)" }

        var moves: [String] = []
        switch own {
        case 0: break
        case 1: moves.append("Its one host moves \(hostsGo)")
        case let count: moves.append("Its \(count) hosts move \(hostsGo)")
        }
        if inside > 0 {
            let carried = reached - own
            let hostsOf = carried == 1 ? "1 host" : "\(carried) hosts"
            let theirs = carried == 0 ? "" : inside == 1 ? ", with its \(hostsOf)" : ", with their \(hostsOf)"
            let them = inside == 1 ? "the group inside it" : "the \(inside) groups inside it"
            if parent == nil {
                // Not where the hosts go: a group with none above stands at
                // the head of the list, not under Ungrouped.
                moves.append(them + (inside == 1 ? " becomes a group of its own"
                                                 : " become groups of their own") + theirs)
            } else if moves.isEmpty {
                moves.append(them + (inside == 1 ? " moves " : " move ") + hostsGo + theirs)
            } else {
                moves.append((inside == 1 ? "so does " : "so do ") + them + theirs)
            }
        }
        let moved = moves.joined(separator: ", and ")
        var said = moved.prefix(1).uppercased() + moved.dropFirst() + "."

        // What it gives the hosts beneath it, which goes with it.
        var gives: [String] = []
        if !group.user.trimmingCharacters(in: .whitespaces).isEmpty { gives.append("the user") }
        if !group.keyPath.trimmingCharacters(in: .whitespaces).isEmpty { gives.append("the key") }
        // Its own, kept in the keychain, which deleting the group takes away.
        if group.hasPassword { gives.append("the password") }
        if !group.proxyJump.trimmingCharacters(in: .whitespaces).isEmpty { gives.append("the jump host") }
        if group.forwardAgent != nil { gives.append("agent forwarding") }
        if !group.theme.isEmpty { gives.append("the palette") }
        if !group.sshOptions.isEmpty { gives.append("its ssh options") }
        if !gives.isEmpty, reached > 0 {
            let listed = gives.count == 1 ? gives[0]
                : gives.dropLast().joined(separator: ", ") + " and " + gives.last!
            let whom = reached == 1 ? "that host" : "those \(reached) hosts"
            said += " \(listed.prefix(1).uppercased() + listed.dropFirst()) it gives \(whom) "
                + (gives.count == 1 ? "goes" : "go") + " with it."
        }
        // Closed as every other deletion question is: "Delete EU?" alone
        // left it out.
        return said + " Nothing is deleted but the group itself. \(cannotBeUndone)"
    }

    /// The groups that could hold this one: everything except itself and
    /// what is already beneath it. A group inside its own child is a loop,
    /// and the surest way to stop one is not to offer it.
    static func possibleParents(for group: Group, among all: [Group]) -> [Group] {
        guard !group.id.isEmpty else { return all }
        var beneath: Set<String> = [group.id]
        var frontier = [group.id]
        while let id = frontier.popLast() {
            for child in all where child.parentId == id && !beneath.contains(child.id) {
                beneath.insert(child.id)
                frontier.append(child.id)
            }
        }
        return all.filter { !beneath.contains($0.id) }
    }

    /// The same for a group: a name, and not its own ancestor.
    static func problem(with group: Group, among others: [Group]) -> String? {
        let name = group.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "A group needs a name." }
        if others.contains(where: {
            $0.id != group.id && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return "There is already a group called \(name)."
        }
        if !group.id.isEmpty, group.parentId == group.id {
            return "A group cannot be inside itself."
        }
        return problem(withOptions: group.sshOptions)
    }

    /// The same for an identity: a name, and not one another identity has.
    ///
    /// An identity that says nothing — no user and no key — is **not** a
    /// problem. It is a record somebody has started, and refusing to save it
    /// would mean the name could not be typed before the rest. The sheet says
    /// so quietly instead.
    static func problem(with identity: Identity, among others: [Identity]) -> String? {
        let name = identity.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "An identity needs a name." }
        if others.contains(where: {
            $0.id != identity.id && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return "There is already an identity called \(name)."
        }
        return nil
    }

    /// What deleting an identity takes with it: everything that points at it
    /// stops pointing at anything, and what it was filling in goes.
    ///
    /// **There is no rename to follow.** A host and a group point at an
    /// identity by id, not by name, so renaming one takes nothing with it —
    /// unlike renaming a host, which has to rewrite every jump field that
    /// named it. Don't add one.
    static func deletionWarning(
        for identity: Identity, hosts: [Host] = [], groups: [Group] = []
    ) -> String {
        let name = identity.name.trimmingCharacters(in: .whitespaces)
        // Every host it **reaches**, not only the ones pointing straight at
        // it: a group that points at it passes it to everything beneath, and
        // saying "2 groups" of six machines is the mistake the jump host's
        // warning already made once. `effective.identity` is what reaches a
        // host, which is the same question answered by the resolver.
        let reached = hosts.count {
            !$0.effective.identity.isEmpty
                && $0.effective.identity.caseInsensitiveCompare(name) == .orderedSame
        }
        // The groups are named, since that is where the pointer would be
        // changed.
        let pointing = groups.filter { !identity.id.isEmpty && $0.identityId == identity.id }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        var who: [String] = []
        if reached > 0 { who.append(reached == 1 ? "1 host" : "\(reached) hosts") }
        switch pointing.count {
        case 0: break
        case 1: who.append("the group \(pointing[0])")
        case 2...3:
            who.append(
                "the groups \(pointing.dropLast().joined(separator: ", ")) and \(pointing.last!)")
        default: who.append("\(pointing.count) groups")
        }
        guard !who.isEmpty else { return "Nothing points at it. \(cannotBeUndone)" }

        let one = reached + pointing.count == 1
        var gives: [String] = []
        if !identity.user.trimmingCharacters(in: .whitespaces).isEmpty { gives.append("the user") }
        switch identity.kind {
        case .key:
            if !identity.keyPath.trimmingCharacters(in: .whitespaces).isEmpty {
                gives.append("the key")
            }
        case .password:
            // Always, and without asking the keychain: this is nonisolated
            // engine code, and the kind is enough to know what goes.
            gives.append("the password")
        }
        let whom = who.joined(separator: " and ")
        var said = whom.prefix(1).uppercased() + whom.dropFirst()
            + (one ? " points" : " point") + " at it"
        if !gives.isEmpty {
            said += ", and \(one ? "loses" : "lose") \(gives.joined(separator: " and "))"
        }
        return said + ". Nothing is deleted but the identity itself. \(cannotBeUndone)"
    }
}
