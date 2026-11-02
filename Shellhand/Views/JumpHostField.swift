import SwiftUI

/// A jump host, typed or picked from your hosts — in both editors. The group
/// editor's was a field alone, though a group needs the menu as much as a
/// host does: EU and US send all six of their hosts through bastion.
///
/// The field and its menu (`JumpHostMenu`) are apart, so that the rows beside
/// the jump host's keep the menu's room where it stands, and every field in
/// them ends at one edge. Drawn as one, the jump host's field ended a menu
/// short of the key's above it, and the menu's arrow 7pt short of the key's
/// border, a borderless menu padding its glyph.
struct JumpHostField: View {
    @Binding var text: String
    /// The inherited value or an example, never `—`.
    let prompt: String

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .multilineTextAlignment(.leading)
    }
}

/// The hosts a jump host can be picked from, beside its field.
struct JumpHostMenu: View {
    @Binding var text: String
    /// The hosts it could name, the one being edited left out.
    let hosts: [Host]

    var body: some View {
        Menu {
            Button("None") { text = "" }
            Divider()
            ForEach(hosts) { other in
                Button(other.name) { text = other.name }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("One of your hosts")
        .help("One of your hosts")
    }

    /// The menu's room, unseen, in a row beside the jump host's.
    static var room: some View {
        JumpHostMenu(text: .constant(""), hosts: []).hidden()
    }
}
