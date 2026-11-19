import Foundation

enum LengthUnit: String, Codable, CaseIterable, Identifiable {
    case cm, inches, pixels
    var id: String {
        rawValue
    }
    var name: String {
        self == .cm ? "Centimeters" : self == .inches ? "Inches" : "Pixels"
    }
    var short: String {
        self == .cm ? "cm" : self == .inches ? "in" : "px"
    }

    /// The original keeps canvases in screen points and converts for display:
    /// `routine` builds the factor table `[1, 72 / 2.54, 72]` for the three
    /// distance units, and `routine` divides the stored value by the selected
    /// factor. Read that as pixels, centimetres, inches. This rebuild stores
    /// world coordinates in centimetres, so these are centimetres per one
    /// display unit. (Pixels is the original's 72-ppi point, not a 96-dpi CSS
    /// pixel.)
    var perUnit: Double {
        switch self {
        case .cm: return 1
        case .inches: return 2.54
        case .pixels: return SketchMetrics.centimetresPerInch / SketchMetrics.pointsPerInch
        }
    }
}

enum SketchMetrics {
    /// Classic Mac screen resolution used by the original: 72 points per inch.
    static let pointsPerInch = 72.0
    static let centimetresPerInch = 2.54
    /// 100% zoom: 72 points per inch ÷ 2.54 cm per inch.
    static let pixelsPerCentimetre = pointsPerInch / centimetresPerInch
}

enum AngleUnit: String, Codable, CaseIterable, Identifiable {
    case degrees, directedDegrees, radians
    var id: String {
        rawValue
    }
    var name: String {
        switch self {
        case .degrees: return "Degrees"
        case .directedDegrees: return "Directed degrees"
        case .radians: return "Radians"
        }
    }
    var short: String {
        self == .radians ? "rad" : "°"
    }
}
