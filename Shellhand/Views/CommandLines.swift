import SwiftUI

/// What will run, one argument a line, as ssh receives it — the inspector's
/// What will run and the host editor's foot alike. Drawn as the quoted line,
/// a jump chain was a wall of `'"'"'` cut in the middle of a path; the line
/// stays what Copy gives and what accessibility reads.
struct CommandLines: View {
    let preview: HostPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if preview.argv.isEmpty {
                Text("Working it out…").foregroundStyle(.secondary)
            } else {
                ForEach(Array(preview.lines.enumerated()), id: \.offset) { index, line in
                    // A space's width apart, the value in a column of its
                    // own, so a long one wraps under itself.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !line.option.isEmpty { Text(line.option) }
                        Text(line.value)
                    }
                    .padding(.leading, index == 0 ? 0 : 14)
                }
            }
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(preview.argv.isEmpty ? "Working it out" : preview.command)
    }
}
