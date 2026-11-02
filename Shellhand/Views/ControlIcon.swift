import AppKit
import SwiftUI

extension ShapeStyle where Self == SwiftUI.Color {
    /// An icon in a borderless button, in the colours AppKit draws a
    /// control's text in: black while it can act, as a menu beside it is, and
    /// its grey while it cannot. Borderless, the icons were drawn mid-grey
    /// when live — 128 in SFTP's header, 124 for Settings' Reveal in Finder —
    /// nearer greyed than live beside the menus' black. A hierarchical style
    /// changed nothing, since `.primary` inside a borderless button is the
    /// button's own grey, while `.tertiary` drew the greyed ones fainter than
    /// a greyed menu.
    static func controlIcon(_ live: Bool) -> SwiftUI.Color {
        SwiftUI.Color(nsColor: live ? .controlTextColor : .disabledControlTextColor)
    }
}
