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
/// matter of memory. So the footer button says Done rather than Save, on
/// Return, and Escape closes it the same way: either leaves nothing undone.
/// This comment said Escape was Done before anything made it so.
struct PalettePicker: View {
    /// The host's own choice: a palette's name, or empty for inherited.
    let chosen: String
    /// What inheriting would give, in words — `Effective.inheritedPalette`,
    /// so this and the host editor say the same thing. Nil where there is
    /// nothing to inherit from, which is Settings: the bottom of the chain.
    let inherited: String?
    /// The palette inheriting resolves to, for the row's own swatch.
    let inheritedPalette: Palette?
    let onChoose: (String) -> Void
    /// How tall it is, from its rows and the room in the window it opens over.
    var height: CGFloat = PalettePicker.height(rows: Themes.names.count + 1, in: nil)

    @Environment(\.dismiss) private var dismiss

    /// A palette's row: its swatch's 48, the row's padding and the gap.
    nonisolated static let rowHeight: CGFloat = 64

    /// The rest of the sheet: the list's padding less its last row's gap,
    /// 22, the divider, 1, and Done's bar, 52 — a button 24pt tall on macOS
    /// 26 with 14 above and below it. Counted as 48, the list stood 3pt
    /// short of its rows and scrolled: 10pt under the last palette against
    /// 11.5 over the first.
    nonisolated static let chrome: CGFloat = 75

    /// How tall the picker is for `rows` rows over a window with this much
    /// room below its toolbar: tall enough for every row where that fits,
    /// and otherwise within the room less a margin, the palettes scrolling in
    /// what is left — never under 240 — and ending partway down a row, so
    /// the one cut off says the list goes on. Settings opens 500 tall and
    /// goes down to 420, and a 460 sheet hung its Done below the window's
    /// edge. It was 460 wherever there was room, tall enough for the palettes
    /// that ship but not for the inherit row above them, which pushed the
    /// last one out of sight; and cut on a row's edge, Settings showed five
    /// palettes of six with nothing to say there was a sixth.
    nonisolated static func height(rows: Int, in room: CGFloat?) -> CGFloat {
        let needed = chrome + rowHeight * CGFloat(rows)
        guard let room, needed > room - 40 else { return needed }
        let whole = ((room - 40 - chrome) / rowHeight - 0.5).rounded(.down)
        return max(240, chrome + rowHeight * (whole + 0.5))
    }

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
        .frame(width: DialogSize.medium, height: height)
        .onExitCommand { dismiss() }
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
            if let inherited { row(name: "", title: inherited, palette: inheritedPalette) }
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

/// A palette shown as itself, opening the picker: how every place that
/// chooses one does it. The inspector had this, and the host editor, the
/// group editor and Settings offered a menu of names — in the one choice
/// that is about what something looks like.
/// A menu's arrows in a round bezel, as a pop-up menu draws its own — Font's
/// in Settings — for the controls that draw a menu's value themselves
/// (`PaletteChoice`, `AgentChoice`): bare and grey, the swatch's read as
/// another kind of control beside a menu. And drawn as that bezel is,
/// measured off it: its fill, where `.quaternary` was a shade darker; its
/// arrows black, where a grouped form greyed them; 12.5pt after the words,
/// where they sat 8pt after; and 3.5pt in from the row's end, where the
/// circle stood 3.5pt right of the menu's.
struct MenuArrows: View {
    var body: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 20, height: 20)
            .background(SwiftUI.Color(nsColor: .secondarySystemFill), in: Circle())
            .padding(.leading, 4.5)
            .padding(.trailing, 3.5)
    }
}

struct PaletteChoice: View {
    /// A palette's name, or empty for whatever is inherited.
    let chosen: String
    /// What inheriting gives, in words; nil where there is nothing to inherit.
    let inherited: String?
    /// The palette inheriting gives, for its swatch.
    let inheritedPalette: Palette?
    /// What inheriting gives in two parts, for a label that says where from
    /// in grey under or beside the palette, as the inspector's other rows
    /// do; without it the label is the inherit row's sentence, which in the
    /// inspector's column wrapped a word to a line.
    var inheritedParts: (name: String, from: String)?
    let onChoose: (String) -> Void

    /// The picker open, with the height it opens at — carried in the
    /// binding, since a sheet built from `isPresented` reads state set in
    /// the same gesture as it was before.
    @State private var choosing: Opening?

    private struct Opening: Identifiable {
        let id = UUID()
        let height: CGFloat
    }

    var body: some View {
        Button {
            choosing = Opening(height: PalettePicker.height(
                rows: Themes.names.count + (inherited == nil ? 0 : 1),
                in: NSApp.keyWindow?.contentLayoutRect.height))
        } label: {
            // The words beside the swatch while each keeps its line, and
            // under it where they would not: in the inspector's column the
            // arrows' bezel left a palette's name too little room, and
            // "Gruvbox Dark from Production" went down a word to a line.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: parts == nil ? .center : .top, spacing: 7) {
                    swatch
                    words(stacked: false)
                    arrows
                }
                HStack(alignment: .top, spacing: 7) {
                    swatch
                    words(stacked: true)
                    arrows
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        swatch
                        arrows
                    }
                    words(stacked: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Its words' baseline said, for a form's row to set its label on:
        // a line centred on the swatch has it this far below the centre. The
        // form lined "Colours" up 1.5pt above "System" without it. Stacked,
        // in the inspector, the row lines up by top instead.
        .alignmentGuide(.firstTextBaseline) { d in
            parts == nil ? d[VerticalAlignment.center] + Self.centreToBaseline : d[.firstTextBaseline]
        }
        .accessibilityLabel("Colours: \(title)")
        .sheet(item: $choosing) { opening in
            PalettePicker(
                chosen: chosen, inherited: inherited, inheritedPalette: inheritedPalette,
                onChoose: onChoose, height: opening.height)
        }
    }

    /// How far below a line's centre its baseline is, in the body font.
    private static let centreToBaseline: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return (font.ascender + font.descender) / 2
    }()

    private var swatch: some View {
        TerminalMiniature(palette: shown, size: CGSize(width: 34, height: 21))
    }

    private var arrows: some View { MenuArrows() }

    /// The palette's name, and where it comes from beside it or under it.
    @ViewBuilder
    private func words(stacked: Bool) -> some View {
        if let parts {
            if stacked {
                VStack(alignment: .leading, spacing: 1) {
                    Text(parts.name)
                    source(parts.from)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(parts.name)
                    source(parts.from)
                }
            }
        } else {
            // A palette set here reads as set, and one inherited as grey as
            // an inherited field's value: a grouped form greys whatever it
            // is handed, so in both editors a group's own Gruvbox Dark was as
            // grey as one from Production.
            Text(title)
                .foregroundStyle(chosen.isEmpty ? .secondary : .primary)
        }
    }

    private var shown: Palette? { chosen.isEmpty ? inheritedPalette : Themes.named(chosen) }

    private var title: String { chosen.isEmpty ? (inherited ?? "") : chosen }

    /// What inheriting gives in two parts, where it is what is shown.
    private var parts: (name: String, from: String)? { chosen.isEmpty ? inheritedParts : nil }

    /// "from Production", as `ValueRow` says it.
    private func source(_ from: String) -> some View {
        Text("from \(from)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
