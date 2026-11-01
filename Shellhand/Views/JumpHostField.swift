import SwiftUI

/// A jump host, typed or picked from your hosts — in both editors. The group
/// editor's was a field alone, though a group needs the menu as much as a
/// host does: EU and US send all six of their hosts through bastion.
struct JumpHostField: View {
    @Binding var text: String
    /// The inherited value or an example, never `—`.
    let prompt: String
    /// The hosts it could name, the one being edited left out.
    let hosts: [Host]

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.leading)
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
    }
}
