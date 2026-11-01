import CoreGraphics
import Observation

/// The room below a window's toolbar, measured where the window is laid out
/// and read by the sheets over it. An object of its own so that resizing the
/// window redraws only a sheet that reads it: held as the window's own state,
/// every step of a resize redrew the whole window, and each redraw hands the
/// menus a new set of actions.
@Observable
final class SheetRoom {
    /// Nil until the window has been laid out.
    var height: CGFloat?
}

/// How tall a sheet over the host window is: what it was measured to need,
/// where the window has that much room below its toolbar, and otherwise the
/// room less a margin.
///
/// A sheet taller than that room hangs off the window's bottom edge, and on a
/// window low on the screen its buttons go with it. The host editor did at the
/// window's default size, 1106×720, once 0.1.7 made it 720 tall; the palette
/// picker did in Settings, which is why `PalettePicker.height` has this shape.
/// What a sheet loses comes out of what scrolls in it.
nonisolated enum SheetHeight {
    /// Left between the sheet's foot and the window's bottom edge.
    static let margin: CGFloat = 16

    /// Below this there is no editor left to show, so over a window shorter
    /// still the sheet hangs rather than shrinking to nothing.
    static let least: CGFloat = 400

    /// `wanted` where `room` has it, and never taller than `wanted`. Without a
    /// room to go by, as measured.
    static func fitted(_ wanted: CGFloat, in room: CGFloat?) -> CGFloat {
        guard let room else { return wanted }
        return min(wanted, max(least, room - margin))
    }
}
