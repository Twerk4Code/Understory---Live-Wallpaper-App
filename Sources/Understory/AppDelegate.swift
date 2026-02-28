import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    var wallpaperManager: WallpaperManager!
    var statusBarController: StatusBarController!
    var notchDetector: NotchHoverDetector!
    var notchPanel: NotchPanelWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the wallpaper system across all screens
        wallpaperManager = WallpaperManager()
        wallpaperManager.start()

        // Initialize the menu-bar status item (secondary access + non-notch Macs)
        statusBarController = StatusBarController(wallpaperManager: wallpaperManager)

        // Initialize the notch hover detector
        notchDetector = NotchHoverDetector()
        notchDetector.onHoverTriggered = { [weak self] in
            self?.showNotchPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperManager.stop()
    }

    // MARK: - Notch Panel

    private func showNotchPanel() {
        // Hide the hover tracker so it doesn't interfere with the panel
        notchDetector.hideTracker()

        if notchPanel == nil {
            notchPanel = NotchPanelWindow(wallpaperManager: wallpaperManager)
            // Re-enable the tracker whenever the panel dismisses
            notchPanel?.onDismiss = { [weak self] in
                // Small delay before re-enabling to avoid immediate re-trigger
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.notchDetector.showTracker()
                }
            }
        }
        notchPanel?.syncState()
        notchPanel?.showPanel()
    }

    /// Called by StatusBarController to show the panel from the menu bar
    func showNotchPanelFromMenuBar() {
        showNotchPanel()
    }
}
