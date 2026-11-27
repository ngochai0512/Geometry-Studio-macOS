import Foundation

/// The constructed straight objects that are not a single segment between two
/// selected points: perpendicular bisectors, tangents and radical axes.
enum ConstructionKind: Codable, Hashable {
    case perpendicularBisector(a: UUID, b: UUID)
    case tangentPointToCircle(point: UUID, circle: UUID, index: Int)
    case tangentCircleToCircle(a: UUID, b: UUID, index: Int)
    case radicalAxis(a: UUID, b: UUID)
}
