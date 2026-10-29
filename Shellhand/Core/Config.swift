import Foundation

/// Shellhand's settings file.
///
/// One setting so far, and it is the one that matters for connecting:
/// `ssh_options`, applied to every invocation, and `themes:` for terminal
/// palettes. A key this app has no use for is refused rather than ignored: a
/// file that accepted it would be promising something.
///
/// ```yaml
/// ssh_options:
///   - ServerAliveInterval=30
///   - IdentitiesOnly=yes
/// ```
nonisolated struct Config: Sendable, Equatable {
    var sshOptions: [String] = []
    /// Palettes of your own, beside the ones that ship. Here rather than in a
    /// form, because eighteen colours is a thing to paste, not to type.
    var themes: [Palette] = []

    /// `~/Library/Application Support/Shellhand/config.yaml`, beside the store.
    static var defaultPath: String {
        NSString(string: "~/Library/Application Support/Shellhand/config.yaml")
            .expandingTildeInPath
    }

    /// The file a run reads: the one named on the command line, or the usual
    /// one when none was.
    static func path(_ named: String) -> String { named.isEmpty ? defaultPath : named }

    /// Reads the file, or returns the defaults when there is none — a missing
    /// config is a config that sets nothing, which is what a fresh install has.
    static func load(path: String) throws -> Config {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            if FileManager.default.fileExists(atPath: path) {
                throw ConfigError("\(path): this file could not be read as text")
            }
            return Config()
        }
        return try parse(raw, path: path)
    }

    /// Split out so it can be tested without a file on disk.
    static func parse(_ raw: String, path: String = "config") throws -> Config {
        let documents: [Any]
        do {
            documents = try YAMLDocuments.read(raw)
        } catch {
            throw ConfigError("\(path): this is not valid YAML — \(error)")
        }
        // A stream can hold several documents, and anything after the second
        // --- would be skipped in exactly the silent way an unknown key would.
        guard documents.count <= 1 else {
            throw ConfigError(
                "\(path): this is more than one YAML document — settings after the --- "
                    + "would be skipped")
        }
        // Empty, or only comments: a config that sets nothing.
        guard let first = documents.first else { return Config() }
        guard let top = first as? [String: Any] else {
            throw ConfigError("\(path): the top of this file should be settings, one per line")
        }

        // A key that is not a setting is an error rather than something to
        // skip past. Silence is indistinguishable from the file not being read
        // at all, and `ssh_option` without its s would quietly pass nothing
        // to ssh.
        let known = Set(["ssh_options", "themes"])
        for key in top.keys.sorted() where !known.contains(key) {
            throw ConfigError(
                "\(path): \(key) is not a setting — this file takes ssh_options and themes")
        }

        var config = Config()
        if let value = top["ssh_options"] {
            guard let list = value as? [Any] else {
                throw ConfigError("\(path): ssh_options should be a list, one -o setting per line")
            }
            config.sshOptions = try list.map { item in
                guard let option = item as? String else {
                    throw ConfigError("\(path): every ssh_option should be text, like IdentitiesOnly=yes")
                }
                if let problem = SSHArgs.optionProblem(option) {
                    throw ConfigError("\(path): the ssh_option \(option.debugDescription) \(problem)")
                }
                return option.trimmingCharacters(in: .whitespaces)
            }
        }
        if let value = top["themes"] {
            guard let list = value as? [Any] else {
                throw ConfigError("\(path): themes should be a list, one palette each")
            }
            config.themes = try list.map { try palette($0, path) }
        }
        return config
    }

    /// One palette, refused whole if any colour is not one — a terminal
    /// painted with fifteen of sixteen colours is worse than one left alone.
    private static func palette(_ raw: Any, _ path: String) throws -> Palette {
        guard let fields = raw as? [String: Any] else {
            throw ConfigError("\(path): every theme should have named fields")
        }
        let known = Set(["name", "ansi", "background", "foreground", "cursor", "selection"])
        for key in fields.keys.sorted() where !known.contains(key) {
            throw ConfigError(
                "\(path): a theme has a \(key), which is not part of one — they are "
                    + known.sorted().joined(separator: ", "))
        }
        guard let name = fields["name"] as? String,
              !name.trimmingCharacters(in: .whitespaces).isEmpty
        else { throw ConfigError("\(path): a theme has no name") }

        func colour(_ key: String) throws -> RGB {
            guard let text = fields[key] as? String else {
                throw ConfigError("\(path): theme \"\(name)\" has no \(key)")
            }
            guard let rgb = RGB(hex: text) else {
                throw ConfigError(
                    "\(path): the \(key) of theme \"\(name)\" is \(text.debugDescription), "
                        + "which is not a colour like #1d1f21")
            }
            return rgb
        }

        guard let ansi = fields["ansi"] as? [Any] else {
            throw ConfigError("\(path): theme \"\(name)\" has no ansi colours")
        }
        guard ansi.count == 16 else {
            throw ConfigError(
                "\(path): theme \"\(name)\" has \(ansi.count) ansi colours; a palette has 16")
        }
        let colours = try ansi.map { entry -> RGB in
            guard let text = entry as? String, let rgb = RGB(hex: text) else {
                throw ConfigError(
                    "\(path): an ansi colour of theme \"\(name)\" is not a colour like #1d1f21")
            }
            return rgb
        }
        return Palette(
            name: name, ansi: colours,
            background: try colour("background"), foreground: try colour("foreground"),
            cursor: try colour("cursor"), selection: try colour("selection"))
    }
}

nonisolated struct ConfigError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
