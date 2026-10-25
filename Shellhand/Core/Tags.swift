import Foundation

/// Tags, and the rules about them.
///
/// The second way to find a machine, beside the tree. A group says where a
/// host lives and passes its settings down; a tag says what a host *is*, cuts
/// across the tree, and carries nothing. A host can be in one group and have
/// as many tags as it likes.
///
/// Here rather than in the sidebar that shows them, for the reason the rest of
/// `Core` exists: a rule in a view can only be tested by driving the view.
nonisolated enum Tags {
    /// Tags as somebody typed them, in a field or in a spreadsheet cell.
    ///
    /// One rule everywhere, because two would be worse than either: a comma,
    /// a semicolon, a bar or a space all separate. That rules out a tag with
    /// a space in it, which is a trade worth making — a tag is a word you
    /// filter by, and "north europe" meaning one tag rather than two is the
    /// kind of thing nobody can tell by looking.
    static func clean(_ raw: String) -> [String] {
        unique(raw.split(whereSeparator: separates).map(String.init))
    }

    /// Whether this character ends one tag and begins the next.
    ///
    /// Here rather than written out twice: the editor's field asks it to know
    /// when what has been typed is finished, and `clean` asks it to split. A
    /// tag typed by hand and a tag imported from a sheet coming out spelled
    /// differently is the kind of bug nobody reports.
    static func separates(_ character: Character) -> Bool {
        character == "," || character == ";" || character == "|" || character.isWhitespace
    }

    /// Written back the way the field shows them.
    static func text(_ tags: [String]) -> String { tags.joined(separator: ", ") }

    /// Every tag in use, in the order a list should show them.
    ///
    /// Deduped without regard to case but keeping the spelling first written,
    /// so a host tagged `Web` and one tagged `web` are under one chip rather
    /// than two that look identical.
    static func all(in hosts: [Host]) -> [String] {
        unique(hosts.flatMap(\.tags)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    /// The hosts carrying **all** of these tags, which is what choosing two
    /// chips means: narrowing, not widening. Choosing `web` and `eu` asks for
    /// the European web servers, not for everything that is either.
    static func hosts(_ hosts: [Host], taggedWith chosen: Set<String>) -> [Host] {
        guard !chosen.isEmpty else { return hosts }
        return hosts.filter { host in
            chosen.allSatisfy { has($0, host) }
        }
    }

    /// Does this host carry this tag, however either is cased.
    static func has(_ tag: String, _ host: Host) -> Bool {
        host.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// The hosts that change when a tag is renamed — only those, so renaming
    /// a tag two hosts carry writes two rows rather than the whole list.
    ///
    /// A rename onto a tag that already exists merges the two, which is the
    /// only sensible reading of it and is how you fix a typo that has been
    /// spreading.
    static func renaming(_ old: String, to new: String, in hosts: [Host]) -> [Host] {
        let replacement = clean(new).first ?? ""
        guard !replacement.isEmpty, !old.isEmpty else { return [] }
        // Exactly what it already is: the dialog opened, nothing was typed,
        // Rename was pressed. Compared exactly rather than loosely, so that
        // `web` → `WEB` is still a rename — that is how the spelling gets
        // settled across hosts that wrote it differently.
        guard replacement != old else { return [] }
        return hosts.compactMap { candidate in
            guard has(old, candidate) else { return nil }
            var changed = candidate
            changed.tags = unique(candidate.tags.map {
                $0.caseInsensitiveCompare(old) == .orderedSame ? replacement : $0
            })
            return changed.tags == candidate.tags ? nil : changed
        }
    }

    /// The same for taking a tag off every host that carries it. The tag is
    /// gone when nothing carries it: there is no list of tags to delete from.
    static func removing(_ tag: String, from hosts: [Host]) -> [Host] {
        guard !tag.isEmpty else { return [] }
        return hosts.compactMap { candidate in
            guard has(tag, candidate) else { return nil }
            var changed = candidate
            changed.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
            return changed
        }
    }

    /// What stops a tag being named that, in words a field can show.
    ///
    /// A name another tag already has is deliberately not a problem: renaming
    /// onto an existing tag merges the two, which is how a typo that has been
    /// spreading gets cleaned up.
    static func problem(withTag raw: String) -> String? {
        let wanted = clean(raw)
        if wanted.isEmpty { return "A tag needs a name." }
        if wanted.count > 1 {
            return "A tag is one word — a comma or a space starts another one."
        }
        return nil
    }

    /// Deduped without regard to case, keeping the first spelling and the
    /// order they came in.
    private static func unique(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }
}
