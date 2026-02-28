import AppKit

// MARK: - WallpaperWindow
// A borderless, click-through window that sits between the desktop wallpaper
// and the Finder icon layer. One instance per screen.
final class WallpaperWindow: NSWindow {

    init(for screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        configureLevel()
        configureAppearance()
    }

    // Place just below the desktop icon layer
    private func configureLevel() {
        let iconLevel = CGWindowLevelForKey(.desktopIconWindow)
        self.level = NSWindow.Level(rawValue: Int(iconLevel) - 1)
    }

    private func configureAppearance() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false

        collectionBehavior = [
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
            .fullScreenNone
        ]
    }
}
