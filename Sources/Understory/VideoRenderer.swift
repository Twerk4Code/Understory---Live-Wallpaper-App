import AppKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - VideoRenderer
// Manages an AVQueuePlayer + AVPlayerLooper to render a seamlessly looping video wallpaper.
// Loads the video file into RAM once to eliminate continuous disk I/O on loop.
// Supports .mp4, .mov, and .livp (Live Photo) files.
final class VideoRenderer {

    private var player: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var looper: AVPlayerLooper?
    private var resourceLoader: InMemoryResourceLoader?
    private(set) var hostView: NSView?

    /// Whether the video is currently playing.
    var isPlaying: Bool {
        player?.rate != 0
    }

    /// Audio mute control — propagated to the AVPlayer.
    var isMuted: Bool = false {
        didSet { player?.isMuted = isMuted }
    }

    // MARK: - Setup

    /// Creates the video renderer and loads the media at `url`.
    /// The video is read into RAM once; all subsequent loop iterations are served from memory.
    func setup(url: URL, in parentView: NSView) {
        teardown()

        let videoURL = resolveVideoURL(from: url)

        // Load the entire video file into memory to eliminate continuous disk I/O.
        // AVPlayerLooper creates multiple AVPlayerItem copies, each of which would
        // independently read from disk. By serving bytes from RAM, we read the file
        // exactly once regardless of how many times it loops.
        let loader = InMemoryResourceLoader(fileURL: videoURL)
        self.resourceLoader = loader

        let asset: AVURLAsset
        if loader.isLoaded {
            // Use the in-memory asset (custom scheme intercepted by our resource loader)
            asset = loader.asset
        } else {
            // Fallback: file too large or read failed — use direct file access
            print("⚠️ VideoRenderer: File too large for RAM cache, using disk streaming")
            asset = AVURLAsset(url: videoURL)
        }

        let templateItem = AVPlayerItem(asset: asset)
        templateItem.preferredForwardBufferDuration = 120

        let player = AVQueuePlayer(playerItem: templateItem)
        player.isMuted = isMuted
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player

        // AVPlayerLooper pre-buffers the loop point for gapless, seamless looping.
        // Since the resource loader serves from RAM, loop copies don't hit disk.
        self.looper = AVPlayerLooper(player: player, templateItem: templateItem)

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = parentView.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Host view for the AVPlayerLayer
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
        player?.play()
    }

    func pause() {
        player?.pause()
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
        resourceLoader = nil  // Release the in-memory video data
    }

    // MARK: - .livp Support

    /// If the URL is a `.livp` bundle, extract the embedded `.mov`.
    /// Otherwise return the URL as-is.
    private func resolveVideoURL(from url: URL) -> URL {
        guard url.pathExtension.lowercased() == "livp" else { return url }

        // .livp is a zip-like package; look for a .mov inside
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            for file in contents {
                let ext = file.pathExtension.lowercased()
                if ext == "mov" || ext == "mp4" {
                    return file
                }
            }
        }

        // Fallback: try treating the livp as a flat zip
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
                        return file
                    }
                }
            }
        } catch {
            print("⚠️ VideoRenderer: Failed to extract .livp: \(error)")
        }

        return url
    }
}

// MARK: - InMemoryResourceLoader
// Loads a video file into RAM and serves it to AVFoundation via a custom URL scheme.
// This prevents AVPlayerLooper's internal item copies from re-reading the file from disk.
private final class InMemoryResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

    private let videoData: Data?
    private let contentType: String
    private let loaderQueue = DispatchQueue(label: "com.understory.resourceLoader")
    let asset: AVURLAsset

    /// Maximum file size we'll load into RAM (512 MB).
    /// Videos larger than this fall back to disk streaming.
    private static let maxFileSize: Int = 512 * 1024 * 1024

    var isLoaded: Bool { videoData != nil }

    init(fileURL: URL) {
        // Determine the content type for the response
        let ext = fileURL.pathExtension.lowercased()
        if ext == "mov" {
            contentType = "com.apple.quicktime-movie"
        } else if ext == "mp4" || ext == "m4v" {
            contentType = "public.mpeg-4"
        } else {
            contentType = "public.movie"
        }

        // Check file size before loading
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        if fileSize > 0 && fileSize <= Self.maxFileSize {
            self.videoData = try? Data(contentsOf: fileURL)
        } else {
            self.videoData = nil
        }

        // Create an asset with a custom URL scheme so AVFoundation routes
        // all data requests through our delegate instead of reading from disk.
        let customURL = URL(string: "understory-mem://video.\(ext)")!
        self.asset = AVURLAsset(url: customURL)

        super.init()

        // Set ourselves as the resource loader delegate BEFORE anyone accesses the asset's tracks
        asset.resourceLoader.setDelegate(self, queue: loaderQueue)
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let data = videoData else { return false }

        // Fill in the content information
        if let contentRequest = loadingRequest.contentInformationRequest {
            contentRequest.contentType = contentType
            contentRequest.contentLength = Int64(data.count)
            contentRequest.isByteRangeAccessSupported = true
        }

        // Serve the requested byte range from our in-memory data
        if let dataRequest = loadingRequest.dataRequest {
            let requestedOffset = Int(dataRequest.requestedOffset)
            let requestedLength = dataRequest.requestedLength
            let availableLength = data.count - requestedOffset

            if availableLength <= 0 {
                loadingRequest.finishLoading()
                return true
            }

            let respondLength = min(requestedLength, availableLength)
            let range = requestedOffset ..< (requestedOffset + respondLength)
            dataRequest.respond(with: data.subdata(in: range))
            loadingRequest.finishLoading()
        }

        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        // No cleanup needed — data is served synchronously from memory
    }
}
