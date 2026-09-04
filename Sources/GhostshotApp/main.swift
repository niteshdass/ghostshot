import AppKit
import Foundation

// Temporary harness for Task 10. Replaced by the real app bootstrap in Task 13.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

Task {
    do {
        let png = try await ScreenCapturer.capture(excludingWindowNumbers: [])
        let url = URL(fileURLWithPath: "/tmp/ghostshot-manual-capture.png")
        try png.write(to: url)
        print("captured \(png.count) bytes to \(url.path)")
    } catch {
        print("capture failed: \(error.localizedDescription)")
    }
    exit(0)
}

app.run()
