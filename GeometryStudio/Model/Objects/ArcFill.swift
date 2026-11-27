import Foundation

/// How an arc fills the region it cuts from its circle.
enum ArcFill: String, Codable, CaseIterable, Identifiable {
    case none
    case sector
    case segment
    var id: String {
        rawValue
    }
    var title: String {
        switch self {
        case .none:
            return "None"
        case .sector:
            return "Sector"
        case .segment:
            return "Segment"
        }
    }
}
