import AppKit

// MARK: - NotchHoverDetector
// An invisible tracking window positioned at the MacBook Pro notch.
// Detects a configurable mouse hover dwell to trigger the control panel.
final class NotchHoverDetector {

    private var trackingWindow: NSWindow?
    private var hoverTimer: Timer?
    var onHoverTriggered: (() -> Void)?

    /// UserDefaults key for hover delay preference.
    static let hoverDelayKey = "com.understory.notchHoverDelay"

    /// The current dwell duration, read from UserDefaults (default 2.0s).
    var dwellDuration: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: Self.hoverDelayKey)
        return stored > 0 ? stored : 2.0
    }

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
        window.level = .statusBar + 1
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenNone]
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01

        let contentView = NotchTrackingView(frame: NSRect(origin: .zero, size: zone.size))
        contentView.onMouseEntered = { [weak self] in self?.startDwellTimer() }
        contentView.onMouseExited = { [weak self] in self?.cancelDwellTimer() }
        window.contentView = contentView

        window.orderFrontRegardless()
        self.trackingWindow = window
    }

    // MARK: - Notch Geometry

    private func notchScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.safeAreaInsets.top > 0 {
                return screen
            }
        }
        return nil
    }

    private func notchZone(for screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let notchWidth: CGFloat = 280
        let notchHeight: CGFloat = 60

        let x = frame.midX - notchWidth / 2
        let y = frame.maxY - notchHeight

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
private class NotchTrackingView: NSView {

    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
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
