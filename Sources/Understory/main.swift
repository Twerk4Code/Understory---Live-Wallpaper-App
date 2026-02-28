import AppKit

// Create and run the application as an accessory (menu-bar only, no Dock icon)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
