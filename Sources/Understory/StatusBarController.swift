import AppKit

// MARK: - StatusBarController
// NSStatusBar item — secondary access point for non-notch Macs and power users.
// Now shows the notch panel instead of a separate settings window.
final class StatusBarController: NSObject {

    private var statusItem: NSStatusItem!
    private weak var wallpaperManager: WallpaperManager?
    private var pauseMenuItem: NSMenuItem!

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        super.init()
        setupStatusItem()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Try custom menu bar icon from bundle Resources
            if let iconPath = Bundle.main.path(forResource: "MenuIcon", ofType: "png"),
               let image = NSImage(contentsOfFile: iconPath) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else if let image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Understory") {
                // Fallback to SF Symbol
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "🌿"
            }
        }

        let menu = NSMenu()

        // Show Panel
        let panelItem = NSMenuItem(title: "Show Panel", action: #selector(showPanel), keyEquivalent: ",")
        panelItem.target = self
        menu.addItem(panelItem)

        menu.addItem(.separator())

        // Pause / Resume
        pauseMenuItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Understory", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func showPanel() {
        // Ask the AppDelegate to show the notch panel
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showNotchPanelFromMenuBar()
        }
    }

    @objc private func togglePause() {
        wallpaperManager?.togglePause()
        let paused = wallpaperManager?.isPaused ?? false
        pauseMenuItem.title = paused ? "Resume" : "Pause"
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
