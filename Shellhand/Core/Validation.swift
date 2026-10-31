import Foundation

/// What stops a record being saved, in words a form can show.
///
/// Here rather than in the sheet that shows it, because these are rules about
/// the data and not about the dialog: a name that two hosts share breaks the
/// export, the import and the jump host field whoever typed it.
nonisolated enum Validation {
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
        else { return "This cannot be undone." }
        return "\(name) is the jump host for \(through.who). Without it, ssh "
            + "is left to find a machine called \(name) by itself. This cannot be undone."
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
    /// saying: nothing is lost but the group.
    static func deletionWarning(
        for group: Group, groups: [Group], hosts: [Host]
    ) -> String {
        let parent = groups.first { $0.id == group.parentId }
        let destination = parent.map { "to \($0.name)" } ?? "to the top of the list"

        // Everything beneath, however deep, because that is what moves.
        var beneath: Set<String> = [group.id]
        var frontier = [group.id]
        while let id = frontier.popLast() {
            for child in groups where child.parentId == id && !beneath.contains(child.id) {
                beneath.insert(child.id)
                frontier.append(child.id)
            }
        }
        var parts: [String] = []
        switch hosts.count(where: { beneath.contains($0.groupId) }) {
        case 0: break
        case 1: parts.append("Its one host moves \(destination)")
        case let count: parts.append("Its \(count) hosts move \(destination)")
        }
        switch groups.count(where: { $0.parentId == group.id }) {
        case 0: break
        case 1: parts.append("so does the group inside it")
        case let count: parts.append("so do the \(count) groups inside it")
        }
        guard !parts.isEmpty else { return "Nothing is filed under it. This cannot be undone." }
        return parts.joined(separator: ", and ") + ". Nothing is deleted but the group itself."
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
}
