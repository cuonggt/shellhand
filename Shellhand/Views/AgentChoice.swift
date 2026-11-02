import SwiftUI

/// Agent forwarding chosen in an editor: the choice drawn as a menu draws its
/// value, its arrows in their round bezel (`MenuArrows`), and what the groups
/// above give in grey, as an inherited palette's name is in the row above it.
/// As a menu's own value it was black whatever it was: "Not carried by
/// default" stood black under "Gruvbox Dark from Production" in grey, though
/// the host set neither.
struct AgentChoice: View {
    @Binding var choice: Bool?
    /// What leaving it to the groups above gives, in words (`Effective.agent`).
    let inherited: String
    /// What carrying it is called here: to this host, or to these hosts.
    let carried: String

    var body: some View {
        Menu {
            Picker("", selection: $choice) {
                Text(inherited).tag(Bool?.none)
                Text(carried).tag(Bool?.some(true))
                Text("Not carried").tag(Bool?.some(false))
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .foregroundStyle(choice == nil ? .secondary : .primary)
                MenuArrows()
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Agent forwarding: \(title)")
    }

    private var title: String {
        switch choice {
        case nil: inherited
        case true?: carried
        case false?: "Not carried"
        }
    }
}
