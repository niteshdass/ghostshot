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
