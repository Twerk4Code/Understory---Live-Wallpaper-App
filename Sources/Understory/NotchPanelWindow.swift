import AppKit
import UniformTypeIdentifiers

// MARK: - NotchPanelWindow
final class NotchPanelWindow: NSPanel {

    private weak var wallpaperManager: WallpaperManager?
    private var dismissTimer: Timer?
    private var bgView: NSView!
    private var mouseInside = false
    private var clickMonitor: Any?
    var onDismiss: (() -> Void)?

    // UI Configuration
    private let notchWidth: CGFloat = 220
    private let notchHeight: CGFloat = 34
    private let expandedWidth: CGFloat = 220
    private let expandedHeight: CGFloat = 115
    private let cornerRadius: CGFloat = 10
    private var panelScreen: NSScreen!

    // UI Elements
    private var videoButton: NSButton!
    private var settingsButton: NSButton!
    private var pauseButton: NSButton!
    private var muteButton: NSButton!

    init(wallpaperManager: WallpaperManager) {
        let screen = NotchPanelWindow.findNotchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        let collapsedFrame = NotchPanelWindow.notchFrame(on: screen, width: notchWidth, height: notchHeight)

        super.init(contentRect: collapsedFrame, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        self.panelScreen = screen
        self.wallpaperManager = wallpaperManager
        
        configurePanel()
        buildUI()
        syncState()
    }

    private func configurePanel() {
        self.level = .statusBar + 2
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenNone]
    }

    private func buildUI() {
        let pureBlack = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        bgView = NSView()
        bgView.wantsLayer = true
        bgView.layer?.backgroundColor = pureBlack
        bgView.layer?.cornerRadius = cornerRadius
        bgView.layer?.masksToBounds = true
        self.contentView = bgView

        let tracker = PanelTrackingView(frame: bgView.bounds)
        tracker.autoresizingMask = [.width, .height]
        tracker.onMouseEntered = { [weak self] in
            self?.mouseInside = true
            self?.cancelDismissTimer()
        }
        tracker.onMouseExited = { [weak self] in
            self?.mouseInside = false
            self?.startDismissTimer()
        }
        bgView.addSubview(tracker)

        let safeTop = panelScreen.safeAreaInsets.top > 0 ? panelScreen.safeAreaInsets.top : 32
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 8
        container.alignment = .centerX
        container.translatesAutoresizingMaskIntoConstraints = false
        bgView.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: bgView.topAnchor, constant: safeTop + 8),
            container.leadingAnchor.constraint(equalTo: bgView.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: bgView.trailingAnchor, constant: -12)
        ])

        // ── Video Picker Button ──────────────────────────────────
        videoButton = NSButton(title: "Choose Video…", target: self, action: #selector(pickVideo))
        videoButton.bezelStyle = .rounded
        videoButton.controlSize = .small
        videoButton.font = .systemFont(ofSize: 11)
        videoButton.lineBreakMode = .byTruncatingMiddle
        videoButton.widthAnchor.constraint(equalToConstant: 180).isActive = true
        container.addArrangedSubview(videoButton)

        // ── Control Buttons ──────────────────────────────────────
        settingsButton = makeIconButton(symbolName: "gearshape.fill", action: #selector(openSettings))
        pauseButton = makeIconButton(symbolName: "pause.fill", action: #selector(togglePause))
        muteButton = makeIconButton(symbolName: "speaker.wave.2.fill", action: #selector(toggleMute))
        let buttonStack = NSStackView(views: [settingsButton, pauseButton, muteButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 16
        buttonStack.distribution = .fillEqually
        container.addArrangedSubview(buttonStack)

        container.alphaValue = 0
    }

    private func makeIconButton(symbolName: String, action: Selector) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .rounded
        btn.isBordered = false
        btn.target = self
        btn.action = action
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            btn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        }
        btn.contentTintColor = .secondaryLabelColor
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 40),
            btn.heightAnchor.constraint(equalToConstant: 36)
        ])
        return btn
    }

    func syncState() {
        guard let mgr = wallpaperManager else { return }

        let pauseSymbol = mgr.isPaused ? "play.fill" : "pause.fill"
        pauseButton.image = NSImage(systemSymbolName: pauseSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        
        let muteSymbol = mgr.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.image = NSImage(systemSymbolName: muteSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .regular))

        // Update video button label with current file name
        let settings = mgr.settings[CGMainDisplayID()] ?? .defaultSettings
        switch settings.mode {
        case .idle:
            videoButton.title = "Choose Video…"
        case .video(let url):
            videoButton.title = "🎬 " + url.lastPathComponent
        case .folder(let url):
            videoButton.title = "📁 " + url.lastPathComponent
        case .dayNight(_, _):
            videoButton.title = "🌗 Day/Night"
        }
    }

    // MARK: - Actions
    
    @objc private func pickVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mp4")!,
            UTType(filenameExtension: "mov")!,
            UTType(filenameExtension: "livp")!,
            .movie
        ]
        panel.message = "Choose a video wallpaper"
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        guard let mgr = wallpaperManager else { return }
        let mainID = CGMainDisplayID()
        var settings = mgr.settings[mainID] ?? .defaultSettings
        settings.mode = .video(url: url)
        settings.lastVideoURL = url
        mgr.updateSettings(for: nil, newSettings: settings)
        syncState()
    }

    @objc private func openSettings() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showSettingsWindow()
            self.hidePanel()
        }
    }

    @objc private func togglePause() {
        wallpaperManager?.togglePause()
        syncState()
    }

    @objc private func toggleMute() {
        wallpaperManager?.toggleMute()
        syncState()
    }

    // MARK: - Show / Hide

    func showPanel() {
        syncState()
        panelScreen = NotchPanelWindow.findNotchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        let collapsed = NotchPanelWindow.notchFrame(on: panelScreen, width: notchWidth, height: notchHeight)
        self.setFrame(collapsed, display: false)
        self.alphaValue = 1

        let container = bgView.subviews.last
        container?.wantsLayer = true
        container?.alphaValue = 0
        self.orderFrontRegardless()

        let expanded = NotchPanelWindow.notchFrame(on: panelScreen, width: expandedWidth, height: expandedHeight)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().setFrame(expanded, display: true)
        }, completionHandler: { [weak container] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                container?.animator().alphaValue = 1
            })
        })

        installClickMonitor()
        startDismissTimer()
    }

    func hidePanel() {
        cancelDismissTimer()
        removeClickMonitor()
        let collapsed = NotchPanelWindow.notchFrame(on: panelScreen, width: notchWidth, height: notchHeight)
        let container = bgView.subviews.last

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            container?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
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

    // MARK: - Auto-Dismiss

    private func startDismissTimer() {
        cancelDismissTimer()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.mouseInside else { return }
            self.hidePanel()
        }
    }

    private func cancelDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    /// Global click monitor — dismiss the panel when the user clicks anywhere outside it.
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            // If click is outside our panel frame, dismiss
            let screenPoint = NSEvent.mouseLocation
            if !self.frame.contains(screenPoint) {
                self.hidePanel()
            }
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private static func notchFrame(on screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let frame = screen.frame
        let x = frame.midX - width / 2
        let y = frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func findNotchScreen() -> NSScreen? {
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }
}

// MARK: - Panel Tracking View
private class PanelTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
}
