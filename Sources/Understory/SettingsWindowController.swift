import AppKit

// MARK: - SettingsWindowController
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let wallpaperManager: WallpaperManager

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Understory Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        
        super.init(window: window)
        
        window.tabbingMode = .disallowed
        window.delegate = self

        // Build tabbed UI
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        // Tab 1: Wallpaper
        let wallpaperTab = NSTabViewItem(identifier: "wallpaper")
        wallpaperTab.label = "Wallpaper"
        let wallpaperVC = SettingsViewController(wallpaperManager: wallpaperManager)
        wallpaperTab.view = wallpaperVC.view
        tabView.addTabViewItem(wallpaperTab)

        // Tab 2: Notch
        let notchTab = NSTabViewItem(identifier: "notch")
        notchTab.label = "Notch"
        let notchVC = NotchSettingsViewController()
        notchTab.view = notchVC.view
        tabView.addTabViewItem(notchTab)

        // We keep references to the VCs so they stay alive
        self.wallpaperVC = wallpaperVC
        self.notchVC = notchVC

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 420))
        containerView.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            tabView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            tabView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            tabView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
        ])
        
        window.contentView = containerView
    }

    private var wallpaperVC: SettingsViewController?
    private var notchVC: NotchSettingsViewController?

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showSettings() {
        wallpaperVC?.syncState()
        notchVC?.syncState()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Optional cleanup
    }
}

// MARK: - NotchSettingsViewController
/// Tab 2: Notch UI preferences (hover delay).
final class NotchSettingsViewController: NSViewController {

    private var hoverDelayPopUp: NSPopUpButton!

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 300))
        buildUI()
        syncState()
    }

    private func buildUI() {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 16
        container.alignment = .leading
        container.edgeInsets = NSEdgeInsets(top: 20, left: 30, bottom: 20, right: 30)
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Header
        let titleLabel = NSTextField(labelWithString: "Notch Panel")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        container.addArrangedSubview(titleLabel)

        let sep = NSBox()
        sep.boxType = .separator
        container.addArrangedSubview(sep)

        // Hover Delay Row
        let delayRow = NSStackView()
        delayRow.orientation = .horizontal
        let delayLabel = NSTextField(labelWithString: "Hover Delay:")
        delayLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        delayRow.addArrangedSubview(delayLabel)

        hoverDelayPopUp = NSPopUpButton(title: "", target: self, action: #selector(hoverDelayChanged))
        let options: [(String, TimeInterval)] = [
            ("0.5 seconds", 0.5),
            ("1 second", 1.0),
            ("2 seconds", 2.0),
            ("3 seconds", 3.0),
        ]
        for (title, value) in options {
            hoverDelayPopUp.addItem(withTitle: title)
            hoverDelayPopUp.lastItem?.tag = Int(value * 10) // Store as 5, 10, 20, 30
        }
        delayRow.addArrangedSubview(hoverDelayPopUp)
        container.addArrangedSubview(delayRow)

        // Info text
        let infoLabel = NSTextField(wrappingLabelWithString: "The panel will automatically dismiss after 3 seconds, or when you click outside of it.")
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        container.addArrangedSubview(infoLabel)
    }

    func syncState() {
        let stored = UserDefaults.standard.double(forKey: NotchHoverDetector.hoverDelayKey)
        let delay = stored > 0 ? stored : 2.0
        let tag = Int(delay * 10)
        hoverDelayPopUp.selectItem(withTag: tag)
    }

    @objc private func hoverDelayChanged() {
        let tag = hoverDelayPopUp.selectedItem?.tag ?? 20
        let delay = TimeInterval(tag) / 10.0
        UserDefaults.standard.set(delay, forKey: NotchHoverDetector.hoverDelayKey)
    }
}
