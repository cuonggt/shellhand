import SwiftUI

/// A palette shown as a scrap of terminal, rather than as its name.
///
/// **It replaced a chart of all sixteen ANSI colours**, which Settings used
/// to show. That answers "what is in this palette", which is a fair question
/// and not the one anybody is asking: what you want when choosing is what a
/// terminal will look like. Both existed for a few hours and the chart is
/// gone, so there is one way a palette is drawn in this app.
///
/// **The name of a palette says almost nothing**, which is the whole reason
/// this exists: "Gruvbox Dark" and "Tomorrow Night" are both dark and
/// nothing in either name says which one is warm. A few bars in the
/// palette's own colours answer in a glance what a list of names cannot
/// answer at all.
///
/// The bars are deliberately not a real terminal's output. Something that
/// looked like a prompt would invite reading, and at this size there is
/// nothing to read — what is being compared is colour against colour.
struct TerminalMiniature: View {
    let palette: Palette?
    var size = CGSize(width: 76, height: 48)

    /// What the **System** palette is drawn as, since there is nothing to
    /// ask: SwiftTerm's own colours, left alone. The background is taken
    /// from a screenshot of one rather than guessed.
    private static let systemBackground = SwiftUI.Color.black
    private static let systemInk = SwiftUI.Color(white: 0.85)

    private func colour(_ index: Int) -> SwiftUI.Color {
        guard let palette, palette.isComplete else { return Self.systemInk }
        return SwiftUI.Color(nsColor: NSColor(palette.ansi[index]))
    }

    private var background: SwiftUI.Color {
        guard let palette else { return Self.systemBackground }
        return SwiftUI.Color(nsColor: NSColor(palette.background))
    }

    private var foreground: SwiftUI.Color {
        guard let palette else { return Self.systemInk }
        return SwiftUI.Color(nsColor: NSColor(palette.foreground))
    }

    private var cursor: SwiftUI.Color {
        guard let palette else { return Self.systemInk }
        return SwiftUI.Color(nsColor: NSColor(palette.cursor))
    }

    /// Widths as fractions of the swatch, so the rows read as lines of
    /// output of different lengths rather than a bar chart.
    private var rows: [[(SwiftUI.Color, CGFloat)]] {
        [
            [(colour(2), 0.46), (foreground, 0.30)],
            [(colour(4), 0.22), (foreground, 0.34), (colour(3), 0.18)],
            [(colour(6), 0.30), (foreground, 0.22)],
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: size.height * 0.11) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: size.width * 0.05) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, bar in
                        Capsule().fill(bar.0)
                            .frame(width: size.width * bar.1, height: size.height * 0.1)
                    }
                }
            }
            HStack(spacing: size.width * 0.05) {
                Capsule().fill(colour(1))
                    .frame(width: size.width * 0.18, height: size.height * 0.1)
                // The cursor, which is the one part of a terminal that is
                // always the same shape, so it is the part that makes this
                // read as a terminal at all.
                RoundedRectangle(cornerRadius: 1)
                    .fill(cursor)
                    .frame(width: size.width * 0.06, height: size.height * 0.14)
            }
        }
        .padding(size.width * 0.09)
        .frame(width: size.width, height: size.height, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.separator, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Choosing a palette by looking at it.
///
/// A dialog rather than the menu this replaced, for the reason above: a menu
/// can only offer names. It is `DialogSize.medium`, which the conventions
/// give for a plain list.
///
/// **Choosing applies at once and the sheet stays open.** The point of
/// seeing the colours is seeing them on a terminal, and a sheet that had to
/// be dismissed before anything changed would make comparing two palettes a
/// matter of memory. So the footer button says Done rather than Save, and
/// Escape — which is that button — leaves nothing undone.
struct PalettePicker: View {
    /// The host's own choice: a palette's name, or empty for inherited.
    let chosen: String
    /// What inheriting would give, in words — `Effective.inheritedPalette`,
    /// so this and the host editor say the same thing.
    let inherited: String
    /// The palette inheriting resolves to, for the row's own swatch.
    let inheritedPalette: Palette?
    let onChoose: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { rows.padding(12) }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: DialogSize.medium, height: 460)
    }

    /// The palettes themselves, apart from the sheet around them.
    ///
    /// **Not private, so that a test can draw them**, which is the same seam
    /// `TerminalSession.watch()` is left open for. Neither a `List` nor a
    /// `ScrollView` can be rendered by `ImageRenderer` — a `List` comes out
    /// as a "cannot render" sign and a `ScrollView` comes out blank — and a
    /// dialog cannot be opened from a script in this app at all, so without
    /// this the one view whose entire job is to be looked at is the one view
    /// nothing could look at.
    ///
    /// A stack rather than a `List` for a reason of its own: the rows carry
    /// their own selected background, which a palette list wants, since the
    /// eye is comparing colours and a `List`'s selection would tint the very
    /// swatch being judged.
    @ViewBuilder var rows: some View {
        LazyVStack(spacing: 2) {
            row(name: "", title: inherited, palette: inheritedPalette)
            ForEach(Themes.names, id: \.self) { name in
                row(name: name, title: name, palette: Themes.named(name))
            }
        }
    }

    private func row(name: String, title: String, palette: Palette?) -> some View {
        Button {
            onChoose(name)
        } label: {
            HStack(spacing: 12) {
                TerminalMiniature(palette: palette)
                Text(title)
                    .foregroundStyle(name == chosen ? AnyShapeStyle(.tint)
                                                    : AnyShapeStyle(.primary))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            // The wash sits behind the row and never over the swatch: the
            // eye is comparing colours, and tinting the thing being judged
            // is the one thing this must not do.
            .background(name == chosen ? AnyShapeStyle(.quaternary)
                                       : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(name == chosen ? [.isSelected] : [])
    }
}
