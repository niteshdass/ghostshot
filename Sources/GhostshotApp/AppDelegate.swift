import AppKit
import Foundation
import GhostshotCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: OverlayPanel?
    private var coordinator: AnswerCoordinator?
    private var eventTap: EventTapController?
    private let store = ConfigStore.defaultStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config: Config
        do {
            try store.writeDefaultConfigIfMissing()
            config = try store.loadConfig()
        } catch {
            fputs("ghostshot: could not read \(store.configURL.path): \(error)\n", stderr)
            NSApp.terminate(nil)
            return
        }

        let state = store.loadState()
        let panel = OverlayPanel(initialFrame: AppDelegate.parseFrame(state.panelFrame))
        panel.onFrameChange = { [store] frame in
            var state = store.loadState()
            state.panelFrame = "\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height)"
            store.saveState(state)
        }
        self.panel = panel

        let coordinator = AnswerCoordinator(config: config, store: store, panel: panel)
        self.coordinator = coordinator

        guard EventTapController.ensureAccessibilityPermission() else {
            panel.setAnswer(
                """
                Accessibility permission is required for the hotkey.

                System Settings > Privacy & Security > Accessibility
                Enable Ghostshot, then quit and relaunch the app.
                """,
                status: "permission needed"
            )
            panel.showWithoutFocus()
            return
        }

        let tap = EventTapController(
            doubleTapWindowMs: Int(config.doubleTapWindowMs)
        ) { [weak coordinator] action in
            coordinator?.handle(action)
        }
        self.eventTap = tap

        if tap.start() {
            panel.setAnswer(
                """
                Ghostshot is running.

                  Right ⌘ ⌘   capture the screen and ask
                  Right ⌥ ⌥   show or hide this panel
                  Right ⌃ ⌃   start a fresh conversation

                This panel is invisible to screen sharing and recording.
                """,
                status: "ready"
            )
            panel.showWithoutFocus()
        } else {
            panel.setAnswer(
                "Could not install the keyboard tap. Check Accessibility permission and relaunch.",
                status: "hotkey unavailable"
            )
            panel.showWithoutFocus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap?.stop()
    }

    /// "x,y,w,h" as written by `onFrameChange`.
    static func parseFrame(_ string: String?) -> CGRect? {
        guard let parts = string?.split(separator: ","), parts.count == 4 else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == 4, numbers[2] > 100, numbers[3] > 100 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }
}
