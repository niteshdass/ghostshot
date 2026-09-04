import Foundation

public enum ModifierKey: Equatable, Hashable, Sendable {
    case rightCommand
    case rightOption
    case rightControl
}

public enum HotkeyEvent: Equatable, Sendable {
    case modifierDown(ModifierKey)
    case modifierUp(ModifierKey)
    /// Any non-modifier key going down. Used to disqualify real shortcuts like Cmd+C.
    case otherKeyDown
}

public enum HotkeyAction: Equatable, Sendable {
    case capture
    case togglePanel
    case resetConversation
}

public final class HotkeyDetector {
    private let window: TimeInterval
    private var heldSince: [ModifierKey: TimeInterval] = [:]
    private var contaminated: Set<ModifierKey> = []
    private var lastTapKey: ModifierKey?
    private var lastTapAt: TimeInterval?

    public init(doubleTapWindowMs: Double = 300) {
        self.window = doubleTapWindowMs / 1000.0
    }

    public func handle(_ event: HotkeyEvent, at now: TimeInterval) -> HotkeyAction? {
        switch event {
        case .modifierDown(let key):
            heldSince[key] = now
            contaminated.remove(key)
            return nil

        case .otherKeyDown:
            // Every modifier currently held was part of a real shortcut, not a tap.
            for key in heldSince.keys { contaminated.insert(key) }
            return nil

        case .modifierUp(let key):
            guard heldSince.removeValue(forKey: key) != nil else { return nil }

            if contaminated.remove(key) != nil {
                lastTapKey = nil
                lastTapAt = nil
                return nil
            }

            if lastTapKey == key, let previous = lastTapAt, now - previous <= window {
                lastTapKey = nil
                lastTapAt = nil
                return Self.action(for: key)
            }

            lastTapKey = key
            lastTapAt = now
            return nil
        }
    }

    private static func action(for key: ModifierKey) -> HotkeyAction {
        switch key {
        case .rightCommand: return .capture
        case .rightOption: return .togglePanel
        case .rightControl: return .resetConversation
        }
    }
}
