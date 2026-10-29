import Yams

/// The documents in a YAML stream, or the error that stopped it.
///
/// **`Yams.load_all` does not throw what it finds in the text.** It throws
/// only when a parser cannot be made at all; a scan error while reading — an
/// unclosed quote, a tab where an indent belongs — is caught by the sequence
/// it returns, kept in that sequence's `error`, and the sequence simply
/// ends. So `try load_all(yaml:).compactMap { $0 }`, which both readers here
/// used, read a broken file as no documents, or as the ones before the
/// break: a config that set nothing, an import with nothing in it, and not a
/// word about why. Draining the sequence by hand and asking it afterwards is
/// the whole of the fix, and one copy of it keeps the two from drifting.
nonisolated enum YAMLDocuments {
    static func read(_ raw: String) throws -> [Any] {
        var stream = try Yams.load_all(yaml: raw)
        var documents: [Any] = []
        while let document = stream.next() { documents.append(document) }
        if let error = stream.error { throw error }
        return documents
    }
}
