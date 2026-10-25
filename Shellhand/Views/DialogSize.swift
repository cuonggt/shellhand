import SwiftUI

/// How wide a dialog is, decided by what it holds.
///
/// Three widths rather than the seven this app grew: 420, 460, 480, 500, 520,
/// 560, 580, 620 and 820 all appeared, each picked by hand for whatever that
/// sheet needed on the day it was written. Opening two in a row moved the
/// window sideways under the pointer, which is the kind of thing nobody
/// reports and everybody feels.
///
/// **Width only.** Height stays with each dialog, because a width that jumps
/// between sheets is jarring and a height that does is not — and a height
/// handed down from a grid clips. Both times a height was guessed here rather
/// than measured, it cut off the last row.
enum DialogSize {
    /// One question and its answer.
    static let small: CGFloat = 460

    /// One record, one task, or a plain list.
    static let medium: CGFloat = 560

    /// A list beside the thing it selects.
    static let large: CGFloat = 820
}

// Quick Connect is deliberately not in here. It is a palette, not a dialog:
// ⌘K, type, return — the shape Spotlight has, where a footer would be noise.
// What a palette does owe you is a way out, which is `onExitCommand`.
