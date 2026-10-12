import Foundation

enum RideLiveActivityActionError: LocalizedError {
    case rideUnavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .rideUnavailable:
            "This ride is no longer active."
        case .saveFailed:
            "Your ride couldn’t be updated. Open Spoke and try again."
        }
    }
}
