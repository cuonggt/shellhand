import SwiftUI

/// The `-o` settings written against one host or one group.
///
/// One per line, because that is how they are written in a config file and
/// how anyone who has set `ServerAliveInterval=30` before expects to type
/// them. They go on the command line ahead of the ones from the settings
/// file, and ssh keeps the first value it is given for a setting — so what is
/// written here about one machine beats what was written once for all of
/// them.
struct SSHOptionsField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ssh options")
            TextEditor(text: $text)
                .font(.caption.monospaced())
                .frame(height: 64)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("ServerAliveInterval=30")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.separator)
                }
            Text("One per line. These beat the settings file's, which apply to everything.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Blank lines and stray spaces are not settings.
    static func parse(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
