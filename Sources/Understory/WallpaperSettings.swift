import AppKit

// MARK: - DayNightScheduleType
enum DayNightScheduleType: Codable, Equatable {
    case systemAppearance
    case customTimes(nightFromHour: Int, nightToHour: Int) // Night plays during [from, to) range
}

// MARK: - WallpaperMode
enum WallpaperMode: Codable, Equatable {
    case idle
    case video(url: URL)
    case folder(url: URL)
    case dayNight(dayURL: URL, nightURL: URL)
}

// MARK: - ScreenSettings
struct ScreenSettings: Codable, Equatable {
    var mode: WallpaperMode
    var playbackSpeed: Float
    var tintColorHex: String? // Kept for backwards Codable compatibility
    var tintAlpha: CGFloat    // Kept for backwards Codable compatibility
    var dayNightSchedule: DayNightScheduleType
    var cycleInterval: TimeInterval
    
    // Remember last picks to avoid re-prompting when switching modes
    var lastVideoURL: URL?
    var lastFolderURL: URL?
    var lastDayURL: URL?
    var lastNightURL: URL?
    
    // Default settings
    static let defaultSettings = ScreenSettings(
        mode: .idle,
        playbackSpeed: 1.0,
        tintColorHex: nil,
        tintAlpha: 0.0,
        dayNightSchedule: .systemAppearance,
        cycleInterval: 600.0, // 10 minutes default
        lastVideoURL: nil,
        lastFolderURL: nil,
        lastDayURL: nil,
        lastNightURL: nil
    )
    
    // Helper to get NSColor from hex (unused but kept for compat)
    var tintColor: NSColor? {
        guard let hex = tintColorHex else { return nil }
        return NSColor(hexString: hex)
    }
}

// MARK: - Dictionary Extensions for UserDefaults
extension Dictionary where Key == CGDirectDisplayID, Value == ScreenSettings {
    func encode() -> Data? {
        let stringKeyedDict = Dictionary<String, ScreenSettings>(uniqueKeysWithValues: self.map { (String($0.key), $0.value) })
        return try? JSONEncoder().encode(stringKeyedDict)
    }
    
    static func decode(from data: Data) -> [CGDirectDisplayID: ScreenSettings]? {
        guard let stringKeyedDict = try? JSONDecoder().decode([String: ScreenSettings].self, from: data) else { return nil }
        return Dictionary(uniqueKeysWithValues: stringKeyedDict.compactMap {
            if let uintKey = UInt32($0.key) {
                return (uintKey, $0.value)
            }
            return nil
        })
    }
}

// MARK: - NSColor Hex Extension
extension NSColor {
    convenience init?(hexString: String) {
        var hexSanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    var hexString: String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return "#FFFFFF"
        }
        let r = Int(round(rgbColor.redComponent * 255.0))
        let g = Int(round(rgbColor.greenComponent * 255.0))
        let b = Int(round(rgbColor.blueComponent * 255.0))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
