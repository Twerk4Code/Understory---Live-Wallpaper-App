import AppKit
import AVFoundation
import CryptoKit
import UniformTypeIdentifiers
import os

// MARK: - VideoRenderer
// Manages an AVQueuePlayer + AVPlayerLooper to render a seamlessly looping video wallpaper.
// Loads the video file into RAM once; all subsequent reads are served from memory
// via an AVAssetResourceLoaderDelegate, producing zero filesystem I/O after initial load.
// Supports .mp4, .mov, and .livp (Live Photo) files.
final class VideoRenderer {

    private var player: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var looper: AVPlayerLooper?
    private var resourceLoader: InMemoryLoader?
    private(set) var hostView: NSView?

    /// Whether the video is currently playing.
    var isPlaying: Bool {
        player?.rate != 0
    }

    /// Audio mute control — propagated to the AVPlayer.
    var isMuted: Bool = false {
        didSet { player?.isMuted = isMuted }
    }

    /// Stored playback speed. Use `setRate(_:)` to apply at runtime.
    var playbackSpeed: Float = 1.0

    /// Maximum file size we'll preload via mmap (512 MB).
    private static let maxRAMCacheSize: Int = AppConfig.maxRAMCacheSize

    // MARK: - Setup

    /// Creates the video renderer and loads the media at `url`.
    /// The video is memory-mapped once; all loop iterations are served without extra disk I/O.
    func setup(url: URL, in parentView: NSView) {
        assert(Thread.isMainThread, "VideoRenderer.setup must be called from main thread")
        teardown()

        os_log("Setting up video renderer for: %{public}@", log: UnderstoryLogger.video, type: .info, url.lastPathComponent)
        let videoURL = resolveVideoURL(from: url)

        // Determine the content type for AVFoundation
        let ext = videoURL.pathExtension.lowercased()
        let uti: String
        switch ext {
        case "mov":  uti = "com.apple.quicktime-movie"
        case "m4v":  uti = "public.mpeg-4"
        default:     uti = "public.mpeg-4"  // mp4 and others
        }

        // Memory-map the video for zero-disk-I/O playback.
        // .alwaysMapped delegates paging to the kernel VM subsystem —
        // same zero-repeated-I/O guarantee as heap-copying Data(contentsOf:),
        // but vastly lower RSS under memory pressure because the kernel
        // can page out and re-fault from the file without swap.
        let asset: AVURLAsset
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0

        if fileSize > 0 && fileSize <= Self.maxRAMCacheSize,
           let data = try? Data(contentsOf: videoURL, options: .alwaysMapped) {
            let loader = InMemoryLoader(data: data, contentType: uti)
            self.resourceLoader = loader
            asset = loader.asset
        } else {
            // Too large or read failed — fall back to standard file I/O
            os_log("File too large for mmap (%{public}@ bytes), using disk", log: UnderstoryLogger.video, type: .default, String(fileSize))
            asset = AVURLAsset(url: videoURL)
        }

        let templateItem = AVPlayerItem(asset: asset)
        templateItem.preferredForwardBufferDuration = AppConfig.playerBufferDuration

        let player = AVQueuePlayer(playerItem: templateItem)
        player.isMuted = isMuted
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player

        // AVPlayerLooper creates new AVPlayerItem copies from the SAME AVURLAsset.
        // Since the resource loader delegate is set on the asset, all copies route
        // through our in-memory delegate — no additional disk reads.
        self.looper = AVPlayerLooper(player: player, templateItem: templateItem)

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = parentView.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        let host = NSView(frame: parentView.bounds)
        host.wantsLayer = true
        host.layer?.addSublayer(layer)
        host.autoresizingMask = [.width, .height]
        parentView.addSubview(host)

        self.playerLayer = layer
        self.hostView = host
    }

    // MARK: - Playback Control

    func play() {
        assert(Thread.isMainThread, "VideoRenderer.play must be called from main thread")
        player?.play()
        if playbackSpeed != 1.0 {
            let safeRate = max(Float(0.1), min(playbackSpeed, 2.0))
            player?.rate = safeRate
        }
    }

    func pause() {
        assert(Thread.isMainThread, "VideoRenderer.pause must be called from main thread")
        player?.pause()
    }

    /// Unconditionally apply a new playback rate to the player.
    /// Unlike the `playbackSpeed` property setter, this does NOT gate on `isPlaying`,
    /// so it can never dead-lock into a stalled state during rapid slider scrubbing.
    func setRate(_ rate: Float) {
        assert(Thread.isMainThread, "VideoRenderer.setRate must be called from main thread")
        playbackSpeed = rate
        guard let player = player else { return }
        let clamped = max(Float(0.1), min(rate, 2.0))
        // If the player was paused (rate == 0), calling play() first
        // ensures we re-enter the playing state before setting the rate.
        if player.rate == 0 {
            player.play()
        }
        player.rate = clamped
    }

    func teardown() {
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        hostView?.removeFromSuperview()
        hostView = nil
        resourceLoader = nil
    }

    // MARK: - .livp Support (with caching)

    /// Cache directory for extracted .livp videos.
    private static var livpCacheDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Understory/LivpCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Deterministic cache key from a file path using SHA256.
    private func cacheKey(for url: URL) -> String {
        let hash = SHA256.hash(data: Data(url.path.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func resolveVideoURL(from url: URL) -> URL {
        guard url.pathExtension.lowercased() == "livp" else { return url }

        let fm = FileManager.default

        // .livp may be a directory (Live Photo bundle) — check for video inside
        if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            for file in contents {
                let ext = file.pathExtension.lowercased()
                if ext == "mov" || ext == "mp4" { return file }
            }
        }

        // Need to extract — check cache first
        let key = cacheKey(for: url)
        let cachedMov = Self.livpCacheDir.appendingPathComponent("\(key).mov")
        let cachedMp4 = Self.livpCacheDir.appendingPathComponent("\(key).mp4")

        if fm.fileExists(atPath: cachedMov.path) { return cachedMov }
        if fm.fileExists(atPath: cachedMp4.path) { return cachedMp4 }

        // Extract to a temp dir, then move the video into the cache
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipURL = tempDir.appendingPathComponent("livephoto.zip")
            try fm.copyItem(at: url, to: zipURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", zipURL.path, "-d", tempDir.path]
            process.standardOutput = nil
            process.standardError = nil
            try process.run()
            process.waitUntilExit()

            if let extracted = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
                for file in extracted {
                    let ext = file.pathExtension.lowercased()
                    if ext == "mov" || ext == "mp4" {
                        let cached = Self.livpCacheDir.appendingPathComponent("\(key).\(ext)")
                        try? fm.moveItem(at: file, to: cached)
                        try? fm.removeItem(at: tempDir)
                        return cached
                    }
                }
            }
            try? fm.removeItem(at: tempDir)
        } catch {
            os_log("Failed to extract .livp: %{public}@", log: UnderstoryLogger.video, type: .error, error.localizedDescription)
        }
        return url
    }
}

// MARK: - InMemoryLoader
// Serves video bytes from a memory-mapped Data object to AVFoundation
// via AVAssetResourceLoaderDelegate. Using .alwaysMapped means the kernel's
// VM pager handles the memory — zero repeated disk I/O with graceful
// page-out under memory pressure (no swap, just re-fault from the file).
//
// Thread safety: all delegate callbacks arrive on `loaderQueue` (a serial dispatch queue).
// The `videoData` is immutable after init, so it's safe to read from any thread.
private final class InMemoryLoader: NSObject, AVAssetResourceLoaderDelegate {

    /// The video bytes (memory-mapped), held for the lifetime of this loader.
    let videoData: Data

    /// UTI content type string (e.g. "public.mpeg-4", "com.apple.quicktime-movie").
    let contentType: String

    /// Serial queue for all resource loader delegate callbacks.
    private let loaderQueue = DispatchQueue(label: "com.understory.memLoader", qos: .userInitiated)

    /// The asset backed by this loader. AVFoundation routes all data requests through us.
    let asset: AVURLAsset

    init(data: Data, contentType: String) {
        self.videoData = data
        self.contentType = contentType

        // Use a custom URL scheme so AVFoundation routes through our delegate.
        // The UUID ensures uniqueness even if multiple renderers exist (multi-monitor).
        let scheme = "understory-mem"
        let uniqueID = UUID().uuidString
        let customURL = URL(string: "\(scheme)://\(uniqueID)/video")!
        self.asset = AVURLAsset(url: customURL)

        super.init()

        // IMPORTANT: set delegate BEFORE anything accesses the asset's properties.
        asset.resourceLoader.setDelegate(self, queue: loaderQueue)
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {

        // ── Content information ──────────────────────────────────────
        if let contentInfo = loadingRequest.contentInformationRequest {
            contentInfo.contentType = contentType
            contentInfo.contentLength = Int64(videoData.count)
            contentInfo.isByteRangeAccessSupported = true
        }

        // ── Data response ────────────────────────────────────────────
        if let dataRequest = loadingRequest.dataRequest {
            let startOffset: Int
            if dataRequest.currentOffset != 0 {
                startOffset = Int(dataRequest.currentOffset)
            } else {
                startOffset = Int(dataRequest.requestedOffset)
            }

            let bytesRemaining = videoData.count - startOffset
            guard bytesRemaining > 0 else {
                loadingRequest.finishLoading()
                return true
            }

            let bytesToRespond: Int
            if dataRequest.requestsAllDataToEndOfResource {
                bytesToRespond = bytesRemaining
            } else {
                let requestedLength = dataRequest.requestedLength
                let alreadyResponded = startOffset - Int(dataRequest.requestedOffset)
                bytesToRespond = min(requestedLength - alreadyResponded, bytesRemaining)
            }

            guard bytesToRespond > 0 else {
                loadingRequest.finishLoading()
                return true
            }

            // Serve bytes directly from mmap'd pages — no filesystem access
            videoData.withUnsafeBytes { rawBuffer in
                let ptr = rawBuffer.baseAddress!.advanced(by: startOffset)
                dataRequest.respond(with: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: ptr),
                                               count: bytesToRespond,
                                               deallocator: .none))
            }

            loadingRequest.finishLoading()
        }

        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        // Nothing to clean up — responses are synchronous from memory
    }
}
