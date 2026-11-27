import Foundation

enum CoordinateKind: String, Codable, CaseIterable, Identifiable {
    case cartesian
    case polar

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .cartesian:
            return "Cartesian"
        case .polar:
            return "Polar"
        }
    }
}
