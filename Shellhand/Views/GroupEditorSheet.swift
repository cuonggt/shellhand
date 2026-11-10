import SwiftUI

/// Editing a group.
///
/// A group is not a folder: what is written here reaches every host beneath
/// it that leaves the same field empty, which is the whole reason the tree
/// exists. So the sheet says how many hosts that is, and deleting one hands
/// them to the group above rather than taking them with it.
///
/// Two tabs, the way the host editor has them — but the line between them is
/// the group's own, because a group is never reached. General is what the
/// group **is** and who the hosts under it log in as; Advanced is what
/// happens once you are on one of them. Copying the host editor's line
/// outright would put everything a group has on one side of it.
///
/// Advanced carries a mark when something is wrong over there and a dot when
/// something is merely set, which the `DisclosureGroup` this replaced could
/// not say: it opened itself for the ssh options and the agent and never
/// looked at the palette, so a group that painted its hosts opened with the
/// palette shut and nothing to hint at it — and a palette is the one thing
/// groups are most used for.
struct GroupEditorSheet: View {
    let store: HostStore
    @State private var group: Group
    @State private var saving = false
    @State private var confirmingDelete = false
    @State private var optionsText: String
    /// A password typed for the group, kept in the keychain on Save.
    @State private var passwordTyped = ""
    /// Whether Save forgets the one the group keeps.
    @State private var forgettingPassword = false
    /// Why the store refused the last Save, said in the editor it refused,
    /// as the host editor says it.
    @State private var saveFailure: String?
    @State private var tab: Tab = .general
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private enum Tab: Hashable { case general, advanced }

    /// The room below the toolbar of the window this opens over, which it
    /// fits in — `SheetHeight`, the form scrolling in what is left.
    let room: SheetRoom

    init(store: HostStore, group: Group, room: SheetRoom = SheetRoom()) {
        self.store = store
        self.room = room
        _group = State(initialValue: group)
        _optionsText = State(initialValue: group.sshOptions.joined(separator: "\n"))
    }

    private var isNew: Bool { group.id.isEmpty }

    /// The name field's example, never a group already in the list: in New
    /// Group Inside Production, "Production" sat right above "Inside:
    /// Production" and read as the name already chosen.
    nonisolated static func nameExample(avoiding names: [String]) -> String {
        let taken = Set(names.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        return ["Production", "Staging", "Lab", "Home"].first { !taken.contains($0.lowercased()) }
            ?? "Servers"
    }

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
        // Measured on screen, not reasoned. 500/490 was measured against a
        // **new** group and still scrolled both tabs: the thumbs covered 305
        // of 328 and 303 of 318, so roughly 25 and 15pt were cut. Editing
        // needs more again — a Delete in the footer costs the form about
        // 23pt, as it does in the host editor — so these are sized for an
        // edit, and a new group sits with slack rather than a scroll bar.
        //
        // Both measured on screen in the end: editing a group gives the
        // form 421 and 406pt with no scroll bar, against a new one's 396 and
        // 381. The 23pt an edit costs is the Delete its footer gains.
        //
        // General's 570 on both tabs, where Advanced was 555: a sheet is
        // centred on its window, so the tab control moved 7pt under the
        // pointer each time the tab changed.
        //
        // And 486 since: its rows had gone, and at 570 General ended 137pt
        // above the footer and Advanced 160pt, an empty band under every
        // form. What takes room now is the footer's line saying what is
        // wrong, about 25pt, which comes out of the form: this leaves
        // General a margin under its last row with that line up, and both
        // tabs unscrolled.
        //
        // **516 since, and measured**: the Identity row at the head of what
        // is passed down is one grouped-form row more than 486 was measured
        // with. Driven from outside, Production's General and Advanced both
        // fit at 516 with 46pt under the last row — a margin, not the band
        // of nothing that 570 left — and neither tab scrolls.
        //
        // **476 since, measured before and after the same way**: the
        // Identity row went into the User row (2026-11-09), and its 40pt
        // with it. Driven from outside, Edge — picking an identity — and Lab
        // — a user typed — had 46.5pt under General's last row at 516 in
        // the build before, and 86.5 after, Advanced 108 in both: General is
        // still the taller tab, and 476 gives it its margin back.
        //
        // **517 since**: the Password row under the key (2026-11-10), 41pt.
        // Driven from outside at 516, Edge — a password of its own — and Lab
        // — none — both had 45.5pt under General's last row, a point short
        // of that margin, and Advanced 108: one more point gives it back.
        .frame(width: DialogSize.medium, height: SheetHeight.fitted(517, in: room.height))
        .onAppear { nameFocused = isNew }
        .confirmationDialog(
            "Delete \(group.name)?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.delete(group)
                    dismiss()
                }
            }
        } message: {
            Text(store.deletionWarning(for: group))
        }
    }

    // MARK: the parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isNew ? "New group" : group.name.isEmpty ? "Group" : group.name)
                .font(.headline)
            Text(describeContents)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

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

    /// What the Advanced tab says about itself. Wrong beats set: a mark that
    /// something needs fixing is worth more than one saying something is
    /// there, and showing both at once would say neither clearly.
    ///
    /// Plain characters, not SF Symbols. A segment of a `.segmented` picker
    /// takes a label **string**, so an `Image` interpolated into the `Text`
    /// has nowhere to go: it collapses to U+FFFC, which accessibility dutifully
    /// reports as "Advanced ￼" while the screen shows "Advanced" and no mark
    /// at all. A bullet has a glyph, so it draws.
    private var advancedLabel: Text {
        if optionsProblem { return Text("Advanced !") }
        if advancedCarriesSomething { return Text("Advanced •") }
        return Text("Advanced")
    }

    /// What the group is called, where it sits, and how the hosts under it
    /// log in.
    private var general: some View {
        let above = fromAbove
        return Form {
            // No header: a name and where it sits are what the dialog is
            // about, and a title above them would only name the thing you
            // are already looking at.
            Section {
                LabeledContent {
                    TextField("", text: $group.name, prompt: Text(
                        Self.nameExample(avoiding: store.snapshot.groups.map(\.name))))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .focused($nameFocused)
                } label: {
                    needed("Name")
                }
                LabeledContent("Inside") {
                    Picker("", selection: $group.parentId) {
                        Text("Nothing — a group of its own").tag("")
                        ForEach(possibleParents) { other in
                            Text(store.path(of: other)).tag(other.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            Section("Passed down, unless something beneath says otherwise") {
                // First, on a line of its own above the key, as in the host
                // editor: who the hosts beneath log in as, typed or an
                // identity picked, which fills the key in too.
                userRow(above)
                let key = passedKey(above)
                row("Key", value: key.value, from: key.from,
                    example: HostEditorSheet.keyExample(avoiding: keysInList),
                    text: $group.keyPath)
                passwordRow(above)
                row("Jump host", value: above.proxyJump, from: above.proxyJumpFrom,
                    example: HostEditorSheet.jumpExample(
                        avoiding: store.snapshot.hosts.map(\.name)),
                    text: $group.proxyJump,
                    picking: store.snapshot.hosts.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    })
            }
        }
        .formStyle(.grouped)
    }

    /// What happens once you are on a host beneath it.
    private var advanced: some View {
        let above = fromAbove
        return Form {
            Section("Once connected") {
                // Chosen by looking at it, as everywhere a palette is.
                LabeledContent("Colours") {
                    PaletteChoice(
                        chosen: group.theme, inherited: inheritedTheme(above),
                        inheritedPalette: TerminalSession.palette(named: above.theme),
                        onChoose: { group.theme = $0 })
                }
                LabeledContent("Agent forwarding") {
                    AgentChoice(choice: $group.forwardAgent, inherited: inheritedAgent(above),
                                carried: "Carried to these hosts")
                }
            }

            // No section header: the field writes its own label, and two of
            // them stacked reads as a mistake.
            Section {
                SSHOptionsField(text: $optionsText)
            }
        }
        .formStyle(.grouped)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let saveFailure {
                Label(saveFailure, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Said quietly while a new group has no name yet, as the host
            // editor says it, where it was a warning before anything had
            // been typed.
            if let problem {
                Label(problem, systemImage: isUntouched ? "info.circle" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(isUntouched ? Color.secondary : Color.orange)
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

    private var possibleParents: [Group] {
        Validation.possibleParents(for: group, among: store.snapshot.groups)
    }

    private var hostCount: Int { group.id.isEmpty ? 0 : store.hostsBeneath(group.id).count }

    private var describeContents: String {
        guard !isNew else {
            return "What is written here reaches every host filed under it."
        }
        switch hostCount {
        case 0: return "Nothing is filed under it yet."
        case 1: return "One host takes what is written here, where it says nothing itself."
        default:
            return "\(hostCount) hosts take what is written here, where they say nothing themselves."
        }
    }

    /// A field, with where its value came from beside it.
    ///
    /// The placeholder is what this group would take from the one it sits
    /// inside, and an example of what belongs there when it would take
    /// nothing — a dash sat in the field reading like a value somebody had
    /// chosen. Where it came from is said beside the field rather than folded
    /// into that grey text, which is the shape the host editor settled on.
    ///
    /// A field that names one of your hosts — the jump host — is `picking`
    /// them, and offers them as the host editor's does.
    @ViewBuilder
    private func row(
        _ title: String, value: String, from: String,
        example: String, text: Binding<String>, picking hosts: [Host]? = nil
    ) -> some View {
        LabeledContent(title) {
            // On the field's baseline, as the host editor's rows are: centred,
            // the label stood 1.5pt above the field's words.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // The field and the jump host's menu, or the menu's room, so
                // every field in these rows ends at one edge.
                HStack(spacing: 6) {
                    if let hosts {
                        JumpHostField(text: text, prompt: value.isEmpty ? example : value)
                        FieldMenu.room.overlay(alignment: .trailing) {
                            JumpHostMenu(text: text, hosts: hosts)
                        }
                    } else {
                        TextField("", text: text, prompt: Text(value.isEmpty ? example : value))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                        FieldMenu.room
                    }
                }
                if let from = Self.shownFrom(from, set: text.wrappedValue) {
                    FromCaption(from: from, among: shownFroms,
                                help: "Inherited from \(from). Type here to set it "
                                    + "for everything under this group.")
                }
            }
        }
    }

    /// Who the hosts beneath log in as, on a line of its own above the key:
    /// typed, or an identity picked in the field (`UserField`), as the host
    /// editor has it, with where an inherited user comes from beside it.
    private func userRow(_ above: FromAbove) -> some View {
        let user = passedUser(above)
        return LabeledContent("User") {
            // On the field's baseline, as `row` sets its rows.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                UserField(
                    user: $group.user, identityId: $group.identityId,
                    identities: store.identitiesByName,
                    prompt: user.value.isEmpty
                        ? HostEditorSheet.userExample(avoiding: usersInList) : user.value)
                if let from = userFrom(above) {
                    FromCaption(from: from, among: shownFroms,
                                help: "Inherited from \(from). Type a user or pick an identity "
                                    + "to set it for everything under this group.")
                }
            }
        }
    }

    /// The identity this group picks, where its id answers to one.
    private var picked: Identity? { store.identity(group.identityId) }

    /// What a user left empty here gives the hosts beneath, and where from.
    private func passedUser(_ above: FromAbove) -> (value: String, from: String) {
        Self.passedDown(
            picked: picked?.user ?? "", pickedFrom: picked?.source ?? "",
            above: above.user, aboveFrom: above.userFrom)
    }

    /// What a key left empty here gives the hosts beneath, and where from.
    private func passedKey(_ above: FromAbove) -> (value: String, from: String) {
        Self.passedDown(
            picked: picked?.keyPath ?? "", pickedFrom: picked?.source ?? "",
            above: above.keyPath, aboveFrom: above.keyPathFrom)
    }

    /// What the User row says its user is from (`UserField.caption`).
    private func userFrom(_ above: FromAbove) -> String? {
        UserField.caption(typed: group.user, picked: picked, from: passedUser(above).from)
    }

    /// The group's own password (`PasswordField`), for every host beneath
    /// that keeps none, with whose would reach them otherwise said beside it.
    private func passwordRow(_ above: FromAbove) -> some View {
        LabeledContent("Password") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                PasswordField(
                    typed: $passwordTyped, forgetting: $forgettingPassword,
                    keeps: group.hasPassword,
                    inherited: !Self.passedPassword(picked: picked, above: above).isEmpty)
                if let from = passwordFrom(above) {
                    FromCaption(from: from, among: shownFroms,
                                help: "Kept for \(from) in this Mac's keychain. Type one here "
                                    + "to keep this group's own.")
                }
            }
        }
    }

    /// The Password row's caption, while the group has none of its own in
    /// play (`PasswordField.namesSource`).
    private func passwordFrom(_ above: FromAbove) -> String? {
        guard PasswordField.namesSource(typed: passwordTyped, keeps: group.hasPassword)
        else { return nil }
        let from = Self.passedPassword(picked: picked, above: above)
        return from.isEmpty ? nil : from
    }

    /// Whose password the hosts beneath a group take where the group keeps
    /// none of its own: the identity it picks, where that is a password
    /// one, and otherwise the groups above — the resolver's order. Empty
    /// where none would. The editor's caption and the inspector's row both
    /// read it, so the two cannot say different things.
    nonisolated static func passedPassword(picked: Identity?, above: FromAbove) -> String {
        if let picked, picked.kind == .password, !picked.id.isEmpty { return picked.source }
        return above.passwordAccount.isEmpty ? "" : above.passwordFrom
    }

    /// What a field left empty in a group gives the hosts beneath it, and
    /// where from: what the identity the group picks fills in, and otherwise
    /// what the groups above give — the resolver's order, a group's own
    /// pointer before its parents. Read off the parents alone, a group
    /// picking the deploy identity showed "ubuntu" and "~/.ssh/id_rsa",
    /// examples, where its hosts log in as deploy with ~/.ssh/id_ed25519.
    nonisolated static func passedDown(
        picked: String, pickedFrom: String, above: String, aboveFrom: String
    ) -> (value: String, from: String) {
        let own = picked.trimmingCharacters(in: .whitespaces)
        return own.isEmpty ? (above, aboveFrom) : (own, pickedFrom)
    }

    /// Where a row's value comes from, said beside it only while this group
    /// sets nothing there itself.
    private static func shownFrom(_ from: String, set: String) -> String? {
        set.trimmingCharacters(in: .whitespaces).isEmpty && !from.isEmpty ? from : nil
    }

    /// What this group's parents give it. Read off the groups above, never
    /// off the group itself, which is what its own fields are for.
    private var fromAbove: FromAbove {
        FromAbove(
            of: group, among: store.snapshot.groups, identities: store.snapshot.identities)
    }

    /// Every user and key the list already names, identities included, so an
    /// example names none of them.
    private var usersInList: [String] {
        store.snapshot.hosts.map(\.user) + store.snapshot.groups.map(\.user)
            + store.snapshot.identities.map(\.user)
    }

    private var keysInList: [String] {
        store.snapshot.hosts.map(\.keyPath) + store.snapshot.groups.map(\.keyPath)
            + store.snapshot.identities.map(\.keyPath)
    }

    /// What the captions beside the fields say, every row's, for the column
    /// they stand in.
    private var shownFroms: [String] {
        let above = fromAbove
        return [
            userFrom(above),
            Self.shownFrom(passedKey(above).from, set: group.keyPath),
            passwordFrom(above),
            Self.shownFrom(above.proxyJumpFrom, set: group.proxyJump),
        ].compactMap { $0 }
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

    /// What the hosts under this group would come up in if it chose nothing.
    private func inheritedTheme(_ above: FromAbove) -> String {
        let (name, from) = above.paletteParts
        return Effective.inherited(name, from: from)
    }

    /// What the groups above this one say about the agent.
    private func inheritedAgent(_ above: FromAbove) -> String {
        Effective.inheritedAgent(above.forwardAgent, from: above.forwardAgentFrom)
    }

    /// Whether what is wrong is on the Advanced tab. The ssh options are the
    /// only thing over there that can be refused, so there is nothing to
    /// subtract — unlike the host editor, which has to ask whether its
    /// problem survives clearing them.
    private var optionsProblem: Bool {
        Validation.problem(withOptions: SSHOptionsField.parse(optionsText)) != nil
    }

    /// Whether anything on Advanced has been set, which is what the dot says.
    private var advancedCarriesSomething: Bool {
        !group.theme.isEmpty || group.forwardAgent != nil
            || !SSHOptionsField.parse(optionsText).isEmpty
    }

    /// A new group nobody has named yet: what it needs is said, but not as a
    /// warning.
    private var isUntouched: Bool { isNew && group.name.isEmpty }

    private var problem: String? {
        var asSaved = group
        asSaved.sshOptions = SSHOptionsField.parse(optionsText)
        return Validation.problem(with: asSaved, among: store.snapshot.groups)
    }

    private func save() {
        saving = true
        saveFailure = nil
        group.name = group.name.trimmingCharacters(in: .whitespaces)
        group.sshOptions = SSHOptionsField.parse(optionsText)
        Task {
            // A refusal keeps the editor open with what was typed and says
            // why here, as the host editor does — the keychain's above all,
            // since a password typed and lost would be found only at the
            // next connection, as a refusal.
            guard await store.save(group, password: PasswordField.change(
                typed: passwordTyped, forgetting: forgettingPassword)) != nil
            else {
                saveFailure = store.lastError ?? "This group could not be saved."
                store.clearError()
                saving = false
                return
            }
            saving = false
            dismiss()
        }
    }
}
