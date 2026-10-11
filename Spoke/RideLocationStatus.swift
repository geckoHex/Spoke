import Foundation

enum RideLocationStatus {
    case acquiring, recording, unavailable, denied, restricted

    var title: String {
        switch self {
        case .acquiring: "Finding GPS…"
        case .recording: "Recording"
        case .unavailable: "GPS unavailable"
        case .denied: "Location access off"
        case .restricted: "Location access restricted"
        }
    }

    var symbol: String {
        switch self {
        case .recording: "record.circle"
        case .acquiring: "location"
        default: "location.slash"
        }
    }

    func receiving(hasUsableLocation: Bool, stationary: Bool) -> Self {
        if hasUsableLocation { return .recording }
        if stationary { return self == .recording ? .recording : .acquiring }
        return .unavailable
    }
}
