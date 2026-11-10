import SwiftUI

/// A host's or a group's own password, beside its key, at the owner's word
/// (2026-11-08): typed here and kept in this Mac's keychain on Save — the
/// record's own Add or Save, never as it is typed, as an identity's is kept
/// on its own Set.
///
/// **A password kept is never read back to be shown.** The field over one
/// stays empty and says it is kept, as an identity's says "unchanged": what
/// is typed replaces it, and the bin at the field's end forgets it on Save,
/// with a way back until then. What reaches the record from above — a
/// group's, an identity's — is said in grey and credited beside it by the
/// row, as the key's is.
struct PasswordField: View {
    /// What has been typed, kept on Save where it is not empty.
    @Binding var typed: String
    /// Whether Save forgets the one kept.
    @Binding var forgetting: Bool
    /// Whether the record keeps one of its own now, before this edit.
    let keeps: Bool
    /// Whether one reaches it from above, should it keep none.
    let inherited: Bool

    var body: some View {
        // The field, then the room every field's menu stands in, as the
        // jump host's row has them, so it ends where the key's ends.
        HStack(spacing: 6) {
            SecureField("", text: $typed, prompt: Text(
                Self.prompt(keeps: keeps, forgetting: forgetting, inherited: inherited)))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .help("Kept in this Mac's keychain, never in the list or its export. A "
                    + "terminal tab types it when ssh asks for it, once, and SFTP hands it over.")
            FieldMenu.room.overlay(alignment: .trailing) { control }
        }
    }

    /// Forget the one kept, or keep it after all — only while nothing has
    /// been typed, since what is typed replaces it either way.
    @ViewBuilder
    private var control: some View {
        if keeps, typed.isEmpty {
            if forgetting {
                Button { forgetting = false } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Keep the saved password")
                .help("Keep the saved password")
            } else {
                Button { forgetting = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Forget the saved password")
                    .help("Forget the saved password on Save")
            }
        }
    }

    /// What the empty field says: that one is kept — the record's own, or
    /// one from above, which the row's caption names — or that Save will
    /// forget the record's own. Nothing where there is none: an example of a
    /// password is no use to anyone.
    nonisolated static func prompt(keeps: Bool, forgetting: Bool, inherited: Bool) -> String {
        if keeps { return forgetting ? "forgotten on Save" : "kept in this Mac's keychain" }
        return inherited ? "kept in this Mac's keychain" : ""
    }

    /// Whether the row names where a password from above comes from: only
    /// where the record has none of its own in play — none kept, and none
    /// typed. Over one kept and being forgotten the field says so, and a
    /// caption beside it would say two things at once.
    nonisolated static func namesSource(typed: String, keeps: Bool) -> Bool {
        typed.isEmpty && !keeps
    }

    /// What Save does with it.
    nonisolated static func change(typed: String, forgetting: Bool) -> HostStore.PasswordChange {
        if !typed.isEmpty { return .set(typed) }
        return forgetting ? .forget : .keep
    }
}
