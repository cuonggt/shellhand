import SwiftUI

// The three modifiers every pane here carries do one job each:
// `.formStyle(.grouped)` gives the inset rounded sections, `.scrollContent
// Background(.hidden)` lets the window's glass through instead of painting an
// opaque sheet over it, and the top margin keeps the first section off the
// toolbar.

/// How the app behaves, and where it keeps what it knows.
struct GeneralSettingsPane: View {
    @AppStorage("confirmCloseLiveSession") private var confirmClose = true
    @State private var updates = Updates.shared
    let storePath: String
    let configPath: String

    var body: some View {
        Form {
            // Here rather than in a pane of its own: a fourth pane holding
            // one switch would say updates are a subject, and they are one
            // line about how the app behaves. Check Now sits beside the
            // switch as well as in the app menu, because this is where you
            // come when you are wondering what version you are on — the
            // build number is in the corner of this very window.
            Section("Updates") {
                Toggle(isOn: Binding(
                    get: { updates.automatic },
                    set: { updates.automatic = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for updates automatically")
                        Text("Releases are published on GitHub; this looks "
                            + "there and offers what it finds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Button("Check Now\u{2026}") { updates.check() }
                    .disabled(!updates.canCheck)
            }

            Section("Closing") {
                Toggle(isOn: $confirmClose) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask before closing a live session")
                        Text("A tab with something still running on it asks first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Section("Where things are") {
                PathRow(label: "Host list", path: storePath)
                PathRow(label: "ssh options", path: configPath)
                Text("The list is this app's own. The options file is yours to "
                    + "edit; this window follows along.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

/// What a new terminal comes up looking like.
struct TerminalSettingsPane: View {
    @AppStorage("defaultFontSize") private var fontSize = 12.0
    @AppStorage("terminalTheme") private var theme = Themes.systemName

    var body: some View {
        Form {
            Section("Text") {
                LabeledContent("Size") {
                    HStack(spacing: 12) {
                        Slider(value: $fontSize, in: 9...24, step: 1)
                            .frame(width: 180)
                        Text(fontSize.formatted(.number.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
                Text("New sessions start at this size. ⌘+ and ⌘- change the one in front.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Colours") {
                Picker("Palette", selection: $theme) {
                    ForEach(Themes.names, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: theme) { _, _ in
                    NotificationCenter.default.post(name: .shellhandThemeChanged, object: nil)
                }
                if let palette = Themes.named(theme) {
                    PaletteSwatch(palette: palette)
                }
                Text(Themes.named(theme) == nil
                    ? "The terminal's own colours. Your settings file can add palettes under themes."
                    : "Open terminals repaint as soon as you choose. Going back to System takes a new one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

/// Moving files about.
struct FilesSettingsPane: View {
    @AppStorage("transferWidth") private var transferWidth = TransferQueue.defaultWidth

    var body: some View {
        Form {
            Section("Transfers") {
                Stepper(value: $transferWidth, in: TransferQueue.widths) {
                    LabeledContent("At once", value: "\(transferWidth)")
                }
                .onChange(of: transferWidth) { _, now in
                    Task { await Core.shared.setTransferWidth(now) }
                }
                Text("The rest wait their turn. More at once share the same "
                    + "connection, so each one takes longer to arrive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

/// A path with a way to get to it, which on a Mac means Finder.
struct PathRow: View {
    let label: String
    let path: String

    /// The path under its name rather than beside it. Beside it, a
    /// `LabeledContent` wrapped the long one onto a second line and left the
    /// short one on the first, so two rows of the same kind did not match.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(shown)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    // From the front: the end is the file, which is the part
                    // that says which of the two this is.
                    .truncationMode(.head)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .help(path)
            }
            Spacer(minLength: 4)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reveal \(label) in Finder")
            .help("Reveal in Finder")
            .disabled(!FileManager.default.fileExists(atPath: path))
        }
    }

    private var shown: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// The sixteen colours, so a name is not the only thing to go on.
struct PaletteSwatch: View {
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(SwiftUI.Color(nsColor: NSColor(palette.ansi[row * 8 + column])))
                            .frame(width: 16, height: 12)
                    }
                }
            }
        }
        .padding(5)
        .background(SwiftUI.Color(nsColor: NSColor(palette.background)),
                    in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5).strokeBorder(.separator)
        }
    }
}
