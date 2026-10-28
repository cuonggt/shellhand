import Foundation

/// Which operating system a host is running, read from the file it keeps that
/// answer in.
///
/// `/etc/os-release` is the one thing every modern Linux agrees on — a handful
/// of `KEY=value` lines, specified by systemd and shipped by distributions
/// that have nothing else in common. It is a **plain file**, which is the
/// whole reason this is cheap: the app already speaks SFTP, so it can read the
/// answer rather than run a command for it. Running one would mean bringing
/// back the process machinery that was deleted as dead code, and the three
/// traps recorded against it.
///
/// Out here rather than beside the reading for the usual reason: a parser in a
/// network path can only be checked by standing up a network, and this is a
/// string going in and a string coming out.
nonisolated enum OSRelease {
    /// The id a distribution calls itself — `ubuntu`, `debian`, `fedora` —
    /// from the contents of `/etc/os-release`. Empty when the file says
    /// nothing this understands.
    ///
    /// `ID_LIKE` is the fallback because a derivative that forgets `ID` still
    /// names what it is built on, and an Ubuntu mark on a machine that is
    /// Ubuntu underneath is better than no mark at all. It can hold several,
    /// most-alike first, so the first word wins.
    static func id(from text: String) -> String {
        let fields = fields(in: text)
        if let own = fields["ID"], !own.isEmpty { return own }
        if let like = fields["ID_LIKE"]?.split(separator: " ").first {
            return String(like)
        }
        return ""
    }

    /// What the machine calls itself in words — `Ubuntu 22.04.3 LTS` — for
    /// saying beside the mark. Empty when the file does not say.
    static func name(from text: String) -> String {
        let fields = fields(in: text)
        return fields["PRETTY_NAME"] ?? fields["NAME"] ?? ""
    }

    /// The file as a dictionary, lowercased ids and all.
    ///
    /// Values are quoted or not at the distribution's whim — `ID=ubuntu` and
    /// `ID="ubuntu"` are both in the wild — and the quotes are not part of the
    /// answer. Anything that is not `KEY=value` is skipped rather than
    /// refused: this is somebody else's file and a line we do not understand
    /// is not a reason to report nothing.
    private static func fields(in text: String) -> [String: String] {
        var out: [String: String] = [:]
        // Split on both, because a file fetched from a machine is whatever
        // that machine wrote — and Swift reads CRLF as one Character, so a
        // parser matching "\r" alone would match neither half.
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let split = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<split]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: split)...])
                .trimmingCharacters(in: .whitespaces)
            for quote in ["\"", "'"] where value.hasPrefix(quote) && value.hasSuffix(quote) && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            out[key] = key == "ID" || key == "ID_LIKE" ? value.lowercased() : value
        }
        return out
    }
}
