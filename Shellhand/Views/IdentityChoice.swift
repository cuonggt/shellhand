import SwiftUI

/// The identity a host or a group points at, chosen in an editor: drawn as a
/// menu draws its value, its arrows in their round bezel (`MenuArrows`), and
/// what the groups above give in grey — as `AgentChoice` and `PaletteChoice`
/// draw theirs, and as the Key row's placeholder does beside it.
///
/// **A named row rather than a glyph on the user field**, which is where
/// Termius puts the same choice. Their shape is the better idea in the
/// abstract — an identity is not a third setting beside the user and the key,
/// it is a way of filling them — and it does not survive contact with this
/// app: a *group* can point at an identity, every other row in these editors
/// says where an inherited value came from, and a menu glyph has nowhere to
/// put "from Production".
struct IdentityChoice: View {
    /// The identity's id, or empty for whatever a group above gives.
    @Binding var chosen: String
    /// The identities to choose from, in the order a menu lists them.
    let identities: [Identity]
    /// The name of the identity a group above points at, or empty where none
    /// does. The **name** alone: the row's caption says where it came from,
    /// as the Key row's does.
    let inherited: String

    var body: some View {
        Menu {
            Picker("", selection: $chosen) {
                Text(noneTitle).tag("")
                if !identities.isEmpty {
                    Divider()
                    ForEach(identities) { identity in
                        Text(identity.name).tag(identity.id)
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    // Grey while this record chooses nothing, since that is
                    // what grey means in these forms: a value from above.
                    .foregroundStyle(chosen.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                MenuArrows()
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Identity: \(title)")
    }

    /// What choosing nothing is called. "None" where nothing is inherited —
    /// and where something is, the inherited name, so the first item of the
    /// menu says what leaving it alone actually does rather than claiming
    /// there is no identity when there is one.
    private var noneTitle: String { inherited.isEmpty ? "None" : inherited }

    /// What the row reads when shut: the chosen identity's name, or what
    /// leaving it alone gives. An id nothing answers to reads as None rather
    /// than as a blank, which is what a list edited from outside can leave.
    private var title: String {
        guard !chosen.isEmpty else { return noneTitle }
        return identities.first { $0.id == chosen }?.name ?? "None"
    }
}
