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

    static func deletionWarning(for host: Host) -> String {
        "This cannot be undone."
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
