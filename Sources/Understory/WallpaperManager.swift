import AppKit

// MARK: - WallpaperMode
enum WallpaperMode: Codable, Equatable {
    case idle          // No video selected — native desktop wallpaper shows through
    case video(url: URL)
}

// MARK: - Per-Screen Context
// Groups a window, renderers, display-link, and lifecycle manager for one monitor.
private final class ScreenContext {
    let screen: NSScreen
    let window: WallpaperWindow
    var videoRenderer: VideoRenderer?
    var lifecycleManager: LifecycleManager?

    init(screen: NSScreen) {
        self.screen = screen
        self.window = WallpaperWindow(for: screen)
    }
}

// MARK: - WallpaperManager
// Central coordinator: one WallpaperWindow per screen.
// Defaults to .idle (native wallpaper) until the user picks a video.
final class WallpaperManager {

    private var contexts: [ScreenContext] = []
    private(set) var mode: WallpaperMode = .idle
    private var screenObserver: Any?
    private var screenChangeDebounce: DispatchWorkItem?

    init() {
        loadPersistedMode()
    }

    // MARK: - Lifecycle

    func start() {
        buildContexts()
        observeScreenChanges()
    }

    func stop() {
        for ctx in contexts {
            teardown(ctx)
        }
        contexts.removeAll()
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
    }

    // MARK: - Mode Switching

    func setMode(_ newMode: WallpaperMode) {
        guard newMode != mode else { return }
        mode = newMode
        persistMode()
        for ctx in contexts {
            teardownRenderers(ctx)
            setupRenderers(ctx)
        }
    }

    // MARK: - Pause / Resume

    private(set) var isPaused = false

    func togglePause() {
        isPaused.toggle()
        for ctx in contexts {
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
        isMuted.toggle()
        UserDefaults.standard.set(isMuted, forKey: "com.understory.isMuted")
        for ctx in contexts {
            ctx.videoRenderer?.isMuted = isMuted
        }
    }

    // MARK: - Build / Teardown

    private func buildContexts() {
        // Remove old
        for ctx in contexts { teardown(ctx) }
        contexts.removeAll()

        for screen in NSScreen.screens {
            let ctx = ScreenContext(screen: screen)
            setupRenderers(ctx)
            // setupRenderers handles window visibility:
            //   .idle  → orderOut (hidden, native wallpaper shows)
            //   .video → orderFrontRegardless (video plays)
            contexts.append(ctx)
        }
    }

    private func setupRenderers(_ ctx: ScreenContext) {
        let screen = ctx.screen
        let window = ctx.window

        switch mode {
        case .idle:
            // No rendering — hide the window so the native desktop wallpaper shows through
            window.orderOut(nil)
            return

        case .video(let url):
            let hostView = NSView(frame: screen.frame)
            hostView.wantsLayer = true
            hostView.autoresizingMask = [.width, .height]
            window.contentView = hostView

            let videoRenderer = VideoRenderer()
            videoRenderer.isMuted = isMuted
            videoRenderer.setup(url: url, in: hostView)
            ctx.videoRenderer = videoRenderer

            // Lifecycle
            ctx.lifecycleManager = LifecycleManager(window: window) { [weak videoRenderer, weak self] visible in
                guard let self = self, !self.isPaused else { return }
                visible ? videoRenderer?.play() : videoRenderer?.pause()
            }

            window.orderFrontRegardless()
            videoRenderer.play()
        }
    }

    private func teardownRenderers(_ ctx: ScreenContext) {
        ctx.videoRenderer?.teardown()
        ctx.videoRenderer = nil
        ctx.lifecycleManager = nil
        ctx.window.contentView = nil
    }

    private func teardown(_ ctx: ScreenContext) {
        teardownRenderers(ctx)
        ctx.window.orderOut(nil)
    }

    private func pauseContext(_ ctx: ScreenContext) {
        ctx.videoRenderer?.pause()
    }

    private func resumeContext(_ ctx: ScreenContext) {
        ctx.videoRenderer?.play()
    }

    // MARK: - Screen Changes

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: .understoryScreensChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.debouncedBuildContexts()
        }
    }

    /// Debounce rapid-fire screen-change notifications (macOS sends several on hotplug).
    private func debouncedBuildContexts() {
        screenChangeDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.buildContexts()
        }
        screenChangeDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - Helpers

    private func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    // MARK: - Persistence (Security-Scoped Bookmarks for Sandbox)

    private static let modeKey = "com.understory.wallpaperMode"
    private static let bookmarkKey = "com.understory.videoBookmark"
    private static let videoURLKey = "com.understory.videoURL"

    private func persistMode() {
        switch mode {
        case .idle:
            UserDefaults.standard.removeObject(forKey: Self.modeKey)
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: Self.videoURLKey)
        case .video(let url):
            UserDefaults.standard.set("video", forKey: Self.modeKey)
            UserDefaults.standard.set(url.path, forKey: Self.videoURLKey)
            // Save a security-scoped bookmark for sandbox persistence
            if let bookmark = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            }
        }
    }

    private func loadPersistedMode() {
        let stored = UserDefaults.standard.string(forKey: Self.modeKey)
        if stored == "video" {
            // Try security-scoped bookmark first (works in sandbox)
            if let bookmarkData = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    _ = url.startAccessingSecurityScopedResource()
                    mode = .video(url: url)
                    isMuted = UserDefaults.standard.bool(forKey: "com.understory.isMuted")
                    return
                }
            }
            // Fallback: try plain path (non-sandboxed builds)
            if let path = UserDefaults.standard.string(forKey: Self.videoURLKey),
               FileManager.default.fileExists(atPath: path) {
                mode = .video(url: URL(fileURLWithPath: path))
                isMuted = UserDefaults.standard.bool(forKey: "com.understory.isMuted")
                return
            }
        }
        mode = .idle
        isMuted = UserDefaults.standard.bool(forKey: "com.understory.isMuted")
    }
}
