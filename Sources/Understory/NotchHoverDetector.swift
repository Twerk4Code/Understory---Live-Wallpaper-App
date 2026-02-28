import AppKit

// MARK: - NotchHoverDetector
// An invisible tracking window positioned at the MacBook Pro notch.
// Detects a 2-second mouse hover dwell to trigger the control panel.
final class NotchHoverDetector {

    private var trackingWindow: NSWindow?
    private var hoverTimer: Timer?
    private let dwellDuration: TimeInterval = 2.0
    var onHoverTriggered: (() -> Void)?

    init() {
        setupTrackingWindow()
    }

    // MARK: - Setup

    private func setupTrackingWindow() {
        let screen = notchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        let zone = notchZone(for: screen)

        let window = NSWindow(
            contentRect: zone,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar + 1  // Above menu bar so we can track there
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false  // We NEED mouse events for tracking
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenNone]
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01  // Near-invisible but still tracks mouse

        // Content view with tracking area
        let contentView = NotchTrackingView(frame: NSRect(origin: .zero, size: zone.size))
        contentView.onMouseEntered = { [weak self] in self?.startDwellTimer() }
        contentView.onMouseExited = { [weak self] in self?.cancelDwellTimer() }
        window.contentView = contentView

        window.orderFrontRegardless()
        self.trackingWindow = window
    }

    // MARK: - Notch Geometry

    /// Find the screen with a notch (safeAreaInsets.top > 0)
    private func notchScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.safeAreaInsets.top > 0 {
                return screen
            }
        }
        return nil
    }

    /// Calculate the invisible tracking zone at the notch position
    private func notchZone(for screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let notchWidth: CGFloat = 280   // Wider than the physical notch for easier access
        let notchHeight: CGFloat = 60   // Deeper trigger zone below the menu bar

        let x = frame.midX - notchWidth / 2
        let y = frame.maxY - notchHeight  // Top of screen in AppKit coordinates

        return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }

    // MARK: - Dwell Timer

    private func startDwellTimer() {
        cancelDwellTimer()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: dwellDuration, repeats: false) { [weak self] _ in
            self?.onHoverTriggered?()
        }
    }

    private func cancelDwellTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    /// Temporarily hide the tracking window (while the panel is showing)
    func hideTracker() {
        trackingWindow?.orderOut(nil)
    }

    /// Re-show the tracking window
    func showTracker() {
        trackingWindow?.orderFrontRegardless()
    }
}

// MARK: - Tracking View
// A transparent NSView that uses NSTrackingArea to detect mouse enter/exit.
private class NotchTrackingView: NSView {

    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove old tracking areas
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // Add a new one covering the full view
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
