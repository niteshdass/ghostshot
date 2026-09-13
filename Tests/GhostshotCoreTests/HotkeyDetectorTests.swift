import Foundation
import Testing
@testable import GhostshotCore

@Suite struct HotkeyDetectorTests {
    private func tap(_ d: HotkeyDetector, _ key: ModifierKey, at t: TimeInterval) -> HotkeyAction? {
        _ = d.handle(.modifierDown(key), at: t)
        return d.handle(.modifierUp(key), at: t + 0.01)
    }

    @Test func twoTapsInsideWindowFireCapture() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        #expect(tap(d, .rightCommand, at: 0.0) == nil)
        #expect(tap(d, .rightCommand, at: 0.2) == .capture)
    }

    @Test func rightShiftDoubleTapQuits() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        #expect(tap(d, .rightShift, at: 0.0) == nil)
        #expect(tap(d, .rightShift, at: 0.2) == .quit)
    }

    /// Typing a capital letter holds Shift across a key press, which must never quit.
    @Test func shiftHeldForACapitalLetterDoesNotQuit() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        #expect(tap(d, .rightShift, at: 0.0) == nil)
        _ = d.handle(.modifierDown(.rightShift), at: 0.1)
        _ = d.handle(.otherKeyDown, at: 0.11)
        #expect(d.handle(.modifierUp(.rightShift), at: 0.12) == nil)
        // The contaminated tap also cleared the pending first tap.
        #expect(tap(d, .rightShift, at: 0.2) == nil)
    }

    @Test func twoTapsOutsideWindowFireNothing() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        #expect(tap(d, .rightCommand, at: 0.0) == nil)
        #expect(tap(d, .rightCommand, at: 0.6) == nil)
    }

    @Test func thirdTapDoesNotFireAgain() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        #expect(tap(d, .rightCommand, at: 0.0) == nil)
        #expect(tap(d, .rightCommand, at: 0.1) == .capture)
        #expect(tap(d, .rightCommand, at: 0.2) == nil)
    }

    @Test func rightOptionTogglesPanelAndRightControlResets() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        #expect(tap(d, .rightOption, at: 0.0) == nil)
        #expect(tap(d, .rightOption, at: 0.1) == .togglePanel)

        #expect(tap(d, .rightControl, at: 1.0) == nil)
        #expect(tap(d, .rightControl, at: 1.1) == .resetConversation)
    }

    @Test func differentModifiersDoNotCombine() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        #expect(tap(d, .rightCommand, at: 0.0) == nil)
        #expect(tap(d, .rightOption, at: 0.1) == nil)
    }

    @Test func realShortcutIsNotATap() {
        // Cmd+C: hold right command, press C, release right command.
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        _ = d.handle(.modifierDown(.rightCommand), at: 0.0)
        _ = d.handle(.otherKeyDown, at: 0.05)
        #expect(d.handle(.modifierUp(.rightCommand), at: 0.1) == nil)
        // A genuine tap right after must still count as only the FIRST tap.
        #expect(tap(d, .rightCommand, at: 0.2) == nil)
    }

    @Test func upWithoutDownIsIgnored() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        #expect(d.handle(.modifierUp(.rightCommand), at: 0.0) == nil)
        #expect(tap(d, .rightCommand, at: 0.1) == nil)
    }
}
