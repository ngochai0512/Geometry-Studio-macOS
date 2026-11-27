import Foundation

enum MeasureKind: String, Codable, CaseIterable, Identifiable {
    case distance
    case length
    case perimeter
    case circumference
    case angle
    case arcAngle
    case arcLength
    case area
    case radius
    case ratio
    case coordinates
    case abscissa
    case ordinate
    case polarDistance
    case polarDirection
    case coordinateDistance
    case equation
    case slope
    var id: String {
        rawValue
    }
    var title: String {
        switch self {
        case .distance:
            return "Distance"
        case .length:
            return "Length"
        case .perimeter:
            return "Perimeter"
        case .circumference:
            return "Circumference"
        case .angle:
            return "Angle"
        case .arcAngle:
            return "Arc Angle"
        case .arcLength:
            return "Arc Length"
        case .area:
            return "Area"
        case .radius:
            return "Radius"
        case .ratio:
            return "Ratio"
        case .coordinates:
            return "Coordinates"
        case .abscissa:
            return "Abscissa"
        case .ordinate:
            return "Ordinate"
        case .polarDistance:
            return "Polar Distance"
        case .polarDirection:
            return "Polar Direction"
        case .coordinateDistance:
            return "Coordinate Distance"
        case .equation:
            return "Equation"
        case .slope:
            return "Slope"
        }
    }
}
