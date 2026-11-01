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
/// Along the bottom is the command the whole of it adds up to, which is the
/// only honest way to show what a form full of inherited values will actually
/// do.
struct HostEditorSheet: View {
    let store: HostStore
    @State private var host: Host
    @State private var tagText: String
    /// What is in the tag field and not yet a tag. Held here rather than in
    /// the field so that Save can count it: it was dropped.
    @State private var tagTyping = ""
    @State private var preview = HostPreview()
    @State private var saving = false
    /// Why the store refused the last Save, said in the editor it refused.
    @State private var saveFailure: String?
    @State private var confirmingDelete = false
    /// The name for a group being made here. Until now groups could only
    /// arrive by import, so a host could not be filed anywhere new.
    @State private var newGroupName = ""
    @State private var optionsText: String
    @State private var tab: Tab = .general
    /// How tall the command along the bottom is, whole.
    @State private var commandHeight: CGFloat = 0
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case name, address, port }

    private enum Tab: Hashable { case general, advanced }

    /// The room below the toolbar of the window this opens over, which it
    /// fits in — `SheetHeight`.
    let room: SheetRoom

    init(store: HostStore, host: Host, room: SheetRoom = SheetRoom()) {
        self.store = store
        self.room = room
        _host = State(initialValue: host)
        _tagText = State(initialValue: Tags.text(host.tags))
        _optionsText = State(initialValue: host.sshOptions.joined(separator: "\n"))
    }

    private var isNew: Bool { host.id.isEmpty }

    /// The most of the command the foot shows before it scrolls: six lines,
    /// which a host behind a jump host fills. The heights below make room
    /// for it.
    nonisolated static let commandRoom: CGFloat = 116

    /// One line of the command, the least the foot shows: two left the form
    /// scrolling at the window's default size with a problem along the foot.
    nonisolated static let leastCommand: CGFloat = 32

    /// What the form has over db-01's General at the height it was measured
    /// for, with nothing along the foot but the command: 28pt, less 4 kept.
    nonisolated static let formSpare: CGFloat = 24

    /// One line along the foot — a problem, a rename note, a refused save.
    nonisolated static let footLine: CGFloat = 23

    /// How much of the command the foot shows in an editor `height` tall that
    /// wanted `wanted`, with `lines` lines along the foot above it:
    /// `commandRoom`, less whatever the window could not give and the form
    /// cannot spare, so the form keeps the room it was measured to fit and
    /// the command scrolls in its box instead — never less than two lines.
    /// It gave up all of the shortfall, leaving the box two lines and a half
    /// under 55pt of the form standing empty.
    nonisolated static func commandCap(wanted: CGFloat, height: CGFloat, lines: Int = 0) -> CGFloat {
        let spare = max(0, formSpare - footLine * CGFloat(lines))
        return max(leastCommand, commandRoom - max(0, wanted - height - spare))
    }

    /// The box's inset around the command, and one of its lines with the gap
    /// to the next: six lines inside the inset are `commandRoom`'s 116.
    nonisolated static let commandInset: CGFloat = 8
    nonisolated static let commandLine: CGFloat = 17

    /// How tall the command's box is under `cap`: the command whole where it
    /// fits, and otherwise ending partway down a line, so the line cut off
    /// says there is more. Cut on a line's edge, the editor at the window's
    /// default size showed three lines that read as the whole command, the
    /// jump host's ProxyCommand and the destination out of sight beneath.
    nonisolated static func commandShown(_ content: CGFloat, cap: CGFloat) -> CGFloat {
        guard content > cap else { return content }
        let whole = ((cap - commandInset - 4) / commandLine).rounded(.down)
        return min(cap, commandInset + commandLine * whole + 8)
    }

    /// What each tab was measured to need; see the frame for how.
    private var wanted: CGFloat { tab == .general ? 736 : 640 }

    /// Where the user this host logs in as comes from while its own field is
    /// empty: nil when it says one itself, or nothing above gives one.
    private var userFrom: String? {
        let from = preview.effective.userFrom
        guard host.user.trimmingCharacters(in: .whitespaces).isEmpty,
              !from.isEmpty, from != "itself" else { return nil }
        return from
    }

    /// What it gets, over the window it opens over.
    private var height: CGFloat { SheetHeight.fitted(736, in: room.height) }

    /// The lines along the foot above the command, each taking room the form
    /// could otherwise spare it.
    private var footLines: Int {
        [saveFailure != nil, problem != nil, store.renameNote(for: host) != nil]
            .filter { $0 }.count
    }

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
        // Measured by tab — General carries nine rows and Advanced four —
        // but drawn at the taller tab's height on both: a sheet is centred
        // on its window, so one that changed height with the tab moved the
        // tab control under the pointer, 27pt over a tall window. What each
        // tab was measured to need still says how much of the command its
        // foot shows (`wanted`).
        //
        // Measured on screen, and sized for **editing** rather than for new:
        // an editor opened on a host has a Delete in the footer, which costs
        // the form 23pt, and more in it to show. At 600/480 both tabs of an
        // edit scrolled, and so did Advanced on a new one. Editing is the
        // case that has to fit, so a new host sits with some slack — which is
        // the right way round, a scroll bar being the thing worth avoiding.
        //
        // The command along the bottom takes up to `commandRoom` where it
        // took two lines, and at 650/570 that left both tabs of a host behind
        // a jump host 41pt short, read off the scroll bars' thumbs. 45pt more
        // fitted it with 4 to spare, which a problem along the foot then
        // overran by 19 — where 650/570 had room for one — so each is 70pt
        // taller. The caption under Connect to saying where the user comes
        // from added 17pt to General's form, so it is 736 — the spare back
        // to within a point.
        //
        // Where the window has less room than that below its toolbar — 668
        // at its default 1100×720 — the editor is the room less a margin, and
        // the command's box gives up the difference: at 720 General hung
        // below the window's bottom edge.
        .frame(width: DialogSize.medium, height: height)
        .task(id: previewKey) {
            // Its own palette left out, so what the preview inherits is what
            // inheriting would give — `HostDetailView.inheriting`.
            var asTyped = HostDetailView.inheriting(host)
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
                    VStack(alignment: .leading, spacing: 3) {
                        destination
                        // Where an empty user comes from, as Key and Jump
                        // host say beside theirs — under this row, which has
                        // no room beside it. It said nothing, the inherited
                        // name sitting in the field as if typed.
                        if let userFrom {
                            Text("user from \(userFrom)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Inherited from \(userFrom). Type a user to set it on this host.")
                        }
                    }
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
                row("Jump host", from: preview.effective.proxyJumpFrom, set: host.proxyJump) {
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
                    TagField(text: $tagText, typing: $tagTyping, known: store.allTags)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// What happens once you are on the host.
    private var advanced: some View {
        Form {
            Section("Once connected") {
                // Chosen by looking at it, as everywhere a palette is.
                LabeledContent("Colours") {
                    PaletteChoice(
                        chosen: host.theme, inherited: inheritedTheme,
                        inheritedPalette: TerminalSession.palette(named: preview.effective.theme),
                        onChoose: { host.theme = $0 })
                }
                LabeledContent("Agent forwarding") {
                    Picker("", selection: $host.forwardAgent) {
                        Text(inheritedAgent).tag(Bool?.none)
                        Text("Carried to this host").tag(Bool?.some(true))
                        Text("Not carried").tag(Bool?.some(false))
                    }
                    .labelsHidden()
                }
            }

            // No section header: the field writes its own label, and the two
            // stacked read "ssh options" twice — as the group editor learned.
            Section {
                SSHOptionsField(text: $optionsText)
            }
        }
        .formStyle(.grouped)
    }

    /// `user@host:port`, as one row, because that is one destination — it is
    /// how ssh is typed and how the command along the bottom ends. Three
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
                    // "from Production", as the group editor and the
                    // inspector say it: the name alone read as a value.
                    Text("from \(from)")
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

    /// The jump field's example — here and in the group editor — never a
    /// host in the list, its own name included: on bastion's own editor
    /// "bastion" read as bastion going through itself, which saving refuses,
    /// and in Production's group editor, bastion filed there, as Production
    /// going through it.
    nonisolated static func jumpExample(avoiding names: [String]) -> String {
        let taken = Set(names.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        return ["bastion", "gateway", "jumpbox"].first { !taken.contains($0) } ?? "jumphost"
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
        JumpHostField(
            text: $host.proxyJump,
            prompt: shown(preview.effective.proxyJump, Self.jumpExample(
                avoiding: store.snapshot.hosts.map(\.name) + [host.name])),
            hosts: otherHosts)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let saveFailure {
                Label(saveFailure, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Both, not one or the other. The command used to be replaced by
            // the problem, which took the thing away exactly when you wanted
            // to look at what was wrong with it. Said quietly on a new host
            // nobody has typed into, where it used to be left out: Add sat
            // greyed with no reason given, while New Group gave one.
            if let problem {
                Label(problem, systemImage: isUntouched ? "info.circle" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(isUntouched ? Color.secondary : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A rename takes the jump fields that name the host along, which
            // is worth knowing before Save rather than finding them changed.
            if let renameNote = store.renameNote(for: host) {
                Label(renameNote, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // What the form adds up to, once there is an address to put in it:
            // `ssh ''` for an empty form says nothing anyone needs. One
            // argument a line, as the inspector draws it, in a box as tall as
            // the command up to `commandCap` and scrolled past that: the
            // quoted line, cut to two, hid a jump chain's middle in `'"'"'`.
            if !preview.argv.isEmpty,
               !host.addr.trimmingCharacters(in: .whitespaces).isEmpty {
                ScrollView {
                    CommandLines(preview: preview)
                        .padding(Self.commandInset)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            commandHeight = $0
                        }
                }
                .frame(height: Self.commandShown(commandHeight, cap: Self.commandCap(
                    wanted: wanted, height: height, lines: footLines)))
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
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

    /// A new host nobody has typed into yet, which is told what it needs but
    /// not warned: a warning that a host needs a name, before anyone has had
    /// the chance to give it one, is nagging.
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
    /// row — so choosing it is a decision rather than a shrug. Read off the
    /// groups, not the preview, which has this host's own choice in it.
    private var inheritedAgent: String {
        let above = FromAbove(of: host, among: store.snapshot.groups)
        return Effective.inheritedAgent(above.forwardAgent, from: above.forwardAgentFrom)
    }

    /// What the terminal would come up in if this host chose nothing: the
    /// nearest group that names a palette, or the one in Settings.
    private var inheritedTheme: String { preview.effective.inheritedPalette }


    private func save() {
        saving = true
        saveFailure = nil
        host.name = host.name.trimmingCharacters(in: .whitespaces)
        host.addr = host.addr.trimmingCharacters(in: .whitespaces)
        host.sshOptions = SSHOptionsField.parse(optionsText)
        host.tags = Tags.saved(tagText, typing: tagTyping)
        Task {
            // The group first, so the host has somewhere to be filed.
            if makingGroup {
                guard let group = await store.save(Group(name: newGroupName)) else {
                    return refused()
                }
                host.groupId = group.id
            }
            guard await store.save(host) != nil else { return refused() }
            saving = false
            dismiss()
        }
    }

    /// A save the store refused keeps the editor open with what was typed,
    /// and says why here. It used to close regardless, and the edits went with
    /// it. The window's own alert is cleared, or it would say the same thing
    /// again once the editor closes.
    private func refused() {
        saveFailure = store.lastError ?? "This host could not be saved."
        store.clearError()
        saving = false
    }
}
