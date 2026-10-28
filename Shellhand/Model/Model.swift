import Foundation

// These are read and written off the main actor, so they and their Codable
// conformances are nonisolated: the app is MainActor by default.

/// The host list as `Core` hands it over, with every group above a host
/// already folded into `effective`.
nonisolated struct Snapshot: Codable, Sendable, Equatable {
    var groups: [Group] = []
    var hosts: [Host] = []
}

nonisolated struct Host: Codable, Sendable, Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var addr: String = ""
    var port: Int = 0
    /// What is typed onto the host itself. Empty means "take it from above",
    /// which is what `effective` then reports.
    var user: String = ""
    var identity: String = ""
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
    func shouldAskOS(now: Date = Date(), every: TimeInterval = 24 * 60 * 60) -> Bool {
        !id.isEmpty && now.timeIntervalSince1970 - osSeen >= every
    }
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
        guard !theme.isEmpty else { return "From Settings" }
        return themeFrom.isEmpty ? "From above — \(theme)" : "From \(themeFrom) — \(theme)"
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
            ? (configProxy, "your ssh config")
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
    var identity: String = ""
    var proxyJump: String = ""
    /// Reaches every host beneath it, after each host's own.
    var sshOptions: [String] = []
    var forwardAgent: Bool?
    /// The palette every host beneath it comes up in unless it says otherwise.
    /// Production not looking like staging is the point.
    var theme: String = ""
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

    var summary: String {
        "\(added) added, \(updated) updated, \(unchanged) already matched"
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

    var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
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
