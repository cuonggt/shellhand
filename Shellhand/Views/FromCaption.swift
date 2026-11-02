import AppKit
import SwiftUI

/// "from Production" beside a field in an editor, in a column as wide as
/// the widest such caption the editor shows, so what stands before them —
/// a field, or the jump host's field and its menu — ends at one edge. Each
/// at its own width, the jump host's field ended 2–2.5pt short of the key's
/// above it, near enough a line to read as a slip.
///
/// The column is the widest caption itself, laid out unseen under this one,
/// so it is as wide as SwiftUI draws it rather than as a measure guesses.
struct FromCaption: View {
    /// Where the value comes from, a group's name or path.
    let from: String
    /// Where the editor's other captions say theirs come from, which with
    /// this one's set the column.
    let among: [String]
    let help: String

    var body: some View {
        Text(Self.widest(among + [from]))
            .font(.caption)
            .lineLimit(1)
            .hidden()
            .overlay(alignment: .leading) {
                Text(Self.caption(from))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(help)
            }
    }

    static func caption(_ from: String) -> String { "from \(from)" }

    /// The caption of `froms` that stands widest in the font they are drawn
    /// in: only to choose which one sets the column.
    static func widest(_ froms: [String]) -> String {
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        return froms.map(caption).max { width($0) < width($1) } ?? ""
    }
}
