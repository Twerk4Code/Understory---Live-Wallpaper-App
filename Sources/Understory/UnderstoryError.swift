import Foundation
import os

enum UnderstoryError: LocalizedError {
    case videoLoadFailed(String)
    case settingsPersistenceFailed(Error)
    case livpExtractionFailed(Error)
    case notchDetectionFailed
    case rendererSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .videoLoadFailed(let reason):
            return "Failed to load video: \(reason)"
        case .settingsPersistenceFailed(let error):
            return "Failed to save settings: \(error.localizedDescription)"
        case .livpExtractionFailed(let error):
            return "Failed to extract Live Photo: \(error.localizedDescription)"
        case .notchDetectionFailed:
            return "Unable to detect notch configuration"
        case .rendererSetupFailed(let reason):
            return "Failed to set up video renderer: \(reason)"
        }
    }
}
