import AppKit
import GhostshotCore

/// A resident stub whose only job is to start Ghostshot again after Right ⇧ ⇧
/// has quit it. Ghostshot itself cannot do this: once it exits there is no
/// process left to watch the keyboard.
///
/// It listens for the same gesture that takes a screenshot — Right ⌘ ⌘ — and
/// acts on it only while Ghostshot is not running, so there is no new gesture
/// to remember and no conflict with the running app.
final class LauncherDelegate: NSObject, NSApplicationDelegate {
    private var tap: EventTapController?

    private static let appBundleID = "com.ghostshot.app"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--launch-now` starts Ghostshot and exits: the one way to check the
        // launcher end to end without a keyboard.
        if CommandLine.arguments.contains("--launch-now") {
            launchAppIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
            return
        }

        // It is a login agent, so it starts before anyone can grant it anything.
        // Waiting beats exiting: launchd would just restart it into the same
        // failure, and the grant needs no relaunch once it arrives.
        if startTap() {
            fputs("ghostshot-launcher: listening for Right Command double taps.\n", stderr)
        } else {
            fputs("ghostshot-launcher: waiting for Accessibility permission.\n", stderr)
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard self?.startTap() == true else { return }
                timer.invalidate()
                fputs("ghostshot-launcher: Accessibility granted, listening.\n", stderr)
            }
        }
    }

    /// Returns false while Accessibility is missing — the one thing that makes a
    /// tap impossible and is worth retrying.
    private func startTap() -> Bool {
        guard tap == nil else { return true }
        guard EventTapController.ensureAccessibilityPermission() else { return false }

        let windowMs = Int((try? ConfigStore.defaultStore().loadConfig().doubleTapWindowMs)
            ?? Config.defaults.doubleTapWindowMs)

        let controller = EventTapController(doubleTapWindowMs: windowMs) { [weak self] action in
            guard action == .capture else { return }
            self?.launchAppIfNeeded()
        }
        guard controller.start() else { return false }
        tap = controller
        return true
    }

    private func launchAppIfNeeded() {
        guard NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.appBundleID).isEmpty
        else { return }

        // Ghostshot.app sits next to GhostshotLauncher.app, in the checkout.
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Ghostshot.app", isDirectory: true)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                fputs("ghostshot-launcher: could not open \(appURL.path): \(error)\n", stderr)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = LauncherDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
