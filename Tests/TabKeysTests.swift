import AppKit
import Testing
@testable import Shellhand

/// Which keys `StepsTabs` takes for the strip, asked of real key events
/// rather than of a description of them.
///
/// Deliberately no `Host` here: `AppKit` brings `Foundation.Host` with it.
@MainActor
@Suite("Tab keys")
struct TabKeysTests {
    private let tab: UInt16 = 48

    private func key(
        _ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, _ characters: String = "\t"
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
    }

    private func offset(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags,
                        _ characters: String = "\t") -> Int? {
        key(keyCode, flags, characters).flatMap(StepsTabs.offset(for:))
    }

    @Test("⌃⇥ is the next tab and ⌃⇧⇥ the previous")
    func controlTab() {
        #expect(key(tab, [.control]) != nil, "no key event could be made to ask with")
        #expect(offset(tab, [.control]) == 1)
        #expect(offset(tab, [.control, .shift]) == -1)
    }

    /// Caps Lock is a state, not a chord: somebody with it on still means ⌃⇥.
    @Test("Caps Lock does not get in the way")
    func capsLock() {
        #expect(offset(tab, [.control, .capsLock]) == 1)
        #expect(offset(tab, [.control, .shift, .capsLock]) == -1)
    }

    /// Everything else belongs to something else: Tab alone is the shell's
    /// completion, ⌃⌥⇥ and ⌘⇥ are other chords, and ⌃ on any other key is
    /// the terminal's.
    @Test("Tab alone, other chords and other keys are left alone")
    func leftAlone() {
        #expect(offset(tab, []) == nil)
        #expect(offset(tab, [.shift]) == nil)
        #expect(offset(tab, [.control, .option]) == nil)
        #expect(offset(tab, [.command]) == nil)
        #expect(offset(0, [.control], "a") == nil)
    }
}
