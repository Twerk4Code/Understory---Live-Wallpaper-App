import AppKit
import UniformTypeIdentifiers

// MARK: - StatusBarController
// NSStatusBar item — primary access point on Intel Macs, secondary on notch Macs.
// Provides full controls: video selection, pause, mute, and quit.
final class StatusBarController: NSObject {

    private var statusItem: NSStatusItem!
    private weak var wallpaperManager: WallpaperManager?
    private var pauseMenuItem: NSMenuItem!
    private var muteMenuItem: NSMenuItem!
    private var fileMenuItem: NSMenuItem!

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

        // ── Show Panel (only useful on notch Macs) ──────────────────
        let hasNotch = AppDelegate.hasNotchDisplay()
        if hasNotch {
            let panelItem = NSMenuItem(title: "Show Panel", action: #selector(showPanel), keyEquivalent: ",")
            panelItem.target = self
            menu.addItem(panelItem)
            menu.addItem(.separator())
        }

        // ── Settings ─────────────────────────────────────────────
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(.separator())
        
        // Current File info (disabled)
        fileMenuItem = NSMenuItem(title: currentFileLabel(), action: nil, keyEquivalent: "")
        fileMenuItem.isEnabled = false
        menu.addItem(fileMenuItem)

        menu.addItem(.separator())

        // ── Pause / Resume ───────────────────────────────────────────
        let paused = wallpaperManager?.isPaused ?? false
        pauseMenuItem = NSMenuItem(
            title: paused ? "Resume" : "Pause",
            action: #selector(togglePause),
            keyEquivalent: "p"
        )
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)

        // ── Mute / Unmute ────────────────────────────────────────────
        let muted = wallpaperManager?.isMuted ?? false
        muteMenuItem = NSMenuItem(
            title: muted ? "Unmute" : "Mute",
            action: #selector(toggleMute),
            keyEquivalent: "m"
        )
        muteMenuItem.target = self
        menu.addItem(muteMenuItem)

        menu.addItem(.separator())

        // ── Quit ─────────────────────────────────────────────────────
        let quitItem = NSMenuItem(title: "Quit Understory", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Update menu state each time the menu opens
        menu.delegate = self
    }

    // MARK: - Helpers

    private func currentFileLabel() -> String {
        guard let mgr = wallpaperManager else { return "No video selected" }
        let settings = mgr.settings[CGMainDisplayID()] ?? .defaultSettings
        switch settings.mode {
        case .idle:
            return "Using default wallpaper"
        case .video(let url):
            return url.lastPathComponent
        case .folder(let url):
            return url.lastPathComponent
        case .dayNight(_, _):
            return "Day/Night Adaptive"
        }
    }

    private func syncMenuState() {
        let paused = wallpaperManager?.isPaused ?? false
        pauseMenuItem.title = paused ? "Resume" : "Pause"

        let muted = wallpaperManager?.isMuted ?? false
        muteMenuItem.title = muted ? "Unmute" : "Mute"

        fileMenuItem.title = currentFileLabel()
    }

    // MARK: - Actions

    @objc private func showPanel() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showNotchPanelFromMenuBar()
        }
    }

    @objc private func openSettings() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showSettingsWindow()
        }
    }

    // pickFile functionality moved to SettingsWindowController

    @objc private func togglePause() {
        wallpaperManager?.togglePause()
        syncMenuState()
    }

    @objc private func toggleMute() {
        wallpaperManager?.toggleMute()
        syncMenuState()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSMenuDelegate
// Sync the menu item titles every time the menu opens so they reflect current state.
extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        syncMenuState()
    }
}
