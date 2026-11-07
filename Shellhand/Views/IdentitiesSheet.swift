import SwiftUI

/// Identities: a login written once — who to log in as, and the key to log in
/// with — pointed at from the hosts and groups that use it.
///
/// **The shape every manager here uses**: the list beside the one selected in
/// an `HSplitView`, `+` and `−` at the bottom left, Done at the right, at
/// `DialogSize.large`. Two of the managers this stands in place of started as
/// a list that opened a second sheet on top of itself, which hid the list
/// behind the thing being edited and gave one dialog two footers.
///
/// Nothing here is a secret. A key is a path handed to ssh, which does its
/// own expanding — the same thing the host editor's Key row holds — and the
/// YAML export carries these as they stand.
struct IdentitiesSheet: View {
    let store: HostStore
    let room: SheetRoom

    /// The working copy: the row selected, or a new one not yet written, so a
    /// half-typed identity never shows up in a host's menu.
    @State private var editing: Identity?
    @State private var pendingSave: Task<Void, Never>?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(store: HostStore, room: SheetRoom = SheetRoom()) {
        self.store = store
        self.room = room
    }

    private var isDraft: Bool { editing.map { $0.id.isEmpty } ?? false }

    /// **Neither side clips when this is cut short** — the list scrolls and
    /// the form scrolls — so unlike the two editors, which are sized so that
    /// neither tab ever scrolls, a short window only costs this one a couple
    /// of visible rows.
    private var height: CGFloat { SheetHeight.fitted(520, in: room.height) }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                list
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 320, maxHeight: .infinity)
                detail
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
            // Without this the split sizes itself to its content and sits in
            // a band across the middle of the sheet.
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Button { add() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New identity")
                    .help("New identity")
                Button { confirmingDelete = true } label: { Image(systemName: "minus") }
                    .accessibilityLabel("Delete this identity")
                    .help("Delete this identity")
                    .disabled(editing == nil || isDraft)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: DialogSize.large, height: height)
        // Deleting one clears it off every host and group that points at it,
        // so nothing is left dangling — but those records lose the user and
        // the key they log in with, and nothing else here would say so.
        .confirmationDialog(
            editing.map { "Delete \($0.name.isEmpty ? "this identity" : $0.name)?" } ?? "",
            isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { remove() }
        } message: {
            if let editing { Text(store.deletionWarning(for: editing)) }
        }
        .onDisappear { flush() }
    }

    // MARK: the list

    private var list: some View {
        List(selection: Binding(get: { editing?.id }, set: { choose($0) })) {
            // A draft sits at the top under the empty tag, so picking it back
            // after looking at another row does not make a second one.
            if let editing, editing.id.isEmpty {
                row(editing).tag("")
            }
            ForEach(store.identitiesByName) { identity in
                row(identity).tag(identity.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if store.snapshot.identities.isEmpty, editing == nil { empty }
        }
    }

    /// What an empty list says, and the one thing worth knowing before making
    /// a fourth identity: a login a whole environment shares belongs on the
    /// group, where it reaches everything beneath it.
    private var empty: some View {
        ContentUnavailableView(
            "No identities", systemImage: "person.badge.key",
            description: Text(
                "An identity names a user and a key once, so a dozen hosts need not "
                    + "repeat them. A login a whole environment shares can go on the "
                    + "group instead, and reach every host in it."))
    }

    private func row(_ identity: Identity) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(identity.name.isEmpty ? "New identity" : identity.name)
                    .foregroundStyle(identity.name.isEmpty ? .secondary : .primary)
                Text(identity.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            // What deleting it would cost, where its row can say so without
            // being opened.
            if !identity.id.isEmpty {
                let reach = store.using(identity)
                let count = reach.hosts.count
                if count > 0 {
                    Text(count == 1 ? "1 host" : "\(count) hosts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: the one selected

    @ViewBuilder
    private var detail: some View {
        if editing != nil {
            IdentityDetail(
                store: store,
                identity: Binding(
                    get: { editing ?? Identity() },
                    set: { now in
                        editing = now
                        save(now)
                    }),
                problem: problem)
        } else {
            ContentUnavailableView(
                "Nothing selected", systemImage: "person.badge.key",
                description: Text("Pick an identity, or press + to make one."))
        }
    }

    private var problem: String? {
        guard let editing else { return nil }
        return Validation.problem(with: editing, among: store.snapshot.identities)
    }

    // MARK: moving about and writing

    /// Moves to another row, writing anything still waiting first: switching
    /// away should not be how the last few characters are lost.
    private func choose(_ id: String?) {
        flush()
        guard let id, !id.isEmpty else {
            if id == nil { editing = nil }
            return
        }
        editing = store.snapshot.identities.first { $0.id == id }
    }

    private func add() {
        flush()
        editing = Identity()
    }

    private func remove() {
        guard let identity = editing, !identity.id.isEmpty else { return }
        pendingSave?.cancel()
        editing = nil
        // The password goes with it: a keychain item filed under an identity
        // nothing names any more is one nobody can ever reach again.
        try? Keychain.remove(identity.id)
        Task { await store.delete(identity) }
    }

    /// Holds the write back a moment, and replaces one still waiting.
    ///
    /// **Never write to the store while a list is drawing.** Every save
    /// rereads the store and resolves every host's inheritance, which is far
    /// too much work to do per character — and it mutates the list this
    /// `List` is drawing from while it draws, which crashes the table view
    /// reading it.
    private func save(_ now: Identity) {
        pendingSave?.cancel()
        guard Validation.problem(with: now, among: store.snapshot.identities) == nil
        else { return }
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let saved = await store.save(now)
            // A draft becomes a real row the moment it is first written, and
            // the selection has to follow it or the next keystroke makes a
            // second one.
            if now.id.isEmpty, let saved { editing = saved }
        }
    }

    /// Writes whatever is waiting, now. The sheet closing is the last chance.
    private func flush() {
        pendingSave?.cancel()
        guard let now = editing,
              Validation.problem(with: now, among: store.snapshot.identities) == nil
        else { return }
        Task { await store.save(now) }
    }

    /// The name field's example, never an identity already here and never a
    /// group's name: "Production" over a list holding a Production group
    /// reads as the group rather than as an example.
    nonisolated static func nameExample(avoiding taken: [String]) -> String {
        let taken = Set(taken.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        return ["deploy", "operator", "readonly"].first { !taken.contains($0) } ?? "login"
    }
}

/// One identity: what it is called, who it logs in as, and the key it logs in
/// with — with what points at it underneath, because that is the number worth
/// knowing before changing either field.
struct IdentityDetail: View {
    let store: HostStore
    @Binding var identity: Identity
    let problem: String?

    /// Empty means "leave the keychain alone", which is why the field says
    /// *unchanged* rather than showing anything: a password is not read back
    /// to be displayed.
    @State private var password = ""
    @State private var trouble: String?
    @State private var note: String?
    /// Whether one is stored, read when the row changes rather than on every
    /// redraw: this is drawn as somebody types, and a keychain call per
    /// keystroke is not a thing to do quietly either.
    @State private var stored = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("", text: $identity.name, prompt: Text(
                            IdentitiesSheet.nameExample(
                                avoiding: store.snapshot.identities.map(\.name)
                                    + store.snapshot.groups.map(\.name)))
                        )
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                    }
                    LabeledContent("User") {
                        TextField("", text: $identity.user, prompt: Text(
                            HostEditorSheet.userExample(avoiding: usersInList))
                        )
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                    }
                    LabeledContent("Logs in with") {
                        Picker("", selection: $identity.kind) {
                            ForEach(Identity.Kind.allCases, id: \.self) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .labelsHidden()
                    }
                    if identity.kind == .key {
                        LabeledContent("Key") {
                            TextField("", text: $identity.keyPath, prompt: Text(
                                HostEditorSheet.keyExample(avoiding: keysInList))
                            )
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                        }
                    }
                }

                if identity.kind == .password { passwordSection }

                // Said quietly, as New Group says a missing name: an identity
                // with neither is a record somebody has started, not a
                // mistake, so it is not a warning — but a host pointed at it
                // would inherit nothing and nothing else would say why.
                if identity.saysNothing {
                    Section {
                        Label(
                            "This fills nothing in yet. A host pointed at it takes its user "
                                + "and key from its groups, as before.",
                            systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                usedBy
            }
            .formStyle(.grouped)

            if let problem {
                Divider()
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
    }

    /// What this identity reaches.
    ///
    /// The hosts are the ones it actually fills in for, read off what the
    /// resolver says reaches them — so a host under a group that points at
    /// this identity is counted, rather than only the hosts pointing straight
    /// at it. The groups are named beside them, since a group is where that
    /// pointer would be changed.
    @ViewBuilder
    private var usedBy: some View {
        if !identity.id.isEmpty {
            let reach = store.using(identity)
            Section("Used by") {
                if reach.hosts.isEmpty, reach.groups.isEmpty {
                    Text("Nothing points at it yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reach.groups) { group in
                        LabeledContent {
                            Text("passes it down").foregroundStyle(.secondary)
                        } label: {
                            Label(store.path(of: group), systemImage: "folder")
                        }
                    }
                    ForEach(reach.hosts) { host in
                        LabeledContent {
                            Text(place(of: host)).foregroundStyle(.secondary)
                        } label: {
                            Label(host.name, systemImage: "server.rack")
                        }
                    }
                    Text("Changing the user or the key changes it for all of them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The one field here that is **not** saved as it is typed, because it is
    /// not saved to the same place: it goes to the keychain, under an id the
    /// identity only has once it has been written. The record beside it
    /// debounces to the store; writing half a password to the keychain on
    /// every keystroke is not a thing to do quietly.
    @ViewBuilder
    private var passwordSection: some View {
        Section("The password") {
            LabeledContent("Password") {
                HStack(spacing: 6) {
                    SecureField("", text: $password, prompt: Text(
                        stored ? "unchanged" : "needed to connect"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .onSubmit { set() }
                    Button("Set") { set() }
                        .disabled(password.isEmpty || identity.id.isEmpty)
                }
            }
            if stored {
                Button("Forget it", role: .destructive) { forget() }
                    .controlSize(.small)
            }
            Text("Kept in this Mac's keychain, never in the host list or its export."
                + (identity.id.isEmpty
                    ? " Give it a name first — the keychain files it under the id it "
                        + "gets when it is saved."
                    : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let trouble {
                Text(trouble).font(.caption).foregroundStyle(.red)
            } else if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: identity.id) {
            stored = !identity.id.isEmpty && Keychain.has(identity.id)
            password = ""
            note = nil
            trouble = nil
        }
        // **Typed and not Set was typed and lost**, in silence — and the
        // thing that goes wrong next is a connection refused with
        // "Permission denied", which reads as a wrong password rather than
        // as no password at all. Saving on the way out is not the same as
        // saving per keystroke, which is what the button is there to avoid:
        // the record beside it flushes on disappear for the same reason.
        .onDisappear { if !password.isEmpty { set() } }
    }

    private func set() {
        guard !password.isEmpty, !identity.id.isEmpty else { return }
        do {
            try Keychain.save(password, for: identity.id)
            trouble = nil
            note = "Saved to the keychain."
            stored = true
            password = ""
        } catch {
            trouble = error.localizedDescription
        }
    }

    private func forget() {
        do {
            try Keychain.remove(identity.id)
            trouble = nil
            note = "Forgotten."
            stored = false
            password = ""
        } catch {
            trouble = error.localizedDescription
        }
    }

    /// Where a host is filed, as the sidebar and the inspector name it.
    private func place(of host: Host) -> String {
        guard let group = store.group(host.groupId) else { return "Ungrouped" }
        return store.path(of: group)
    }

    /// Every user the list logs in as — hosts', groups' and the other
    /// identities' — so the example names none of them.
    private var usersInList: [String] {
        store.snapshot.hosts.map(\.user) + store.snapshot.groups.map(\.user)
            + store.snapshot.identities.filter { $0.id != identity.id }.map(\.user)
    }

    /// The same for keys.
    private var keysInList: [String] {
        store.snapshot.hosts.map(\.keyPath) + store.snapshot.groups.map(\.keyPath)
            + store.snapshot.identities.filter { $0.id != identity.id }.map(\.keyPath)
    }
}
