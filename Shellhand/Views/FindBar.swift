import SwiftTerm
import SwiftUI

/// Searching the scrollback, over SwiftTerm's own `findNext` and
/// `findPrevious`, which scroll the match into view as they go. What is being
/// looked for belongs to the session, so the Find menu can drive this bar and
/// the term survives a trip to another tab.
struct FindBar: View {
    let session: TerminalSession
    @State private var summary = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in scrollback", text: Binding(
                get: { session.findTerm },
                set: { session.findTerm = $0 }))
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { step { session.findNext() } }
                .onChange(of: session.findTerm) { _, _ in summary = session.findSummary }
            if !summary.isEmpty {
                Text(summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Button { step { session.findPrevious() } } label: { Image(systemName: "chevron.up") }
                .accessibilityLabel("Previous match")
                .help("Previous match (⇧⌘G)")
            Button { step { session.findNext() } } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Next match")
                .help("Next match (⌘G)")
            Button { session.findOpen = false } label: { Image(systemName: "xmark") }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close find")
                .help("Close")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .onAppear {
            focused = true
            summary = session.findSummary
        }
    }

    private func step(_ move: () -> Bool) {
        _ = move()
        summary = session.findSummary
    }
}
