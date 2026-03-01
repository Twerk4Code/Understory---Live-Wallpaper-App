import AppKit
import UniformTypeIdentifiers

// MARK: - SettingsViewController
final class SettingsViewController: NSViewController {

    private weak var wallpaperManager: WallpaperManager?
    
    // UI Elements
    private var displayPopUp: NSPopUpButton!
    private var modeControl: NSSegmentedControl!
    
    private var fileButton1: NSButton!
    private var fileLabel1: NSTextField!
    private var fileRow1: NSStackView!
    
    private var fileButton2: NSButton!
    private var fileLabel2: NSTextField!
    private var fileRow2: NSStackView!
    
    // Cycle specific
    private var cycleIntervalRow: NSStackView!
    private var cycleIntervalPopUp: NSPopUpButton!
    
    // Day/Night specific
    private var schedulePopUp: NSPopUpButton!
    private var dayHourPopUp: NSPopUpButton!
    private var nightHourPopUp: NSPopUpButton!
    private var scheduleRow: NSStackView!
    
    private var speedSlider: NSSlider!
    private var speedValueLabel: NSTextField!

    private var selectedScreenID: CGDirectDisplayID? = nil // nil = All Screens

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 400))
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
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // ── Header ──────────────────────────────────────────────
        let titleLabel = NSTextField(labelWithString: "Understory Settings")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        container.addArrangedSubview(titleLabel)

        let sep1 = NSBox()
        sep1.boxType = .separator
        container.addArrangedSubview(sep1)

        // ── Display Selector ──────────────────────────────────────
        let displayRow = NSStackView()
        displayRow.orientation = .horizontal
        let displayLabel = NSTextField(labelWithString: "Display:")
        displayLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
        displayRow.addArrangedSubview(displayLabel)
        
        displayPopUp = NSPopUpButton(title: "", target: self, action: #selector(displayChanged))
        displayPopUp.addItem(withTitle: "All Displays")
        for screen in NSScreen.screens {
            let id = screenDisplayID(screen)
            displayPopUp.addItem(withTitle: "Display \(id)")
            displayPopUp.lastItem?.tag = Int(id)
        }
        displayRow.addArrangedSubview(displayPopUp)
        container.addArrangedSubview(displayRow)
        
        // Hide Display row if only 1 screen exists
        if NSScreen.screens.count <= 1 {
            displayRow.isHidden = true
        }
        
        // ── Mode Selector ─────────────────────────────────────────
        let modeRow = NSStackView()
        modeRow.orientation = .horizontal
        let modeLabel = NSTextField(labelWithString: "Mode:")
        modeLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
        modeRow.addArrangedSubview(modeLabel)
        
        modeControl = NSSegmentedControl(labels: ["Video", "Cycle", "Day/Night"], trackingMode: .selectOne, target: self, action: #selector(modeChanged))
        modeRow.addArrangedSubview(modeControl)
        container.addArrangedSubview(modeRow)

        // ── Schedule Selector (Day/Night only) ────────────────────
        scheduleRow = NSStackView()
        scheduleRow.orientation = .horizontal
        let scheduleLabel = NSTextField(labelWithString: "Schedule:")
        scheduleLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
        scheduleRow.addArrangedSubview(scheduleLabel)
        
        schedulePopUp = NSPopUpButton(title: "", target: self, action: #selector(scheduleChanged))
        schedulePopUp.addItem(withTitle: "macOS Default")
        schedulePopUp.addItem(withTitle: "Custom Night Period")
        scheduleRow.addArrangedSubview(schedulePopUp)
        
        let fromLabel = NSTextField(labelWithString: "From:")
        scheduleRow.addArrangedSubview(fromLabel)
        
        dayHourPopUp = buildHourMenu()
        dayHourPopUp.action = #selector(scheduleChanged)
        dayHourPopUp.target = self
        scheduleRow.addArrangedSubview(dayHourPopUp)
        
        let toLabel = NSTextField(labelWithString: "to")
        scheduleRow.addArrangedSubview(toLabel)
        
        nightHourPopUp = buildHourMenu()
        nightHourPopUp.action = #selector(scheduleChanged)
        nightHourPopUp.target = self
        scheduleRow.addArrangedSubview(nightHourPopUp)
        
        container.addArrangedSubview(scheduleRow)

        // ── Cycle Interval Selector (Cycle only) ──────────────────
        cycleIntervalRow = NSStackView()
        cycleIntervalRow.orientation = .horizontal
        let cycleLabel = NSTextField(labelWithString: "Cycle Every:")
        cycleLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
        cycleIntervalRow.addArrangedSubview(cycleLabel)
        
        cycleIntervalPopUp = NSPopUpButton(title: "", target: self, action: #selector(cycleIntervalChanged))
        let intervals: [(String, TimeInterval)] = [
            ("5 Minutes", 300),
            ("10 Minutes", 600),
            ("15 Minutes", 900),
            ("30 Minutes", 1800),
            ("1 Hour", 3600),
            ("2 Hours", 7200)
        ]
        for (title, value) in intervals {
            cycleIntervalPopUp.addItem(withTitle: title)
            cycleIntervalPopUp.lastItem?.tag = Int(value)
        }
        cycleIntervalRow.addArrangedSubview(cycleIntervalPopUp)
        container.addArrangedSubview(cycleIntervalRow)

        // ── File Pickers ──────────────────────────────────────────
        fileButton1 = NSButton(title: "Choose...", target: self, action: #selector(pickFile1))
        fileButton1.bezelStyle = .rounded
        fileButton1.widthAnchor.constraint(equalToConstant: 120).isActive = true
        fileLabel1 = NSTextField(labelWithString: "None")
        fileLabel1.lineBreakMode = .byTruncatingMiddle
        fileRow1 = NSStackView(views: [fileButton1, fileLabel1])
        fileRow1.orientation = .horizontal
        container.addArrangedSubview(fileRow1)
        
        fileButton2 = NSButton(title: "Choose...", target: self, action: #selector(pickFile2))
        fileButton2.bezelStyle = .rounded
        fileButton2.widthAnchor.constraint(equalToConstant: 120).isActive = true
        fileLabel2 = NSTextField(labelWithString: "None")
        fileLabel2.lineBreakMode = .byTruncatingMiddle
        fileRow2 = NSStackView(views: [fileButton2, fileLabel2])
        fileRow2.orientation = .horizontal
        container.addArrangedSubview(fileRow2)

        let sep2 = NSBox()
        sep2.boxType = .separator
        container.addArrangedSubview(sep2)

        // ── Playback Speed ────────────────────────────────────────
        let speedRow = NSStackView()
        speedRow.orientation = .horizontal
        let sLabel = NSTextField(labelWithString: "Speed:")
        sLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
        speedRow.addArrangedSubview(sLabel)
        
        speedSlider = NSSlider(value: 1.0, minValue: 0.25, maxValue: 2.0, target: self, action: #selector(speedChanged))
        speedSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        speedRow.addArrangedSubview(speedSlider)
        
        speedValueLabel = NSTextField(labelWithString: "1.0x")
        speedRow.addArrangedSubview(speedValueLabel)
        container.addArrangedSubview(speedRow)
        
        // Spacer to push everything up
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.addArrangedSubview(spacer)
    }

    private func buildHourMenu() -> NSPopUpButton {
        let popUp = NSPopUpButton(title: "", target: nil, action: nil)
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        
        var dateComps = DateComponents()
        dateComps.year = 2000
        dateComps.month = 1
        dateComps.day = 1
        
        for i in 0..<24 {
            dateComps.hour = i
            if let d = Calendar.current.date(from: dateComps) {
                popUp.addItem(withTitle: formatter.string(from: d))
                popUp.lastItem?.tag = i
            }
        }
        return popUp
    }

    private func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    func syncState() {
        guard let mgr = wallpaperManager else { return }
        let idToFetch = selectedScreenID ?? screenDisplayID(NSScreen.screens[0])
        let settings = mgr.settings[idToFetch] ?? .defaultSettings

        // Sync Pickers based on Mode
        switch settings.mode {
        case .idle:
            // Should not be reachable now, map to single
            modeControl.selectedSegment = 0
            fileRow1.isHidden = true
            fileRow2.isHidden = true
            scheduleRow.isHidden = true
            cycleIntervalRow.isHidden = true
        case .video(let url):
            modeControl.selectedSegment = 0
            fileButton1.title = "Choose Video..."
            fileLabel1.stringValue = url.lastPathComponent
            fileRow1.isHidden = false
            fileRow2.isHidden = true
            scheduleRow.isHidden = true
            cycleIntervalRow.isHidden = true
        case .folder(let url):
            modeControl.selectedSegment = 1
            fileButton1.title = "Choose Folder..."
            fileLabel1.stringValue = url.lastPathComponent
            fileRow1.isHidden = false
            fileRow2.isHidden = true
            scheduleRow.isHidden = true
            cycleIntervalRow.isHidden = false
        case .dayNight(let d, let n):
            modeControl.selectedSegment = 2
            fileButton1.title = "Day Video..."
            fileLabel1.stringValue = d.lastPathComponent
            fileButton2.title = "Night Video..."
            fileLabel2.stringValue = n.lastPathComponent
            fileRow1.isHidden = false
            fileRow2.isHidden = false
            scheduleRow.isHidden = false
            cycleIntervalRow.isHidden = true
        }
        
        // Sync Cycle Interval
        if !cycleIntervalPopUp.selectItem(withTag: Int(settings.cycleInterval)) {
            cycleIntervalPopUp.selectItem(withTag: 600) // Default 10m
        }
        
        // Sync Schedule
        switch settings.dayNightSchedule {
        case .systemAppearance:
            schedulePopUp.selectItem(at: 0)
            dayHourPopUp.isHidden = true
            nightHourPopUp.isHidden = true
        case .customTimes(let nightFrom, let nightTo):
            schedulePopUp.selectItem(at: 1)
            dayHourPopUp.isHidden = false
            nightHourPopUp.isHidden = false
            dayHourPopUp.selectItem(withTag: nightFrom)
            nightHourPopUp.selectItem(withTag: nightTo)
        }
        
        speedSlider.floatValue = settings.playbackSpeed
        speedValueLabel.stringValue = String(format: "%.2fx", settings.playbackSpeed)
    }

    // MARK: - Actions
    
    @objc private func displayChanged() {
        if displayPopUp.indexOfSelectedItem == 0 {
            selectedScreenID = nil
        } else {
            selectedScreenID = CGDirectDisplayID(displayPopUp.selectedItem!.tag)
        }
        syncState()
    }

    @objc private func modeChanged() {
        var settings = fetchCurrentSettings()
        switch modeControl.selectedSegment {
        case 0: // Video
            if let retained = settings.lastVideoURL {
                settings.mode = .video(url: retained)
                wallpaperManager?.updateSettings(for: selectedScreenID, newSettings: settings)
                syncState()
            } else {
                pickFile1()
            }
        case 1: // Cycle
            if let retained = settings.lastFolderURL {
                settings.mode = .folder(url: retained)
                wallpaperManager?.updateSettings(for: selectedScreenID, newSettings: settings)
                syncState()
            } else {
                pickFolder()
            }
        case 2: // Day/Night
            if let day = settings.lastDayURL, let night = settings.lastNightURL {
                settings.mode = .dayNight(dayURL: day, nightURL: night)
                wallpaperManager?.updateSettings(for: selectedScreenID, newSettings: settings)
                syncState()
            } else {
                pickFile1()
            }
        default: break
        }
    }
    
    @objc private func cycleIntervalChanged() {
        var settings = fetchCurrentSettings()
        settings.cycleInterval = TimeInterval(cycleIntervalPopUp.selectedItem?.tag ?? 600)
        wallpaperManager?.updateSettings(for: selectedScreenID, newSettings: settings)
        syncState()
    }
    
    @objc private func scheduleChanged() {
        var settings = fetchCurrentSettings()
        if schedulePopUp.indexOfSelectedItem == 0 {
            settings.dayNightSchedule = .systemAppearance
        } else {
            let nightFrom = dayHourPopUp.selectedItem?.tag ?? 19
            let nightTo = nightHourPopUp.selectedItem?.tag ?? 7
            settings.dayNightSchedule = .customTimes(nightFromHour: nightFrom, nightToHour: nightTo)
        }
        wallpaperManager?.updateSettings(for: selectedScreenID, newSettings: settings)
        syncState()
    }
    
    private func fetchCurrentSettings() -> ScreenSettings {
        let idToFetch = selectedScreenID ?? screenDisplayID(NSScreen.screens[0])
        return wallpaperManager?.settings[idToFetch] ?? .defaultSettings
    }
    
    @objc private func speedChanged() {
        var settings = fetchCurrentSettings()
        settings.playbackSpeed = speedSlider.floatValue
        wallpaperManager?.updateSettings(for: selectedScreenID, newSettings: settings)
        speedValueLabel.stringValue = String(format: "%.2fx", speedSlider.floatValue)
    }
    


    @objc private func pickFile1() {
        if modeControl.selectedSegment == 1 {
            pickFolder()
            return
        }
        let url = showOpenPanel(directories: false)
        guard let url = url else {
            syncState() // Reset if cancelled
            return
        }
        
        var settings = fetchCurrentSettings()
        if modeControl.selectedSegment == 0 {
            settings.mode = .video(url: url)
            settings.lastVideoURL = url
        } else if modeControl.selectedSegment == 2 {
            if case .dayNight(_, let n) = settings.mode {
                settings.mode = .dayNight(dayURL: url, nightURL: n)
                settings.lastDayURL = url
            } else if let n = settings.lastNightURL {
                settings.mode = .dayNight(dayURL: url, nightURL: n)
                settings.lastDayURL = url
            } else {
                settings.mode = .dayNight(dayURL: url, nightURL: url) // Fallback
                settings.lastDayURL = url
            }
        }
        wallpaperManager?.updateSettings(for: selectedScreenID, newSettings: settings)
        syncState()
    }
    
    @objc private func pickFile2() {
        let url = showOpenPanel(directories: false)
        guard let url = url else { return }
        var settings = fetchCurrentSettings()
        if case .dayNight(let d, _) = settings.mode {
            settings.mode = .dayNight(dayURL: d, nightURL: url)
            settings.lastNightURL = url
        } else if let d = settings.lastDayURL {
            settings.mode = .dayNight(dayURL: d, nightURL: url)
            settings.lastNightURL = url
        }
        wallpaperManager?.updateSettings(for: selectedScreenID, newSettings: settings)
        syncState()
    }
    
    private func pickFolder() {
        let url = showOpenPanel(directories: true)
        guard let url = url else {
            syncState()
            return
        }
        var settings = fetchCurrentSettings()
        settings.mode = .folder(url: url)
        settings.lastFolderURL = url
        wallpaperManager?.updateSettings(for: selectedScreenID, newSettings: settings)
        syncState()
    }
    
    private func showOpenPanel(directories: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        if !directories {
            panel.allowedContentTypes = [UTType(filenameExtension: "mp4")!, UTType(filenameExtension: "mov")!, UTType(filenameExtension: "livp")!, .movie]
        }
        panel.message = directories ? "Choose a folder of videos" : "Choose a video"
        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }
}
