import Foundation

// These are read and written off the main actor, so they and their Codable
// conformances are nonisolated: the app is MainActor by default.

/// The host list as `Core` hands it over, with every group above a host
/// already folded into `effective`.
nonisolated struct Snapshot: Codable, Sendable, Equatable {
    var groups: [Group] = []
    var hosts: [Host] = []
    /// The logins a host or a group can point at. Read with the list rather
    /// than asked for per host: there are a handful of them and every
    /// resolve needs all of them.
    var identities: [Identity] = []
}

nonisolated struct Host: Codable, Sendable, Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var addr: String = ""
    var port: Int = 0
    /// What is typed onto the host itself. Empty means "take it from above",
    /// which is what `effective` then reports.
    var user: String = ""
    var keyPath: String = ""
    /// The identity this host points at, by id. Empty means it points at
    /// none, which is not the same as pointing at one that says nothing.
    ///
    /// By id rather than by name, as a group is: ids never leave this app, so
    /// renaming an identity costs nothing and takes nothing with it — unlike
    /// a jump host, which is named and so has to be followed.
    var identityId: String = ""
    var proxyJump: String = ""
    var groupId: String = ""
    var tags: [String] = []
    /// What this machine said it was the last time it was reached — the `ID`
    /// out of its own `/etc/os-release`, so `ubuntu`, `debian`, `fedora`.
    /// Empty until it has been asked, and for anything that could not answer.
    ///
    /// Learned rather than typed: nothing in the editor sets it, and
    /// `Host.shouldAskOS` decides when to ask again.
    var os: String = ""
    /// When this host was last **asked** what it is, as seconds since 1970,
    /// or 0 for never.
    ///
    /// The asking and not the answering, which is the whole point of it: a
    /// host that cannot say — one taking only a password, a BSD with no such
    /// file, a container with no sftp subsystem — would otherwise be asked
    /// again on every single connect for ever, which is the cost this exists
    /// to bound. A failed attempt stamps this exactly as a successful one
    /// does.
    var osSeen: Double = 0
    /// What the machine calls itself in words — `Ubuntu 22.04.3 LTS` — from
    /// its own `PRETTY_NAME`. Empty when it has not said, or said only an id.
    ///
    /// Kept beside `os` rather than derived from it because nothing here has
    /// a table of distributions, deliberately: the id finds a mark by
    /// filename and this is the machine's own words for itself. Deriving
    /// "Ubuntu 22.04.3 LTS" from "ubuntu" is not possible and inventing
    /// "Opensuse-leap" from "opensuse-leap" would be worse than the id.
    var osName: String = ""

    /// What to call this host's operating system, in as many words as it
    /// gave. Empty when it has never said anything.
    ///
    /// **A mark nobody can read is decoration**, and several of these are a
    /// coloured tile at the size a row draws them. This is what the tooltip,
    /// the accessibility label and the inspector all say, so the three cannot
    /// drift — and it is out here rather than in the view because a decision
    /// inside a view can only be checked by driving the view.
    var osLabel: String { osName.isEmpty ? os : osName }

    /// Whether to ask this host what it is.
    ///
    /// **Once a day, not once ever and not every connect.** Asking once ever
    /// left a machine rebuilt onto another distribution claiming what it used
    /// to be, with nothing anywhere able to correct it; asking every time
    /// doubles the logins this app makes to somebody's machines, for an icon.
    /// A day bounds the staleness and the cost at the same time, and needs no
    /// button for somebody to find.
    ///
    /// Pure, and out here rather than in the view, so the schedule can be
    /// checked without opening a connection to anything.
    /// **The stamp alone decides, and `os.isEmpty` must not come into it.**
    /// That looks like the obvious first condition and it undoes the whole
    /// thing: a host that cannot say keeps an empty `os` for ever, so it
    /// would be due on every connect for ever. Never-asked is already covered
    /// — `osSeen` is 0 then, which is further in the past than any interval.
    ///
    /// **`allowed` is the switch in Settings ▸ General, and it outranks the
    /// schedule**: off, no host is due, not even one never asked. Required
    /// rather than defaulted, so no caller can ask without consulting it.
    func shouldAskOS(
        allowed: Bool, now: Date = Date(), every: TimeInterval = 24 * 60 * 60
    ) -> Bool {
        allowed && !id.isEmpty && now.timeIntervalSince1970 - osSeen >= every
    }

    /// The switch `allowed` comes from: whether this app asks hosts what they
    /// run at all. Asking is a second login, which on some machines sets off
    /// an alert or a session recorder.
    static let askingSetting = "askHostsWhatTheyRun"

    /// On unless it was turned off: nothing stored is how every copy behaved
    /// from 0.0.12, before there was a switch.
    static func asks(_ stored: Any?) -> Bool { stored as? Bool ?? true }

    static var asksNow: Bool { asks(UserDefaults.standard.object(forKey: askingSetting)) }
    /// `-o` settings for this host alone, ahead of anything a group or the
    /// config says, because ssh keeps the first value it is given.
    var sshOptions: [String] = []
    /// Whether the agent is carried to this host. Nothing means "whatever the
    /// group above says", which is why it is not a plain Bool: a group that
    /// turns it on and a host that turns it off are different from a host
    /// that was never asked.
    var forwardAgent: Bool?
    /// The palette this host's terminals come up in. Empty means "take it
    /// from above", and nothing anywhere in the chain means the one chosen in
    /// Settings.
    var theme: String = ""
    var effective = Effective()
}

/// What the host connects with once the groups above it have filled in what it
/// leaves empty, and the name of whatever supplied each value.
nonisolated struct Effective: Codable, Sendable, Hashable {
    var user: String = ""
    var userFrom: String = ""
    var keyPath: String = ""
    var keyPathFrom: String = ""
    /// The name of the identity that reached this host, and the group that
    /// pointed at it — empty when the host points at it itself, as
    /// `userFrom` is empty when the host sets its own user.
    ///
    /// The **name**, not the id: this is what a row shows, and nothing
    /// outside the store has any use for an id.
    var identity: String = ""
    var identityFrom: String = ""
    var proxyJump: String = ""
    var proxyJumpFrom: String = ""
    var port: Int = 22
    var aliasElsewhere: Alias?
    /// What ssh's own config would send this host through, when the host
    /// itself names no jump. Empty otherwise — a jump of the host's own goes
    /// on the command line, which ssh reads first and keeps.
    ///
    /// Shown because the alternative is the inspector saying a host has no
    /// jump host while ssh quietly takes it through one, which is a worse
    /// answer than saying nothing.
    var configProxy: String = ""
    /// What ssh's own config would **run** to reach this host, where it
    /// names a `ProxyCommand` instead of a jump host. Shown as its own row:
    /// a command line is not a jump host, and putting one in a field
    /// labelled "Jump host" would be a different wrong answer rather than a
    /// right one.
    var configProxyCommand: String = ""
    /// Every `-o` setting that reaches this host, nearest first.
    var sshOptions: [String] = []
    /// Whether the agent is carried, and what said so.
    var forwardAgent: Bool?
    var forwardAgentFrom: String = ""
    /// The palette that reaches this host, and what supplied it.
    var theme: String = ""
    var themeFrom: String = ""

    /// What a host would come up in if it chose no palette of its own: the
    /// nearest group that names one, or the one in Settings.
    ///
    /// Out here because the host editor and the inspector both label their
    /// "inherit" option with it, and two copies of a sentence drift — which
    /// this app has already watched happen with error handling.
    var inheritedPalette: String {
        let (name, from) = inheritedPaletteParts
        return Self.inherited(name, from: from)
    }

    /// The same in two parts, the palette and where it comes from, for the
    /// inspector's row, which says the second under or beside the first as
    /// its other rows do.
    var inheritedPaletteParts: (name: String, from: String) {
        guard !theme.isEmpty else { return (Themes.inSettings, "Settings") }
        return (theme, themeFrom.isEmpty ? "above" : themeFrom)
    }

    /// An inherited value as an inherit row names it: the value, then where
    /// it comes from — "Gruvbox Dark from Production", as "deploy from
    /// Production" reads everywhere else. A palette read "From Production —
    /// Gruvbox Dark", source first, and the group inspector "As in Settings"
    /// where the editors said "From Settings".
    static func inherited(_ value: String, from source: String) -> String {
        "\(value) from \(source)"
    }

    /// Agent forwarding as the inspectors show it: "Carried" or "Not
    /// carried", with the group that said so where one did, and where
    /// nothing says either way, what ssh does when it is told nothing.
    static func agent(_ says: Bool?, from source: String) -> (value: String, from: String) {
        guard let says else { return ("Not carried by default", "") }
        return (says ? "Carried" : "Not carried", source)
    }

    /// The same as an inherit row names it — "Carried from Production". It
    /// read "From Production — carried", source first, and "Not carried
    /// (nothing says)" where the group inspector said "—" and the host
    /// inspector had no row for it.
    static func inheritedAgent(_ says: Bool?, from source: String) -> String {
        let (value, from) = agent(says, from: source)
        return from.isEmpty ? value : inherited(value, from: from)
    }

    /// What to show as the jump host, and what supplied it.
    ///
    /// **Both sources, because either alone is wrong.** The host's own wins
    /// when it is set — that goes on the command line and ssh keeps the first
    /// value it is given — but with nothing set, a config entry matching this
    /// destination really does route the connection, and showing nothing says
    /// the opposite of what will happen.
    ///
    /// Out here rather than in `HostDetailView` for the reason every rule in
    /// this app is: a decision inside a view can only be checked by driving
    /// the view, and this app's dialogs do not answer to `click at`.
    var jumpHost: (value: String, from: String) {
        proxyJump.isEmpty && !configProxy.isEmpty
            ? (configProxy, "your SSH config")
            : (proxyJump, proxyJumpFrom)
    }
}

nonisolated struct Alias: Codable, Sendable, Hashable {
    var name: String
    var addr: String
    var port: Int
}

nonisolated struct Group: Codable, Sendable, Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var parentId: String = ""
    var user: String = ""
    var keyPath: String = ""
    /// The identity every host beneath it takes its login from, unless the
    /// host says otherwise — reaching them after this group's own fields and
    /// before the group above it.
    var identityId: String = ""
    var proxyJump: String = ""
    /// Reaches every host beneath it, after each host's own.
    var sshOptions: [String] = []
    var forwardAgent: Bool?
    /// The palette every host beneath it comes up in unless it says otherwise.
    /// Production not looking like staging is the point.
    var theme: String = ""
}

/// A login written once and pointed at from many hosts and groups: who to log
/// in as, and the key to log in with.
///
/// **A group that is not a place.** It sits in the inheritance chain between
/// a record's own fields and its parent's — your own first, then whatever you
/// point at, then the same again for each group above you — so it is one more
/// step in the walk the resolver already does rather than a second mechanism
/// with its own precedence to get wrong.
///
/// Nothing here is a secret. A key is a path handed to ssh, which does its
/// own expanding; the YAML export carries these as they stand, and its header
/// says as much.
nonisolated struct Identity: Codable, Sendable, Identifiable, Hashable {
    /// How it proves who it is. **Not a free-for-all**: a key is a path
    /// handed to ssh, and a password is a secret kept in this Mac's keychain
    /// and never in the store or its export.
    nonisolated enum Kind: String, Codable, Sendable, CaseIterable {
        case key, password

        /// What the menu calls it, and what a row says it is.
        var title: String {
            switch self {
            case .key: "A key on disk"
            case .password: "A password"
            }
        }
    }

    var id: String = ""
    var name: String = ""
    /// Declared before `user` so the memberwise initialiser keeps working for
    /// everything written before it existed: an argument it leaves out takes
    /// the default, and the rest stay in order.
    var kind: Kind = .key
    var user: String = ""
    var keyPath: String = ""

    /// Whether it would fill anything in. One that says nothing is not a
    /// failure — it is a record somebody has started — but it is worth
    /// saying before four hosts are filed under it.
    ///
    /// **A password identity is never "nothing"**, whatever is typed here:
    /// what it carries lives in the keychain, which this cannot see and must
    /// not read — a model property that touched the keychain would do so once
    /// per row, per redraw.
    var saysNothing: Bool {
        kind == .key
            && user.trimmingCharacters(in: .whitespaces).isEmpty
            && keyPath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// How a row names where a value came from: "from the deploy identity".
    ///
    /// A phrase rather than the bare name, because every other source in this
    /// app is a group — "from Production" — and a bare "from deploy" would
    /// read as one. The captions, the inherit rows and the inspectors all go
    /// through here, so the spelling cannot drift between them.
    var source: String { "the \(name) identity" }

    /// What it fills in, in as many words as a row has room for: "deploy ·
    /// ~/.ssh/id_ed25519", or what it says of the two.
    ///
    /// Whether a password is actually **stored** is not said here: that is a
    /// keychain read, and this is drawn once per row.
    var summary: String {
        var parts = [user].map { $0.trimmingCharacters(in: .whitespaces) }
        switch kind {
        case .key: parts.append(keyPath.trimmingCharacters(in: .whitespaces))
        case .password: parts.append("password")
        }
        let said = parts.filter { !$0.isEmpty }
        return said.isEmpty ? "Says nothing yet" : said.joined(separator: " · ")
    }
}

/// What an import did, or would do with `dryRun`.
nonisolated struct MergeResult: Codable, Sendable {
    var changes: [Change] = []
    var added = 0
    var updated = 0
    var unchanged = 0
    /// What the file said that this app no longer keeps — "credentials",
    /// "snippets", "startup snippets". Apart from `changes` rather than among
    /// them, because nothing is written for these: a row in the list of what
    /// will change would leave Import enabled with nothing to do.
    var passedOver: [String] = []

    /// What a dry run would do, which is all the import sheet ever shows:
    /// it said "5 added" before anything had been.
    var plan: String {
        var doing: [String] = []
        if added > 0 { doing.append("add \(added)") }
        if updated > 0 { doing.append("update \(updated)") }
        let said = doing.isEmpty ? "Nothing to add or update" : "Would " + doing.joined(separator: " and ")
        return unchanged > 0 ? "\(said) · \(unchanged) already here" : said
    }
}

/// What a CSV import did, with the reading of the file that produced it.
nonisolated struct CSVImport: Sendable {
    var result = MergeResult()
    /// Columns that became a field, and columns nothing was made of — both in
    /// the file's own spelling, so the window can name them back.
    var used: [String] = []
    var ignored: [String] = []
}

nonisolated struct Change: Codable, Sendable, Hashable, Identifiable {
    var kind: String
    var name: String
    var action: String

    var id: String { "\(action) \(kind) \(name)" }
}

// MARK: Phase 2 — files

/// A file or directory on either side of a transfer.
nonisolated struct RemoteEntry: Codable, Sendable, Identifiable, Hashable {
    var name = ""
    var size: Int64 = 0
    var mode = ""
    var modTime = ""
    var isDir = false

    var id: String { name }
}

nonisolated struct Listing: Codable, Sendable {
    var path = ""
    var parent = ""
    var label = ""
    var entries: [RemoteEntry] = []
}

nonisolated struct Transfer: Codable, Sendable, Identifiable, Hashable {
    var id = ""
    var name = ""
    /// Whether this is one file or a folder of them, which decides how it is
    /// carried and is worth showing beside the name.
    var kind = ""
    var done: Int64 = 0
    var total: Int64 = 0
    /// `queued`, `running`, `done`, `failed` or `cancelled` —
    /// `TransferQueue` names them and decides what moves next.
    var state = TransferQueue.queued
    var error = ""
    /// Which way it goes, for the strip: the two panes' names and the folder
    /// it lands in. The window fills these in, since the engine knows
    /// sessions and paths and not what a pane is called.
    var from = ""
    var to = ""
    var into = ""

    var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }

    /// The engine's latest word on this transfer, with the labels the window
    /// gave it kept: a report from the engine carries none.
    func labelled(like other: Transfer) -> Transfer {
        var out = self
        out.from = other.from
        out.to = other.to
        out.into = other.into
        return out
    }
    /// Nothing more will happen to it. Not simply "not running": a transfer
    /// waiting its turn has not finished, and reading it as finished was what
    /// made a queue impossible to add.
    var finished: Bool {
        state == TransferQueue.done || state == TransferQueue.failed
            || state == TransferQueue.cancelled
    }
    var waiting: Bool { state == TransferQueue.queued }
    var moving: Bool { state == TransferQueue.running }
}
