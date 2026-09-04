import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory keeps the process out of the Dock, the menu bar, and Cmd-Tab.
app.setActivationPolicy(.accessory)
app.run()
