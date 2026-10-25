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
    @State private var tab: Tab = .general
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private enum Tab: Hashable { case general, advanced }

    init(store: HostStore, group: Group) {
        self.store = store
        _group = State(initialValue: group)
        _optionsText = State(initialValue: group.sshOptions.joined(separator: "\n"))
    }

    private var isNew: Bool { group.id.isEmpty }

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
        .frame(width: DialogSize.medium, height: tab == .general ? 570 : 555)
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
        let above = FromAbove(of: group, among: store.snapshot.groups)
        return Form {
            // No header: a name and where it sits are what the dialog is
            // about, and a title above them would only name the thing you
            // are already looking at.
            Section {
                LabeledContent {
                    TextField("", text: $group.name, prompt: Text("Production"))
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
                row("User", value: above.user, from: above.userFrom,
                    example: "deploy", text: $group.user)
                row("Key", value: above.identity, from: above.identityFrom,
                    example: "~/.ssh/id_ed25519", text: $group.identity)
                row("Jump host", value: above.proxyJump, from: above.proxyJumpFrom,
                    example: "bastion", text: $group.proxyJump)
            }
        }
        .formStyle(.grouped)
    }

    /// What happens once you are on a host beneath it.
    private var advanced: some View {
        let above = FromAbove(of: group, among: store.snapshot.groups)
        return Form {
            Section("Once connected") {
                LabeledContent("Colours") {
                    Picker("", selection: $group.theme) {
                        Text(inheritedTheme(above)).tag("")
                        Divider()
                        ForEach(Themes.names, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                LabeledContent("Agent forwarding") {
                    Picker("", selection: $group.forwardAgent) {
                        Text(inheritedAgent(above)).tag(Bool?.none)
                        Text("Carried to these hosts").tag(Bool?.some(true))
                        Text("Not carried").tag(Bool?.some(false))
                    }
                    .labelsHidden()
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
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
    @ViewBuilder
    private func row(
        _ title: String, value: String, from: String,
        example: String, text: Binding<String>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("", text: text, prompt: Text(value.isEmpty ? example : value))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                if text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty, !from.isEmpty {
                    Text("from \(from)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Inherited from \(from). Type here to set it "
                            + "for everything under this group.")
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

    /// What the hosts under this group would come up in if it chose nothing.
    private func inheritedTheme(_ above: FromAbove) -> String {
        above.theme.isEmpty ? "From Settings" : "From \(above.themeFrom) — \(above.theme)"
    }

    /// What the groups above this one say about the agent.
    private func inheritedAgent(_ above: FromAbove) -> String {
        guard let says = above.forwardAgent else { return "Not carried (nothing says)" }
        return "From \(above.forwardAgentFrom) — \(says ? "carried" : "not carried")"
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

    private var problem: String? {
        var asSaved = group
        asSaved.sshOptions = SSHOptionsField.parse(optionsText)
        return Validation.problem(with: asSaved, among: store.snapshot.groups)
    }

    private func save() {
        saving = true
        group.name = group.name.trimmingCharacters(in: .whitespaces)
        group.sshOptions = SSHOptionsField.parse(optionsText)
        Task {
            await store.save(group)
            saving = false
            dismiss()
        }
    }
}
