import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    var wallpaperManager: WallpaperManager!
    var statusBarController: StatusBarController!
    var notchDetector: NotchHoverDetector?
    var notchPanel: NotchPanelWindow?

    /// Whether this Mac has a notch (Apple Silicon MacBook Pro/Air with notch display).
    private var hasNotch: Bool {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the wallpaper system across all screens
        wallpaperManager = WallpaperManager()
        wallpaperManager.start()

        // Initialize the menu-bar status item (always available on all Macs)
        statusBarController = StatusBarController(wallpaperManager: wallpaperManager)

        // Only enable the notch hover panel on Macs with a physical notch
        if hasNotch {
            let detector = NotchHoverDetector()
            detector.onHoverTriggered = { [weak self] in
                self?.showNotchPanel()
            }
            notchDetector = detector
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperManager.stop()
    }

    // MARK: - Notch Panel

    private func showNotchPanel() {
        guard let notchDetector = notchDetector else { return }

        // Hide the hover tracker so it doesn't interfere with the panel
        notchDetector.hideTracker()

        if notchPanel == nil {
            notchPanel = NotchPanelWindow(wallpaperManager: wallpaperManager)
            // Re-enable the tracker whenever the panel dismisses
            notchPanel?.onDismiss = { [weak self] in
                // Small delay before re-enabling to avoid immediate re-trigger
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.notchDetector?.showTracker()
                }
            }
        }
        notchPanel?.syncState()
        notchPanel?.showPanel()
    }

    /// Called by StatusBarController to show the panel from the menu bar (only on notch Macs)
    func showNotchPanelFromMenuBar() {
        guard hasNotch else { return }
        showNotchPanel()
    }
    
    // MARK: - Settings Window
    
    var settingsWindowController: SettingsWindowController?
    
    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(wallpaperManager: wallpaperManager)
        }
        settingsWindowController?.showSettings()
    }
}
