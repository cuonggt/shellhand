import SwiftUI

/// The pane in front and the tab shown beside it, with a line between them to
/// drag.
///
/// **Not an `HSplitView`.** That is an `NSSplitView`, and it sized each side
/// from the terminal view's own frame — 900pt, from when the view was made —
/// rather than from the window it was in: Show Beside on two terminals
/// widened the window from 1220pt to 2016, past the screen, and putting the
/// one pane back left it there. Laid out here in the room the window already
/// has, the sides never ask it for more. The widths are `Panes.frontWidth`.
struct SideBySide<Front: View, Beside: View>: View {
    /// The front side's share of the width, which dragging the line sets.
    @Binding var share: CGFloat
    @ViewBuilder var front: Front
    @ViewBuilder var beside: Beside

    private static var space: String { "side-by-side" }

    var body: some View {
        GeometryReader { geometry in
            // The line takes a point of its own.
            let width = max(0, geometry.size.width - 1)
            HStack(spacing: 0) {
                front
                    .frame(width: Panes.frontWidth(share: share, of: width))
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .overlay {
                        // Wider than the line it moves, so a pointer finds it.
                        Color.clear
                            .frame(width: 7)
                            .contentShape(Rectangle())
                            .pointerStyle(.columnResize)
                            .gesture(
                                DragGesture(coordinateSpace: .named(Self.space))
                                    .onChanged { drag in
                                        guard width > 0 else { return }
                                        share = min(max(drag.location.x / width, 0), 1)
                                    })
                    }
                beside
                    .frame(maxWidth: .infinity)
            }
            .coordinateSpace(.named(Self.space))
        }
    }
}
