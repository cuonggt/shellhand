import Foundation

/// A host list as a spreadsheet writes one.
///
/// Every other client exports CSV, so a file that came out of one is the
/// likeliest thing a fresh installation has to start from — and the only
/// thing someone keeping their machines in a spreadsheet has at all.
///
/// Unlike the settings file, a column this does not recognise is passed over
/// rather than refused. That file is written by hand, where a typo silently
/// doing nothing is the one outcome worth ruling out; this one is written by
/// another program, and an export that carries a Password and a Notes column
/// is the normal case rather than a mistake. What was passed over is reported
/// instead, so nothing disappears quietly.
nonisolated enum CSVHosts {
    /// What a file turned out to hold.
    nonisolated struct Reading: Sendable, Equatable {
        var document = Portable.Document()
        /// Headers that became a field, in the file's own spelling.
        var used: [String] = []
        /// Headers nothing was made of.
        var ignored: [String] = []

        var hosts: Int { document.hosts.count }
    }

    /// The fields a row can fill. Everything else a host has — its ssh
    /// options, its palette — is not a thing spreadsheets carry, and is left
    /// to the editor.
    private enum Field: CaseIterable {
        case name, addr, port, user, identity, group, tags, jump

        /// Spellings seen in the wild, already normalised. A header is matched
        /// by letters and digits alone, so `Host Name`, `host_name` and
        /// `HostName` are one spelling.
        var aliases: [String] {
            switch self {
            case .name: ["name", "label", "alias", "nickname", "title"]
            case .addr: ["address", "addr", "hostname", "ip", "ipaddress", "server"]
            case .port: ["port", "sshport"]
            case .user: ["user", "username", "login", "loginname", "sshuser"]
            case .identity: ["identity", "identityfile", "key", "keyfile", "privatekey", "sshkey"]
            case .group: ["group", "folder", "category", "parent"]
            case .tags: ["tags", "tag", "labels", "keywords"]
            case .jump: ["jump", "jumphost", "proxyjump", "bastion", "proxy"]
            }
        }
    }

    /// Reads a file. The first row names the columns; everything after it is a
    /// machine.
    static func read(_ raw: String) throws -> Reading {
        let separator = separator(raw)
        let rows = rows(raw, separator: separator)
        guard let header = rows.first else {
            throw PortableError("this file is empty")
        }

        var columns: [Int: Field] = [:]
        var reading = Reading()
        // `host` means the address in a flat export and the name in one shaped
        // after ssh's own config, where HostName carries the address. Which it
        // is depends on the rest of the header, so it is settled last.
        var hostColumn: Int?
        for (index, title) in header.enumerated() {
            let key = normalise(title)
            if key == "host" { hostColumn = index; continue }
            guard let field = Field.allCases.first(where: { $0.aliases.contains(key) }),
                  !columns.values.contains(field)
            else {
                reading.ignored.append(title.isEmpty ? "column \(index + 1)" : title)
                continue
            }
            columns[index] = field
            reading.used.append(title)
        }
        if let hostColumn {
            let field: Field = columns.values.contains(.addr) ? .name : .addr
            if columns.values.contains(field) {
                reading.ignored.append(header[hostColumn])
            } else {
                columns[hostColumn] = field
                reading.used.append(header[hostColumn])
            }
        }

        guard columns.values.contains(.name) || columns.values.contains(.addr) else {
            throw PortableError(
                "the first row of this file should name its columns, and none of them is a name "
                    + "or an address — the ones understood are name, address, port, user, "
                    + "identity, group, tags and jump")
        }

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard row.contains(where: { !$0.isEmpty }) else { continue }
            guard row.count <= header.count else {
                throw PortableError(
                    "line \(line) has \(row.count) values where the first row names "
                        + "\(header.count) columns")
            }
            if let host = try host(row, columns, line) { reading.document.hosts.append(host) }
        }

        guard !reading.document.hosts.isEmpty else {
            throw PortableError("this file names its columns but holds no machines")
        }
        reading.document.groups = groups(of: reading.document.hosts)
        return reading
    }

    /// One row. Nil only for a row that is entirely empty, which a spreadsheet
    /// leaves behind at the end of a file.
    private static func host(_ row: [String], _ columns: [Int: Field], _ line: Int) throws
        -> Portable.Host?
    {
        var host = Portable.Host()
        for (index, field) in columns {
            let value = index < row.count ? row[index] : ""
            guard !value.isEmpty else { continue }
            switch field {
            case .name: host.name = value
            case .addr: host.addr = value
            case .user: host.user = value
            case .group: host.group = value
            case .jump: host.jump = value
            case .identity: host.identity = NSString(string: value).expandingTildeInPath
            case .tags: host.tags = Tags.clean(value)
            case .port:
                guard let port = Int(value), port > 0, port < 65536 else {
                    throw PortableError(
                        "line \(line): \(value.debugDescription) is not a port number")
                }
                // 22 is what ssh does anyway, and leaving it out keeps an
                // export free of noise — the same rule the ssh config reader
                // follows.
                if port != 22 { host.port = port }
            }
        }
        // A file may carry only one of the two. A name with no address
        // connects to its own name, which is what `Host myserver` means in an
        // ssh config; an address with no name is known by its address.
        if host.name.isEmpty { host.name = host.addr }
        if host.addr.isEmpty { host.addr = host.name }
        guard !host.name.isEmpty else {
            throw PortableError("line \(line) has values but no name or address")
        }
        return host
    }

    /// The groups the rows asked for, declared so the merge creates them
    /// rather than refusing a host that points at one that is not there.
    private static func groups(of hosts: [Portable.Host]) -> [Portable.Group] {
        var seen: Set<String> = []
        var groups: [Portable.Group] = []
        for host in hosts where !host.group.isEmpty {
            let key = host.group.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            groups.append(Portable.Group(name: host.group))
        }
        return groups
    }

    /// Tags in one cell, however that cell separated them — the same rule the
    /// editor's field uses, so a tag typed by hand and a tag imported from a
    /// sheet cannot come out spelled differently.

    /// Letters and digits, lowercased: everything a header might be spaced,
    /// hyphenated or underscored with is noise.
    private static func normalise(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: the grammar

    /// What this file separates values with.
    ///
    /// A comma unless something else is more common in the first line, which
    /// is how a file saved by a spreadsheet in a locale that writes decimals
    /// with a comma comes back — semicolons throughout, and otherwise exactly
    /// a CSV.
    static func separator(_ raw: String) -> Character {
        let line = raw.prefix(while: { $0 != "\n" && $0 != "\r" })
        let counts: [(Character, Int)] = [",", ";", "\t"].map { candidate in
            (candidate, line.count { $0 == candidate })
        }
        let best = counts.max { $0.1 < $1.1 }
        return (best?.1 ?? 0) > 0 ? best!.0 : ","
    }

    /// The rows of a file, as RFC 4180 has them: a quoted value may hold the
    /// separator, a line break, and a doubled quote standing for one.
    static func rows(_ raw: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var value = ""
        var quoted = false
        var inQuotes = false
        var iterator = raw.makeIterator()
        var pending: Character?

        func endValue() {
            row.append(quoted ? value : value.trimmingCharacters(in: .whitespaces))
            value = ""
            quoted = false
        }
        func endRow() {
            endValue()
            rows.append(row)
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                guard character == "\"" else { value.append(character); continue }
                // A doubled quote stands for one; a single one ends the value.
                if let next = iterator.next() {
                    if next == "\"" { value.append("\"") } else { inQuotes = false; pending = next }
                } else {
                    inQuotes = false
                }
                continue
            }
            switch character {
            case "\"" where value.trimmingCharacters(in: .whitespaces).isEmpty:
                // Only at the start of a value, so a stray quote mid-word —
                // 5" wide — stays the character it is rather than swallowing
                // the rest of the line.
                inQuotes = true
                quoted = true
                value = ""
            case separator:
                endValue()
            // Swift reads CRLF as ONE Character, so the pair is matched as
            // itself. Looking ahead for the LF after a CR finds the next
            // value instead, and the row never ends.
            case "\n", "\r\n", "\r":
                endRow()
            default:
                value.append(character)
            }
        }
        // Only when the file does not end in a line break: a file that does
        // has already had its last row closed.
        if !value.isEmpty || !row.isEmpty { endRow() }
        // Blank lines are kept so that a line number in a complaint is the
        // line the person would count to in their editor. The reader skips
        // them.
        return rows
    }
}
