import AppKit

// MARK: - LifecycleManager
// Observes system events to pause/resume wallpaper rendering when the desktop
// is not visible (fullscreen app, space switch, sleep, monitor hotplug),
// and pauses on Low Power Mode and screen lock for battery savings.
final class LifecycleManager {

    private let window: NSWindow
    private let onVisibilityChanged: (Bool) -> Void
    private var screenLockObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?

    init(window: NSWindow, onVisibilityChanged: @escaping (Bool) -> Void) {
        self.window = window
        self.onVisibilityChanged = onVisibilityChanged
        setupObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let obs = screenLockObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        if let obs = screenUnlockObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
    }

    // MARK: - Setup

    private func setupObservers() {
        // Window occlusion — fires when a fullscreen app covers the desktop,
        // or any opaque window completely obscures our window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )

        // Space switch — fires when the user swipes to a different desktop
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        // Display sleep/wake
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        // Monitor hotplug
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Low Power Mode — pause video to save battery
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )

        // Screen lock/unlock — pause decoding when nobody can see the desktop
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onVisibilityChanged(false)
        }
        screenUnlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Re-check occlusion after unlock — desktop might still be covered
            self?.occlusionChanged()
        }
    }

    // MARK: - Handlers

    @objc private func occlusionChanged() {
        let isVisible = window.occlusionState.contains(.visible)
        onVisibilityChanged(isVisible)
    }

    @objc private func handleSleep() {
        onVisibilityChanged(false)
    }

    @objc private func handleWake() {
        // Re-check occlusion after a brief delay (display may need time to initialize)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.occlusionChanged()
        }
    }

    @objc private func screenConfigChanged() {
        // Notify the WallpaperManager to rebuild windows for the new screen layout.
        // The visibility callback isn't the right channel for this; we post a separate notification.
        NotificationCenter.default.post(name: .understoryScreensChanged, object: nil)
    }

    @objc private func powerStateChanged() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            // Pause to save battery
            onVisibilityChanged(false)
        } else {
            // Resume — re-check actual occlusion state
            occlusionChanged()
        }
    }
}

// Custom notification for screen layout changes
extension Notification.Name {
    static let understoryScreensChanged = Notification.Name("com.understory.screensChanged")
}
