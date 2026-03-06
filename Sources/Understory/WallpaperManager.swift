import AppKit
import AVFoundation
import os

// Enums moved to WallpaperSettings.swift

// MARK: - Per-Screen Context
// Groups a window, renderers, display-link, and lifecycle manager for one monitor.
private final class ScreenContext {
    let displayID: CGDirectDisplayID
    let window: WallpaperWindow
    var videoRenderer: VideoRenderer?
    var lifecycleManager: LifecycleManager?
    /// The URL currently loaded in the renderer. Used to avoid redundant teardown/setup.
    var activeVideoURL: URL?
    /// Persistent host view — we reuse this so contentView is never nil (prevents flash).
    var hostView: NSView?

    init(screen: NSScreen, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        self.window = WallpaperWindow(for: screen)
    }
}

// MARK: - WallpaperManager
// Central coordinator: one WallpaperWindow per screen.
// Defaults to .idle (native wallpaper) until the user picks a video.
final class WallpaperManager {

    private var contexts: [CGDirectDisplayID: ScreenContext] = [:]
    private(set) var settings: [CGDirectDisplayID: ScreenSettings] = [:]
    private var screenObserver: Any?
    private var screenChangeDebounce: DispatchWorkItem?

    init() {
        loadPersistedMode()
    }

    // MARK: - Lifecycle

    func start() {
        reconcileContexts()
        observeScreenChanges()
    }

    func stop() {
        for (_, ctx) in contexts {
            teardown(ctx)
        }
        contexts.removeAll()
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        if let obs = themeObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            themeObserver = nil
        }
        customTimeTimer?.invalidate()
        customTimeTimer = nil
    }

    // MARK: - Mode Switching

    func updateSettings(for screenID: CGDirectDisplayID?, newSettings: ScreenSettings) {
        assert(Thread.isMainThread, "WallpaperManager.updateSettings must be called from main thread")
        os_log("Updating wallpaper settings", log: UnderstoryLogger.settings, type: .info)
        if let id = screenID {
            settings[id] = newSettings
        } else {
            for screen in NSScreen.screens {
                let id = screenDisplayID(screen)
                settings[id] = newSettings
            }
        }

        persistSettings()

        for (id, ctx) in contexts {
            guard screenID == nil || screenID == id else { continue }

            let targetURL = resolveActiveURL(for: newSettings)

            if targetURL != ctx.activeVideoURL {
                // The actual video to play changed — swap without flash
                swapRenderers(ctx)
            } else {
                // Same video — just update live properties (speed)
                applyLiveSettings(to: ctx, settings: newSettings)
            }
        }
    }

    /// Determine which URL should actually be playing right now for a given settings config.
    private func resolveActiveURL(for s: ScreenSettings) -> URL? {
        switch s.mode {
        case .idle:
            return nil
        case .video(let url):
            return url
        case .folder(let url):
            return url
        case .dayNight(_, _):
            return evaluateDayNightURL(for: s)
        }
    }

    private func applyLiveSettings(to ctx: ScreenContext, settings: ScreenSettings) {
        if let renderer = ctx.videoRenderer {
            renderer.setRate(settings.playbackSpeed)
        }
    }

    // MARK: - Pause / Resume

    private(set) var isPaused = false

    func togglePause() {
        assert(Thread.isMainThread, "WallpaperManager.togglePause must be called from main thread")
        isPaused.toggle()
        for (_, ctx) in contexts {
            if isPaused {
                pauseContext(ctx)
            } else {
                resumeContext(ctx)
            }
        }
    }

    // MARK: - Mute / Unmute

    private(set) var isMuted: Bool = false

    func toggleMute() {
        assert(Thread.isMainThread, "WallpaperManager.toggleMute must be called from main thread")
        isMuted.toggle()
        UserDefaults.standard.set(isMuted, forKey: "com.understory.isMuted")
        for (_, ctx) in contexts {
            ctx.videoRenderer?.isMuted = isMuted
        }
    }

    // MARK: - Build / Teardown (Incremental Reconciliation)

    private func reconcileContexts() {
        let currentScreens = NSScreen.screens
        var liveIDs = Set<CGDirectDisplayID>()

        for screen in currentScreens {
            let id = screenDisplayID(screen)
            liveIDs.insert(id)

            if contexts[id] == nil {
                let ctx = ScreenContext(screen: screen, displayID: id)
                contexts[id] = ctx
                setupRenderers(ctx)
            }
        }

        let staleIDs = Set(contexts.keys).subtracting(liveIDs)
        for id in staleIDs {
            if let ctx = contexts.removeValue(forKey: id) {
                teardown(ctx)
            }
        }
    }

    // MARK: - Folder Logic

    private var folderTimers: [CGDirectDisplayID: Timer] = [:]

    private func pickRandomVideo(from folderURL: URL) -> URL? {
        let fm = FileManager.default
        let ext = ["mp4", "mov", "livp"]
        guard let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return nil }
        let videoFiles = files.filter { ext.contains($0.pathExtension.lowercased()) }
        return videoFiles.randomElement()
    }

    private func startFolderTimer(for ctx: ScreenContext, folderURL: URL) {
        let id = ctx.displayID
        let screenSettings = settings[id] ?? .defaultSettings
        folderTimers[id]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: screenSettings.cycleInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.swapRenderers(ctx)
        }
        folderTimers[id] = timer
    }

    private func stopFolderTimer(for ctx: ScreenContext) {
        let id = ctx.displayID
        folderTimers[id]?.invalidate()
        folderTimers[id] = nil
    }

    // MARK: - Flash-Free Renderer Swap

    /// Sets up a new video renderer on top of the old one, starts playback,
    /// then tears down the old renderer underneath. This prevents any frame
    /// where the macOS wallpaper is visible.
    private func swapRenderers(_ ctx: ScreenContext) {
        let oldRenderer = ctx.videoRenderer
        let oldHostView = ctx.videoRenderer?.hostView

        // Stop folder timer (will be re-started by setupRenderers if needed)
        stopFolderTimer(for: ctx)

        // Set up the new renderer — this adds a new subview on top
        setupRenderers(ctx)

        // Now tear down the OLD renderer underneath
        oldRenderer?.teardown()
        oldHostView?.removeFromSuperview()
    }

    private func setupRenderers(_ ctx: ScreenContext) {
        let window = ctx.window
        let id = ctx.displayID
        let screenSettings = settings[id] ?? .defaultSettings

        var videoURLToPlay: URL?

        switch screenSettings.mode {
        case .idle:
            ctx.activeVideoURL = nil
            teardownRenderers(ctx)
            window.orderOut(nil)
            return

        case .video(let url):
            videoURLToPlay = url

        case .folder(let url):
            videoURLToPlay = pickRandomVideo(from: url)
            startFolderTimer(for: ctx, folderURL: url)

        case .dayNight(_, _):
            videoURLToPlay = evaluateDayNightURL(for: screenSettings)
        }

        guard let url = videoURLToPlay else {
            ctx.activeVideoURL = nil
            teardownRenderers(ctx)
            window.orderOut(nil)
            return
        }

        ctx.activeVideoURL = url

        // Ensure we have a persistent host view on the window
        let screen = NSScreen.screens.first(where: { screenDisplayID($0) == id })
        let frame = screen?.frame ?? NSScreen.main!.frame

        if ctx.hostView == nil {
            let host = NSView(frame: frame)
            host.wantsLayer = true
            host.autoresizingMask = [.width, .height]
            window.contentView = host
            ctx.hostView = host
        }

        guard let hostView = ctx.hostView else { return }

        let videoRenderer = VideoRenderer()
        videoRenderer.isMuted = isMuted
        videoRenderer.playbackSpeed = screenSettings.playbackSpeed
        videoRenderer.setup(url: url, in: hostView)

        ctx.videoRenderer = videoRenderer

        ctx.lifecycleManager = LifecycleManager(window: window) { [weak videoRenderer, weak self] visible in
            guard let self = self, !self.isPaused else { return }
            visible ? videoRenderer?.play() : videoRenderer?.pause()
        }

        window.orderFrontRegardless()
        videoRenderer.play()
    }

    private func teardownRenderers(_ ctx: ScreenContext) {
        stopFolderTimer(for: ctx)
        ctx.videoRenderer?.teardown()
        ctx.videoRenderer = nil
        ctx.lifecycleManager = nil
        ctx.activeVideoURL = nil
        // NOTE: we do NOT nil out ctx.hostView or window.contentView here
        // to avoid flashing the macOS wallpaper.
    }

    private func teardown(_ ctx: ScreenContext) {
        teardownRenderers(ctx)
        ctx.hostView = nil
        ctx.window.contentView = nil
        ctx.window.orderOut(nil)
    }

    private func pauseContext(_ ctx: ScreenContext) {
        ctx.videoRenderer?.pause()
    }

    private func resumeContext(_ ctx: ScreenContext) {
        ctx.videoRenderer?.play()
    }

    // MARK: - Day/Night Evaluator

    private func evaluateDayNightURL(for settings: ScreenSettings) -> URL? {
        guard case .dayNight(let dayURL, let nightURL) = settings.mode else { return nil }

        let isNight: Bool
        switch settings.dayNightSchedule {
        case .systemAppearance:
            isNight = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        case .customTimes(let nightFrom, let nightTo):
            let hour = Calendar.current.component(.hour, from: Date())
            if nightFrom <= nightTo {
                // e.g. nightFrom=1, nightTo=6 → night is [1, 6)
                isNight = hour >= nightFrom && hour < nightTo
            } else {
                // e.g. nightFrom=19, nightTo=7 → night is [19, 24) ∪ [0, 7)
                isNight = hour >= nightFrom || hour < nightTo
            }
        }
        return isNight ? nightURL : dayURL
    }

    // MARK: - Screen Changes

    private var themeObserver: Any?
    private var customTimeTimer: Timer?

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: .understoryScreensChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.debouncedReconcile()
        }

        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThemeChange()
        }

        customTimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkCustomTimeSchedules()
        }
    }

    private func handleThemeChange() {
        for (id, ctx) in contexts {
            let s = settings[id] ?? .defaultSettings
            guard case .dayNight(_, _) = s.mode,
                  case .systemAppearance = s.dayNightSchedule else { continue }

            let newURL = evaluateDayNightURL(for: s)
            if newURL != ctx.activeVideoURL {
                swapRenderers(ctx)
            }
        }
    }

    private func checkCustomTimeSchedules() {
        for (id, ctx) in contexts {
            let s = settings[id] ?? .defaultSettings
            guard case .dayNight(_, _) = s.mode,
                  case .customTimes(_, _) = s.dayNightSchedule else { continue }

            let newURL = evaluateDayNightURL(for: s)
            if newURL != ctx.activeVideoURL {
                swapRenderers(ctx)
            }
        }
    }

    private func debouncedReconcile() {
        screenChangeDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reconcileContexts()
        }
        screenChangeDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - Helpers

    func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    // MARK: - Persistence (Security-Scoped Bookmarks for Sandbox)

    private static let settingsKey = "com.understory.screenSettings"
    private static let bookmarksKey = "com.understory.videoBookmarks"

    private func persistSettings() {
        if let data = settings.encode() {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }

        var bookmarks: [String: Data] = [:]
        for (_, screenSetting) in settings {
            let urls: [URL]
            switch screenSetting.mode {
            case .idle: urls = []
            case .video(let url), .folder(let url): urls = [url]
            case .dayNight(let d, let n): urls = [d, n]
            }

            for url in urls {
                if let bookmark = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    bookmarks[url.path] = bookmark
                }
            }
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
    }

    private func loadPersistedMode() {
        if let bookmarks = UserDefaults.standard.dictionary(forKey: Self.bookmarksKey) as? [String: Data] {
            for (_, bookmarkData) in bookmarks {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    _ = url.startAccessingSecurityScopedResource()
                }
            }
        }

        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = Dictionary<CGDirectDisplayID, ScreenSettings>.decode(from: data) {
            self.settings = decoded
        } else {
            self.settings = [:]
        }

        isMuted = UserDefaults.standard.bool(forKey: "com.understory.isMuted")
    }
}
