import AppKit
import Foundation
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permissionDenied(String)
    case noDisplay
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let detail):
            return """
            Screen Recording permission is not granted.

            System Settings > Privacy & Security > Screen & System Audio Recording
            Enable Ghostshot, then quit and relaunch the app.

            (\(detail))
            """
        case .noDisplay:
            return "No display found to capture."
        case .encodingFailed:
            return "Could not encode the screenshot as PNG."
        }
    }
}

enum ScreenCapturer {
    /// Captures the display under the mouse pointer, omitting our own windows.
    static func capture(excludingWindowNumbers: [Int]) async throws -> Data {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied(error.localizedDescription)
        }

        guard let display = displayUnderCursor(in: content.displays) else {
            throw CaptureError.noDisplay
        }

        let excluded = content.windows.filter { excludingWindowNumbers.contains(Int($0.windowID)) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodingFailed
        }
        return png
    }

    private static func displayUnderCursor(in displays: [SCDisplay]) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main

        if let screenNumber = screen?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber {
            if let match = displays.first(where: { $0.displayID == screenNumber.uint32Value }) {
                return match
            }
        }
        return displays.first
    }
}
