import SwiftUI

/// What a fresh installation shows instead of a terminal.
///
/// An empty list is the one screen every new person sees, and "No hosts yet"
/// on its own leaves them to find the menu. Nobody types thirty machines in by
/// hand; they already have them somewhere. So the first thing offered is the
/// file they already have — counted, by name, before they click anything.
struct WelcomeView: View {
    let store: HostStore
    let onImport: (ImportSheet.Source) -> Void
    let onNewHost: () -> Void

    @State private var configCount: Int?

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 7) {
                Image(systemName: "server.rack")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No hosts yet").font(.title2.weight(.semibold))
                Text("Shellhand keeps its own list. Bring one in to start.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                source(
                    .sshConfig, "doc.text",
                    title: "Your SSH config",
                    detail: configCount.map {
                        "~/.ssh/config names \($0) machine\($0 == 1 ? "" : "s")"
                    } ?? "No ~/.ssh/config here — pick another file",
                    ready: configCount != nil)
                source(
                    .csv, "tablecells",
                    title: "A CSV file",
                    detail: "From a spreadsheet, or another client's export",
                    ready: true)
                source(
                    .yaml, "doc.plaintext",
                    title: "A YAML file",
                    detail: "A list exported from Shellhand",
                    ready: true)
            }
            .frame(maxWidth: 380)

            Button("Add a host by hand", action: onNewHost)
                .buttonStyle(.link)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { configCount = store.sshConfigHosts() }
    }

    /// One way in. A whole row is the target rather than a word inside it,
    /// because at this size the row is what the eye is already on.
    private func source(
        _ kind: ImportSheet.Source, _ symbol: String,
        title: String, detail: String, ready: Bool
    ) -> some View {
        Button {
            onImport(kind)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .frame(width: 24)
                    .foregroundStyle(ready ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        // A button built out of a stack carries no name of its own: in the
        // accessibility tree these came out as "button 1, button 2, button 3",
        // which is what VoiceOver would have read out. The name has to go on
        // the button itself, before the background and the border wrap it in
        // layers of their own — and it has to be a label rather than
        // `accessibilityElement(children: .ignore)`, which names the row but
        // replaces the button's own element, so pressing it does nothing.
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}
