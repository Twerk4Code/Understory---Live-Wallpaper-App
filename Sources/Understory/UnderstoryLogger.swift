import os

struct UnderstoryLogger {
    enum Category: String {
        case video = "com.understory.video"
        case settings = "com.understory.settings"
        case notch = "com.understory.notch"
        case lifecycle = "com.understory.lifecycle"
        case general = "com.understory.general"
    }

    static let video = OSLog(subsystem: "com.understory", category: Category.video.rawValue)
    static let settings = OSLog(subsystem: "com.understory", category: Category.settings.rawValue)
    static let notch = OSLog(subsystem: "com.understory", category: Category.notch.rawValue)
    static let lifecycle = OSLog(subsystem: "com.understory", category: Category.lifecycle.rawValue)
    static let general = OSLog(subsystem: "com.understory", category: Category.general.rawValue)

    static func logError(_ error: Error, in category: OSLog) {
        os_log("Error: %{public}@", log: category, type: .error, error.localizedDescription)
    }

    static func logInfo(_ message: String, in category: OSLog) {
        os_log("%{public}@", log: category, type: .info, message)
    }

    static func logDebug(_ message: String, in category: OSLog) {
        os_log("%{public}@", log: category, type: .debug, message)
    }
}
