import SwiftUI

/// Editing what is written on a host.
///
/// Two tabs, and the line between them is what the fields are **for**, not
/// what ssh calls them: General is what you call the host, how to reach it and
/// where you file it; Advanced is what happens once you are on it. A name is
/// not a fact about the machine, which is why it does not sit with the
/// address.
///
/// A field left empty takes its value from the group above, and the row says
/// where from — worked out again whenever the group changes,
/// so it describes the host being typed rather than the one that was opened.
/// The line along the bottom is the command the whole of it adds up to, which
/// is the only honest way to show what a form full of inherited values will
/// actually do.
struct HostEditorSheet: View {
    let store: HostStore
    @State private var host: Host
    @State private var tagText: String
    @State private var preview = HostPreview()
    @State private var saving = false
    @State private var confirmingDelete = false
    /// The name for a group being made here. Until now groups could only
    /// arrive by import, so a host could not be filed anywhere new.
    @State private var newGroupName = ""
    @State private var optionsText: String
    @State private var tab: Tab = .general
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case name, address, port }

    private enum Tab: Hashable { case general, advanced }

    init(store: HostStore, host: Host) {
        self.store = store
        _host = State(initialValue: host)
        _tagText = State(initialValue: Tags.text(host.tags))
        _optionsText = State(initialValue: host.sshOptions.joined(separator: "\n"))
    }

    private var isNew: Bool { host.id.isEmpty }

    /// Stands for "one that does not exist yet" in the group picker. Not an
    /// id anything could have: ids are hex.
    private static let newGroup = "\u{1}new-group"
    private var makingGroup: Bool { host.groupId == Self.newGroup }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            Divider()
            // SwiftUI's Group: the model has one of its own.
            SwiftUI.Group {
                switch tab {
                case .general: general
                case .advanced: advanced
                }
            }
            Divider()
            footer
        }
        // Height by tab rather than one that suits neither: General carries
        // nine rows and Advanced four, so a single height leaves one of them
        // two thirds empty — which is the thing this rebuild set out to fix.
        //
        // Measured on screen, and sized for **editing** rather than for new:
        // an editor opened on a host has a Delete in the footer, which costs
        // the form 23pt, and more in it to show. At 600/480 both tabs of an
        // edit scrolled, and so did Advanced on a new one. Editing is the
        // case that has to fit, so a new host sits with some slack — which is
        // the right way round, a scroll bar being the thing worth avoiding.
        .frame(width: DialogSize.medium, height: tab == .general ? 650 : 570)
        .task(id: previewKey) {
            var asTyped = host
            asTyped.sshOptions = SSHOptionsField.parse(optionsText)
            preview = await store.preview(of: asTyped)
        }
        .onAppear { if isNew { focus = .name } }
        .confirmationDialog(
            "Delete \(host.name)?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.delete(host)
                    dismiss()
                }
            }
        } message: {
            Text(store.deletionWarning(for: host))
        }
    }

    // MARK: the parts

    /// The two tabs. Advanced carries a mark when what is wrong is in there,
    /// so a greyed-out Save never goes unexplained by a tab you cannot see.
    private var tabs: some View {
        Picker("", selection: $tab) {
            Text("General").tag(Tab.general)
            advancedLabel.tag(Tab.advanced)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var advancedLabel: Text {
        guard optionsProblem else { return Text("Advanced") }
        // A character, not an SF Symbol: a segmented picker's segment takes a
        // label string, so an interpolated Image collapses to U+FFFC and draws
        // nothing. This mark was an Image, so it had never once appeared.
        return Text("Advanced !")
    }

    /// What you call it, how to reach it, and where you file it.
    private var general: some View {
        Form {
            // No header: these two are what the dialog is about, and a title
            // above them would only name the thing you are already looking at.
            Section {
                LabeledContent {
                    TextField("", text: $host.name, prompt: Text("web"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .focused($focus, equals: .name)
                } label: {
                    needed("Name")
                }
                LabeledContent {
                    destination
                } label: {
                    needed("Connect to")
                }
            }

            Section("Connect with") {
                row("Key", from: preview.effective.identityFrom, set: host.identity) {
                    TextField("", text: $host.identity,
                              prompt: Text(shown(preview.effective.identity, "~/.ssh/id_ed25519")))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                }
                row("Through", from: preview.effective.proxyJumpFrom, set: host.proxyJump) {
                    jumpField
                }
            }

            Section("File it under") {
                LabeledContent("Group") {
                    Picker("", selection: $host.groupId) {
                        Text("Ungrouped").tag("")
                        ForEach(store.snapshot.groups) { group in
                            Text(store.path(of: group)).tag(group.id)
                        }
                        Divider()
                        Text("New group…").tag(Self.newGroup)
                    }
                    .labelsHidden()
                }
                if makingGroup {
                    LabeledContent("Called") {
                        TextField("", text: $newGroupName, prompt: Text("Production"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    }
                }
                LabeledContent("Tags") {
                    TagField(text: $tagText, known: store.allTags)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// What happens once you are on the host.
    private var advanced: some View {
        Form {
            Section("Once connected") {
                LabeledContent("Colours") {
                    Picker("", selection: $host.theme) {
                        Text(inheritedTheme).tag("")
                        Divider()
                        ForEach(Themes.names, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                LabeledContent("Agent") {
                    Picker("", selection: $host.forwardAgent) {
                        Text(inheritedAgent).tag(Bool?.none)
                        Text("Carried to this host").tag(Bool?.some(true))
                        Text("Not carried").tag(Bool?.some(false))
                    }
                    .labelsHidden()
                }
            }

            Section("ssh options") {
                SSHOptionsField(text: $optionsText)
            }
        }
        .formStyle(.grouped)
    }

    /// `user@host:port`, as one row, because that is one destination — it is
    /// how ssh is typed and how the line along the bottom renders it. Three
    /// rows said the same thing and left you to infer they belonged together.
    private var destination: some View {
        HStack(spacing: 4) {
            TextField("", text: $host.user, prompt: Text(shown(preview.effective.user, "deploy")))
                .frame(width: 92)
            Text("@").foregroundStyle(.secondary)
            TextField("", text: $host.addr, prompt: Text("10.0.0.1"))
                .focused($focus, equals: .address)
            Text(":").foregroundStyle(.secondary)
            // Empty rather than 0 for "whatever ssh does", which is 22: a port
            // of nought is not a port, and showing one invites somebody to
            // correct it.
            TextField("", text: portText, prompt: Text("22"))
                .frame(width: 48)
                .focused($focus, equals: .port)
        }
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .multilineTextAlignment(.leading)
    }

    /// A field with where its value came from beside it.
    ///
    /// Only when this host sets nothing itself: then what is on screen belongs
    /// to a group, and saying so out loud beats leaving it to a grey
    /// placeholder nobody reads.
    @ViewBuilder
    private func row(
        _ title: String, from: String, set: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                content()
                if set.trimmingCharacters(in: .whitespaces).isEmpty,
                   !from.isEmpty, from != "itself" {
                    Text(from)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Inherited from \(from). Type here to set it on this host.")
                }
            }
        }
    }

    /// A label for something that has to be filled in.
    private func needed(_ title: String) -> some View {
        HStack(spacing: 2) {
            Text(title)
            Text("*")
                .foregroundStyle(.secondary)
                .accessibilityLabel("required")
        }
    }

    /// What a field would be if left empty.
    ///
    /// The inherited value when there is one, and otherwise an example of what
    /// belongs there. A dash sat in the field looking like a value somebody
    /// had chosen.
    private func shown(_ value: String, _ example: String) -> String {
        value.isEmpty ? example : value
    }

    /// Whether what is wrong is the ssh options, which live on the other tab.
    private var optionsProblem: Bool {
        var asSaved = host
        if makingGroup { asSaved.groupId = "" }
        asSaved.sshOptions = SSHOptionsField.parse(optionsText)
        guard Validation.problem(with: asSaved, among: store.snapshot.hosts) != nil
        else { return false }
        asSaved.sshOptions = []
        return Validation.problem(with: asSaved, among: store.snapshot.hosts) == nil
    }


    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isNew ? "New host" : host.name.isEmpty ? "Host" : host.name)
                .font(.headline)
            Text(isNew
                ? "Anything left empty is taken from the group it is filed under."
                : "Empty fields come from the group above; the hints say which.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// The jump host is one of your own hosts by name, so the names are
    /// offered — but it stays a field, because `user@bastion.example.com` is
    /// something ssh understands and the list cannot.
    private var jumpField: some View {
        HStack(spacing: 6) {
            TextField("", text: $host.proxyJump,
                      prompt: Text(shown(preview.effective.proxyJump, "bastion")))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.leading)
            Menu {
                Button("None") { host.proxyJump = "" }
                Divider()
                ForEach(otherHosts) { other in
                    Button(other.name) { host.proxyJump = other.name }
                }
            } label: {
                Image(systemName: "list.bullet")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("One of your hosts")
            .help("One of your hosts")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Both, not one or the other. The command used to be replaced by
            // the problem, which took the thing away exactly when you wanted
            // to look at what was wrong with it.
            if let problem, !isUntouched {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // What the form adds up to, once there is an address to put in it:
            // `ssh ''` for an empty form says nothing anyone needs.
            if !preview.argv.isEmpty,
               !host.addr.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(preview.command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil || saving)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: what the form says

    /// The port as text, because the field has to be able to be empty — which
    /// a number cannot be.
    private var portText: Binding<String> {
        Binding(
            get: { host.port == 0 ? "" : String(host.port) },
            set: { typed in
                let digits = typed.filter(\.isNumber)
                host.port = Int(digits) ?? 0
            })
    }

    private var otherHosts: [Host] {
        store.snapshot.hosts
            .filter { $0.id != host.id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Recomputed whenever something that could change what is inherited
    /// changes — the group, and the fields that stop a value
    /// being inherited at all.
    private var previewKey: String {
        [host.groupId, host.user, host.identity, host.proxyJump,
         host.addr, String(host.port), optionsText,
         host.forwardAgent.map(String.init) ?? "-"].joined(separator: "\u{2}")
    }

    /// A new host nobody has typed into yet. Telling someone a host needs a
    /// name before they have had the chance to give it one is nagging.
    private var isUntouched: Bool {
        isNew && host.name.isEmpty && host.addr.isEmpty
    }

    /// What stops this being saved, in one line. The rules are the engine's:
    /// they are about the host, not about this dialog.
    private var problem: String? {
        if makingGroup {
            if let said = Validation.problem(
                with: Group(name: newGroupName), among: store.snapshot.groups) {
                return said
            }
        }
        var asSaved = host
        if makingGroup { asSaved.groupId = "" }
        asSaved.sshOptions = SSHOptionsField.parse(optionsText)
        return Validation.problem(with: asSaved, among: store.snapshot.hosts)
    }

    /// What the groups above say about the agent, for the "leave it to them"
    /// row — so choosing it is a decision rather than a shrug.
    private var inheritedAgent: String {
        guard let says = preview.effective.forwardAgent else { return "Not carried (nothing says)" }
        let from = preview.effective.forwardAgentFrom
        let what = says ? "carried" : "not carried"
        return from.isEmpty ? "From above — \(what)" : "From \(from) — \(what)"
    }

    /// What the terminal would come up in if this host chose nothing: the
    /// nearest group that names a palette, or the one in Settings.
    private var inheritedTheme: String {
        let name = preview.effective.theme
        guard !name.isEmpty else { return "From Settings" }
        let from = preview.effective.themeFrom
        return from.isEmpty ? "From above — \(name)" : "From \(from) — \(name)"
    }


    private func save() {
        saving = true
        host.name = host.name.trimmingCharacters(in: .whitespaces)
        host.addr = host.addr.trimmingCharacters(in: .whitespaces)
        host.sshOptions = SSHOptionsField.parse(optionsText)
        host.tags = Tags.clean(tagText)
        Task {
            // The group first, so the host has somewhere to be filed.
            if makingGroup {
                let group = await store.save(Group(name: newGroupName))
                host.groupId = group?.id ?? ""
            }
            await store.save(host)
            saving = false
            dismiss()
        }
    }
}
