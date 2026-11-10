import SwiftUI

/// Who a host logs in as — or the hosts beneath a group — on a line of its
/// own above the key: a user typed, or one of your identities picked from
/// the menu at its end, which then stands in the field as a token. That is
/// where Termius puts the same choice, and both editors took it at the
/// owner's word (2026-11-08): the identity was a row of its own above the
/// user, which in the host editor was squeezed into `user@host:port` with
/// its caption under the row for want of room beside it.
///
/// The field is the resolver made visible — a host's own user first, then
/// the identity it points at, then whatever the groups above give. So beside
/// a token the field still takes a user, typed to log in in the identity's
/// place while the identity goes on supplying the key; and left empty it
/// says in grey what it would log in as, as every field in the editors
/// does: the identity's own user, or where the identity names none, the one
/// from above — except where that is the token's own name, which would say
/// one word twice (`typingPrompt`).
///
/// Picking an identity that names a user clears a user typed here: picking
/// it is asking for its login, and the typed user would quietly win. One that
/// names none leaves it, since it is then the only user there is.
struct UserField: View {
    @Binding var user: String
    @Binding var identityId: String
    /// The identities to pick from, in the order the menu lists them.
    let identities: [Identity]
    /// What leaving the field empty gives: the user inherited, the identity's
    /// own, or an example where there is none — never `—`.
    let prompt: String

    /// The mark an identity wears here, in its menu and on its token — the
    /// one File ▸ Identities… draws.
    static let symbol = "person.badge.key"

    /// The identity picked here, where the id answers to one. An id nothing
    /// answers to is no identity to the resolver either, so the plain field
    /// stands in its place.
    private var picked: Identity? {
        identityId.isEmpty ? nil : identities.first { $0.id == identityId }
    }

    var body: some View {
        // The field, then its menu in the room every field's menu stands in,
        // as the jump host's row has them, so it ends where the key's ends.
        HStack(spacing: 6) {
            if let picked {
                tokenBox(picked)
            } else {
                TextField("", text: $user, prompt: Text(prompt))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
            }
            FieldMenu.room.overlay(alignment: .trailing) { menu }
        }
    }

    /// The identity as a token that can be taken off, and room after it to
    /// type a user in its place, drawn over a rounded field nobody sees: the
    /// field sets the box's frame and its baseline, so the row stands as tall
    /// with a token as with a user typed, and its label sits where a field's
    /// words do. In the tag field's flowing box, whose baseline is its first
    /// token's words, the box stood 4pt lower than a field and the row 4pt
    /// taller, so picking an identity moved every row under it.
    ///
    /// The token is centred in the box, as a tag is; the typing field after
    /// it stands on the unseen field's baseline, past an unseen token of the
    /// same width. Centred with the token, its grey "cuong" after "work"
    /// stood 3pt above the label's line: a borderless field draws its words
    /// at its top, not its middle.
    private func tokenBox(_ identity: Identity) -> some View {
        // Read here, on the main actor: the alignment closure is Sendable.
        let baseline = TagField.fieldBaseline
        let token = Token(
            title: identity.name, systemImage: Self.symbol,
            removeLabel: "Stop using the \(identity.name) identity"
        ) { identityId = "" }
        return TextField("", text: .constant(""))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .hidden()
            .overlay(alignment: .leading) {
                token
                    .help("The \(identity.name) identity: \(identity.summary)")
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .fieldGround()
            }
            .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    token.hidden()
                    TextField("", text: $user, prompt: Text(Self.typingPrompt(prompt, after: identity)))
                        .textFieldStyle(.plain)
                        // A grouped form's rows right-align their fields, and
                        // that reaches in here, as it did in the tag field.
                        .multilineTextAlignment(.leading)
                        // The rest of the box, so a click anywhere after the
                        // token lands in it.
                        .frame(minWidth: 72, maxWidth: .infinity)
                        .alignmentGuide(.firstTextBaseline) { d in d[.top] + baseline }
                        .accessibilityLabel("User, in place of the identity's")
                }
                .padding(.horizontal, 5)
            }
    }

    /// The identities, the one picked ticked; picking it again lets it go, as
    /// a tag in the tag field's menu does.
    private var menu: some View {
        Menu {
            if identities.isEmpty {
                Text("No identities yet: File ▸ Identities… makes one")
            }
            ForEach(identities) { identity in
                let on = identity.id == identityId
                Button {
                    if on { identityId = "" } else { pick(identity) }
                } label: {
                    Label(identity.name, systemImage: on ? "checkmark" : Self.symbol)
                }
            }
        } label: {
            Image(systemName: Self.symbol)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Your identities")
        .help("Log in as one of your identities")
    }

    private func pick(_ identity: Identity) {
        (identityId, user) = Self.picking(identity, over: user)
    }

    /// What picking `identity` leaves in the field: its id, and a user typed
    /// there cleared where the identity names one of its own — picking it is
    /// asking for its login, and the typed user would quietly win — or kept
    /// where it names none, since it is then the only user there is.
    nonisolated static func picking(
        _ identity: Identity, over typed: String
    ) -> (identityId: String, user: String) {
        let namesOne = !identity.user.trimmingCharacters(in: .whitespaces).isEmpty
        return (identity.id, namesOne ? "" : typed)
    }

    /// What a User row says its user is from, beside it, given what is typed
    /// in it, the identity picked in it, and where the user comes from: nil
    /// where the record says one itself — typed, or an identity picked here
    /// that names one, whose token beside the grey user already says whose
    /// it is — or where nothing gives one. Both editors ask it.
    nonisolated static func caption(typed: String, picked: Identity?, from: String) -> String? {
        guard typed.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let picked, !picked.user.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        return from.isEmpty ? nil : from
    }

    /// What the field says in grey after `identity`'s token: what leaving it
    /// empty logs in as, `prompt` — but nothing where the identity logs in as
    /// its own name, the usual way to name one, since the token already says
    /// it and "deploy deploy" would say one word twice. Where the identity
    /// names no user the grey one is from above, and stays whatever it is
    /// called.
    nonisolated static func typingPrompt(_ prompt: String, after identity: Identity) -> String {
        let user = identity.user.trimmingCharacters(in: .whitespaces)
        let name = identity.name.trimmingCharacters(in: .whitespaces)
        return !user.isEmpty && user.caseInsensitiveCompare(name) == .orderedSame ? "" : prompt
    }
}
