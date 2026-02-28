import AppKit
import UniformTypeIdentifiers

// MARK: - NotchPanelWindow
// A pitch-black dropdown panel that merges seamlessly with the MacBook Pro notch.
// Expands outward like a Dynamic Island bubble and retracts when the mouse leaves.
final class NotchPanelWindow: NSPanel {

    private weak var wallpaperManager: WallpaperManager?
    private var fileButton: NSButton!
    private var fileLabel: NSTextField!
    private var pauseButton: NSButton!
    private var muteButton: NSButton!
    private var dismissTimer: Timer?
    private var bgView: NSView!

    // Track mouse presence to auto-dismiss
    private var mouseInside = false

    /// Called when the panel finishes hiding (use this to re-enable the hover tracker)
    var onDismiss: (() -> Void)?

    // ── Geometry ──────────────────────────────────────────────────────

    /// The physical notch width on a MacBook Pro is ~185pt; we match it for the collapsed state.
    private let notchWidth: CGFloat = 200
    /// Height of the collapsed "pill" that hides behind the notch.
    private let notchHeight: CGFloat = 34
    /// The expanded panel dimensions.
    private let expandedWidth: CGFloat = 260
    private let expandedHeight: CGFloat = 200
    /// Corner radius matching the M4 MacBook Pro notch hardware rounding.
    private let cornerRadius: CGFloat = 10

    /// The screen this panel lives on.
    private var panelScreen: NSScreen!

    init(wallpaperManager: WallpaperManager) {
        let screen = NotchPanelWindow.findNotchScreen() ?? NSScreen.main ?? NSScreen.screens[0]

        // Start at the notch position (collapsed pill)
        let collapsedFrame = NotchPanelWindow.notchFrame(
            on: screen, width: 200, height: 34
        )

        super.init(
            contentRect: collapsedFrame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.panelScreen = screen
        self.wallpaperManager = wallpaperManager
        configurePanel()
        buildUI()
        syncState()
    }

    // MARK: - Panel Configuration

    private func configurePanel() {
        self.level = .statusBar + 2  // Above the tracking window
        self.isOpaque = false        // Must be false so rounded corners are transparent
        self.backgroundColor = .clear // Window itself is transparent; bgView provides the black
        self.hasShadow = false       // No glow/border — seamless with the notch
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenNone]
    }

    // MARK: - UI Construction

    private func buildUI() {
        // Pure #000000 background — sRGB (0,0,0) is guaranteed pure black on OLED/miniLED
        let pureBlack = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = pureBlack
        bg.layer?.cornerRadius = cornerRadius
        bg.layer?.masksToBounds = true
        self.contentView = bg
        self.bgView = bg

        // Tracking area for auto-dismiss
        let tracker = PanelTrackingView(frame: bg.bounds)
        tracker.autoresizingMask = [.width, .height]
        tracker.onMouseEntered = { [weak self] in
            self?.mouseInside = true
            self?.cancelDismissTimer()
        }
        tracker.onMouseExited = { [weak self] in
            self?.mouseInside = false
            self?.startDismissTimer()
        }
        bg.addSubview(tracker)

        // Container — top padding accounts for the safe area (notch) so content
        // sits below the physical notch while the black extends behind it.
        let safeTop = panelScreen.safeAreaInsets.top > 0 ? panelScreen.safeAreaInsets.top : 32
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: bg.topAnchor, constant: safeTop + 12),
            container.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            container.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -16),
        ])

        // ── App Name ──────────────────────────────────────────────
        let titleLabel = NSTextField(labelWithString: "Understory")
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        // ── File Picker ───────────────────────────────────────────
        fileButton = NSButton(title: "Choose Video…", target: self, action: #selector(pickFile))
        fileButton.bezelStyle = .rounded
        fileButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(fileButton)

        fileLabel = NSTextField(labelWithString: "Using default wallpaper")
        fileLabel.font = .systemFont(ofSize: 11, weight: .regular)
        fileLabel.textColor = .tertiaryLabelColor
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fileLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        fileLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(fileLabel)

        // ── Separator ─────────────────────────────────────────────
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sep)

        // ── Control Buttons Row ───────────────────────────────────
        pauseButton = makeIconButton(symbolName: "pause.fill", action: #selector(togglePause))
        muteButton = makeIconButton(symbolName: "speaker.wave.2.fill", action: #selector(toggleMute))
        let quitButton = makeIconButton(symbolName: "power", action: #selector(quitApp))

        let buttonStack = NSStackView(views: [pauseButton, muteButton, quitButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(buttonStack)

        // ── Layout ────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            fileButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            fileButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            fileLabel.centerYAnchor.constraint(equalTo: fileButton.centerYAnchor),
            fileLabel.leadingAnchor.constraint(equalTo: fileButton.trailingAnchor, constant: 8),
            fileLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            sep.topAnchor.constraint(equalTo: fileButton.bottomAnchor, constant: 12),
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            buttonStack.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 12),
            buttonStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: 30),
        ])

        // Start with content hidden (will fade in during expand)
        container.alphaValue = 0
    }

    // MARK: - Button Factory

    private func makeIconButton(symbolName: String, action: Selector) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .rounded
        btn.isBordered = false
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false

        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            btn.image = img.withSymbolConfiguration(config)
        }
        btn.contentTintColor = .secondaryLabelColor

        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 44),
            btn.heightAnchor.constraint(equalToConstant: 36),
        ])
        return btn
    }

    // MARK: - State Sync

    func syncState() {
        guard let mgr = wallpaperManager else { return }

        switch mgr.mode {
        case .idle:
            fileLabel.stringValue = "Using default wallpaper"
        case .video(let url):
            fileLabel.stringValue = url.lastPathComponent
        }

        // Pause button icon
        let pauseSymbol = mgr.isPaused ? "play.fill" : "pause.fill"
        if let img = NSImage(systemSymbolName: pauseSymbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            pauseButton.image = img.withSymbolConfiguration(config)
        }

        // Mute button icon
        let muteSymbol = mgr.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        if let img = NSImage(systemSymbolName: muteSymbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            muteButton.image = img.withSymbolConfiguration(config)
        }
    }

    // MARK: - Actions

    @objc private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        var types: [UTType] = []
        if let mp4 = UTType(filenameExtension: "mp4") { types.append(mp4) }
        if let mov = UTType(filenameExtension: "mov") { types.append(mov) }
        if let livp = UTType(filenameExtension: "livp") { types.append(livp) }
        if types.isEmpty { types = [.movie] }
        panel.allowedContentTypes = types
        panel.message = "Choose a video for your desktop wallpaper"

        // Run as modal since we don't have a parent window to sheet onto reliably
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        fileLabel.stringValue = url.lastPathComponent
        wallpaperManager?.setMode(.video(url: url))
    }

    @objc private func togglePause() {
        wallpaperManager?.togglePause()
        syncState()
    }

    @objc private func toggleMute() {
        wallpaperManager?.toggleMute()
        syncState()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Show / Hide — Dynamic Island Bubble Animation

    func showPanel() {
        syncState()

        // Refresh the screen reference in case monitors changed since init
        panelScreen = NotchPanelWindow.findNotchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        let screen = panelScreen!

        // Start at the collapsed notch pill position
        let collapsed = NotchPanelWindow.notchFrame(
            on: screen, width: notchWidth, height: notchHeight
        )
        self.setFrame(collapsed, display: false)
        self.alphaValue = 1
        self.contentView?.subviews.last?.alphaValue = 0  // container hidden initially
        // Ensure content subviews are hidden during the expand
        if let container = bgView.subviews.last {
            container.alphaValue = 0
        }
        self.orderFrontRegardless()

        // Expanded frame — centered at the notch, growing downward
        let expanded = NotchPanelWindow.notchFrame(
            on: screen, width: expandedWidth, height: expandedHeight
        )

        // Animate the bubble expansion
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().setFrame(expanded, display: true)
        }, completionHandler: { [weak self] in
            // Fade in the content after the bubble has expanded
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                if let container = self.bgView.subviews.last {
                    container.animator().alphaValue = 1
                }
            })
        })

        // Start dismiss timer in case mouse never enters the panel
        startDismissTimer()
    }

    func hidePanel() {
        cancelDismissTimer()

        let screen = panelScreen!
        let collapsed = NotchPanelWindow.notchFrame(
            on: screen, width: notchWidth, height: notchHeight
        )

        // Fade out content first, then retract the bubble
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if let container = self.bgView.subviews.last {
                container.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            // Retract the bubble back to the notch
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0.0, 0.84, 0.0)
                self.animator().setFrame(collapsed, display: true)
            }, completionHandler: { [weak self] in
                self?.orderOut(nil)
                self?.onDismiss?()
            })
        })
    }

    // MARK: - Auto-Dismiss Timer

    private func startDismissTimer() {
        cancelDismissTimer()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.mouseInside else { return }
            self.hidePanel()
        }
    }

    private func cancelDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    // MARK: - Helpers

    /// Calculate a frame centered at the notch position, anchored to the top of the screen.
    /// The top edge extends behind the menu bar to merge with the physical notch.
    private static func notchFrame(on screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let frame = screen.frame
        let x = frame.midX - width / 2
        // Anchor the top of the panel to the very top of the screen (behind the notch)
        let y = frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func findNotchScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.safeAreaInsets.top > 0 {
                return screen
            }
        }
        return nil
    }
}

// MARK: - Panel Tracking View
private class PanelTrackingView: NSView {

    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
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
