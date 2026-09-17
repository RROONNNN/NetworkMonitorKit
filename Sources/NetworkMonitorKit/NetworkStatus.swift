import Foundation

public enum NetworkStatus: Equatable, Sendable {

    case wifi

    case cellular

    case ethernet

    case other

    case offline

    case unknown

    public var displayName: String {
        switch self {
        case .wifi:
            return "Wi-Fi"

        case .cellular:
            return "Cellular"

        case .ethernet:
            return "Ethernet"

        case .other:
            return "Other"

        case .offline:
            return "Offline"

        case .unknown:
            return "Unknown"
        }
    }

    public var symbolName: String {
        switch self {
        case .wifi:
            return "wifi"

        case .cellular:
            return "antenna.radiowaves.left.and.right"

        case .ethernet:
            return "network"

        case .other:
            return "network"

        case .offline:
            return "wifi.slash"

        case .unknown:
            return "questionmark.circle"
        }
    }
}
