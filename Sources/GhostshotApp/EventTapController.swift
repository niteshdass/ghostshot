import AppKit
import CoreGraphics
import Foundation
import GhostshotCore

/// Watches modifier keys with a passive tap and reports double-tap gestures.
///
/// The tap is `.listenOnly`: it can never swallow, delay, or alter a keystroke,
/// so normal typing is unaffected even if this code misbehaves.
final class EventTapController {
    private var detector: HotkeyDetector
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onAction: (HotkeyAction) -> Void

    /// Carbon virtual key codes for the right-hand modifiers.
    private static let rightCommandKeyCode: Int64 = 54
    private static let rightOptionKeyCode: Int64 = 61
    private static let rightControlKeyCode: Int64 = 62

    /// Device-dependent flag bits, which distinguish right from left.
    private static let rightCommandMask: UInt64 = 0x10
    private static let rightOptionMask: UInt64 = 0x40
    private static let rightControlMask: UInt64 = 0x2000

    init(doubleTapWindowMs: Int, onAction: @escaping (HotkeyAction) -> Void) {
        self.detector = HotkeyDetector(doubleTapWindowMs: Double(doubleTapWindowMs))
        self.onAction = onAction
    }

    /// Returns false when Accessibility permission has not been granted.
    @discardableResult
    func start() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let unmanaged = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
                controller.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: unmanaged
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    /// macOS disables a tap that is slow to respond; re-enable it rather than
    /// silently losing the hotkey for the rest of the session.
    private func reenableIfDisabled(type: CGEventType) -> Bool {
        guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return false }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if reenableIfDisabled(type: type) { return }

        let now = ProcessInfo.processInfo.systemUptime
        var hotkeyEvent: HotkeyEvent?

        switch type {
        case .keyDown:
            hotkeyEvent = .otherKeyDown
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags.rawValue
            guard let key = Self.modifierKey(forKeyCode: keyCode) else { return }
            let isDown = (flags & Self.mask(for: key)) != 0
            hotkeyEvent = isDown ? .modifierDown(key) : .modifierUp(key)
        default:
            return
        }

        guard let hotkeyEvent else { return }
        if let action = detector.handle(hotkeyEvent, at: now) {
            DispatchQueue.main.async { [onAction] in
                onAction(action)
            }
        }
    }

    private static func modifierKey(forKeyCode code: Int64) -> ModifierKey? {
        switch code {
        case rightCommandKeyCode: return .rightCommand
        case rightOptionKeyCode: return .rightOption
        case rightControlKeyCode: return .rightControl
        default: return nil
        }
    }

    private static func mask(for key: ModifierKey) -> UInt64 {
        switch key {
        case .rightCommand: return rightCommandMask
        case .rightOption: return rightOptionMask
        case .rightControl: return rightControlMask
        }
    }

    /// Prompts once for Accessibility permission if it has not been granted.
    static func ensureAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
