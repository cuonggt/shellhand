import SwiftUI

extension View {
    /// Selectable text that is made afresh when its words change.
    ///
    /// A `.textSelection(.enabled)` text comes twice in the accessibility
    /// tree, and changed in place the first copy kept its first words: after
    /// a switch the inspector held the last host's user, address and jump
    /// host there while the screen showed this one's. For text whose words
    /// change while it stays on screen; text that never changes can take
    /// `.textSelection(.enabled)` as it is.
    func selectable(_ words: String) -> some View {
        textSelection(.enabled).id(words)
    }
}
