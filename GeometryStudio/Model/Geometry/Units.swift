import Foundation

enum LengthUnit: String, Codable, CaseIterable, Identifiable {
    case cm
    case inches
    case pixels
    var id: String {
        rawValue
    }
    var name: String {
        switch self {
        case .cm:
            return "Centimeters"
        case .inches:
            return "Inches"
        case .pixels:
            return "Pixels"
        }
    }
    var short: String {
        switch self {
        case .cm:
            return "cm"
        case .inches:
            return "in"
        case .pixels:
            return "px"
        }
    }

    /// Canvases are measured in screen points and converted for display: the
    /// factor table is `[1, 72 / 2.54, 72]` for pixels, centimetres and
    /// inches, and a stored value is divided by the selected factor. This
    /// rebuild stores world coordinates in centimetres, so these are
    /// centimetres per one display unit. (Pixels means the 72-ppi point, not a
    /// 96-dpi CSS pixel.)
    var perUnit: Double {
        switch self {
        case .cm:
            return 1
        case .inches:
            return 2.54
        case .pixels:
            return SketchMetrics.centimetresPerInch / SketchMetrics.pointsPerInch
        }
    }
}

enum SketchMetrics {
    /// Classic Mac screen resolution: 72 points per inch.
    static let pointsPerInch = 72.0
    static let centimetresPerInch = 2.54
    /// 100% zoom: 72 points per inch ÷ 2.54 cm per inch.
    static let pixelsPerCentimetre = pointsPerInch / centimetresPerInch

    /// Vector arrowheads on the canvas: screen length range and half-angle.
    /// One set of values so the printed and on-screen heads stay identical.
    static let arrowMinimumLength = 10.0
    static let arrowMaximumLength = 15.0
    static let arrowHalfAngle = 0.45

    /// Short vectors get a proportionally smaller head, never under the minimum.
    static func arrowHeadLength(for length: Double) -> Double {
        min(arrowMaximumLength, max(arrowMinimumLength, length * 0.5))
    }
}

enum AngleUnit: String, Codable, CaseIterable, Identifiable {
    case degrees
    case directedDegrees
    case radians
    var id: String {
        rawValue
    }
    var name: String {
        switch self {
        case .degrees:
            return "Degrees"
        case .directedDegrees:
            return "Directed degrees"
        case .radians:
            return "Radians"
        }
    }
    var short: String {
        switch self {
        case .degrees:
            return "°"
        case .directedDegrees:
            return "°"
        case .radians:
            return "rad"
        }
    }
}
