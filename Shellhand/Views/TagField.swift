import SwiftUI

/// Tags as things you can see and take off, rather than a line of commas.
///
/// The value is still the comma form — that is what `Tags.clean` reads and
/// what gets saved — so nothing below this knows the difference. What changes
/// is that the tags on a host are countable at a glance and one of them can be
/// removed without editing a string around it.
struct TagField: View {
    @Binding var text: String
    /// What has been typed and not yet made a tag. The editor holds it, so
    /// that Save counts it as `Tags.saved` says.
    @Binding var typing: String
    /// Tags already in use anywhere, to pick from rather than retype.
    let known: [String]

    private var tags: [String] { Tags.clean(text) }

    /// Where AppKit puts a borderless field's first baseline, from its top,
    /// in the body font: what the typing field says it has. Asked from
    /// inside the flow, it answered 8pt down a 22pt field, above its words,
    /// where its words sit 13pt down.
    private static let fieldBaseline: CGFloat = {
        let probe = NSTextField(string: "")
        probe.isBezeled = false
        probe.font = .systemFont(ofSize: NSFont.systemFontSize)
        probe.sizeToFit()
        return probe.firstBaselineOffsetFromTop
    }()

    var body: some View {
        // On the text's line, the row's label with it: the form lines a
        // label up with the baseline of what is beside it, and this said
        // none, or one it took from the typing field 5pt too high — "Tags"
        // stood above "add a tag" either way.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            FlowLayout(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    TagToken(tag: tag) { remove(tag) }
                }
                // The same words with tags or without: "web, eu" named two
                // tags the list already holds, in the comma form the field
                // turns into tokens.
                TextField("", text: $typing, prompt: Text("add a tag"))
                    .textFieldStyle(.plain)
                    // A grouped form's rows right-align their fields, and
                    // that reaches in here: "add a tag" floated off the last
                    // token, and "web, eu" sat 25pt inside an empty box.
                    .multilineTextAlignment(.leading)
                    .frame(minWidth: 72)
                    .alignmentGuide(.firstTextBaseline) { d in d[.top] + Self.fieldBaseline }
                    .onSubmit { commit() }
                    // One rule for reading tags, and it says a comma, a
                    // semicolon, a bar or a space all separate — so typing any
                    // of them finishes the tag, the same as pressing return.
                    .onChange(of: typing) { _, now in
                        if now.contains(where: Tags.separates) { commit() }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(nsColor: .separatorColor)))

            Menu {
                if known.isEmpty { Text("No tags yet") }
                ForEach(known, id: \.self) { tag in
                    let on = tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                    Button {
                        text = Tags.text(on
                            ? tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
                            : tags + [tag])
                    } label: {
                        Label(tag, systemImage: on ? "checkmark" : "tag")
                    }
                }
            } label: {
                Image(systemName: "tag")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Tags already in use")
            .help("Tags already in use")
        }
    }

    /// Takes whatever has been typed and makes tags of it.
    private func commit() {
        let added = Tags.clean(typing)
        typing = ""
        guard !added.isEmpty else { return }
        // `Tags.clean` drops repeats, so a tag added twice stays once.
        text = Tags.text(tags + added)
    }

    private func remove(_ tag: String) {
        text = Tags.text(tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame })
    }
}

private struct TagToken: View {
    let tag: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(tag).font(.caption)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.18), in: Capsule())
    }
}

/// Lays its children in rows, wrapping when the next one would not fit.
///
/// A host with six tags should not push a form row off the side of the dialog,
/// and SwiftUI has no flowing stack of its own.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > limit {
                widest = max(widest, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(
            width: limit == .infinity ? max(widest, 0) : limit,
            height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    /// The first line's text baseline, its first view's, which sits at the
    /// top: without it the flow said no baseline at all, and a label lined
    /// up with it stood off the text.
    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout ()
    ) -> CGFloat? {
        guard guide == .firstTextBaseline, let first = subviews.first else { return nil }
        let size = first.sizeThatFits(.unspecified)
        return bounds.minY + first.dimensions(in: ProposedViewSize(size))[.firstTextBaseline]
    }
}
