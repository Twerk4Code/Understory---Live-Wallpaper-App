import Foundation

struct AppConfig {
    // Video rendering
    static let maxRAMCacheSize: Int = 512 * 1024 * 1024  // 512 MB
    static let playerBufferDuration: TimeInterval = 120
    static let playerPreferredBufferDuration: TimeInterval = 120

    // Timing
    static let debounceDelay: TimeInterval = 0.5
    static let panelDismissTimeout: TimeInterval = 3.0

    // Notch display
    static let notchHoverZoneWidth: CGFloat = 280
    static let notchHoverZoneHeight: CGFloat = 60
    static let panelCornerRadius: CGFloat = 10
    static let panelAutoHideDelay: TimeInterval = 3.0

    // Playback
    static let speedRangeMin: Float = 0.25
    static let speedRangeMax: Float = 2.0

    // Folder cycling
    static let folderCycleIntervalDefault: TimeInterval = 600.0

    // Day/Night
    static let dayNightDefaultNightStart: Int = 19
    static let dayNightDefaultNightEnd: Int = 7
}
