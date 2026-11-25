import Foundation

/// A coarse object family used by the appearance defaults.
enum AppearanceFamily: String, CaseIterable, Identifiable {
    case point
    case line
    case circle
    case region
    case measure

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .point:
            return "Points"
        case .line:
            return "Lines & Segments"
        case .circle:
            return "Circles & Arcs"
        case .region:
            return "Polygons"
        case .measure:
            return "Measurements"
        }
    }

    static func family(for kind: ObjectKind) -> AppearanceFamily? {
        switch kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return .point
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector,
             .construction, .vector, .functionPlot, .coordinateSystem:
            return .line
        case .graph(.derivative), .graph(.tangent):
            return .line
        case .circle, .circleRadius, .arcOnCircle, .arcThroughPoints:
            return .circle
        case .polygon, .graph(.integral):
            return .region
        case .measurement, .calculation, .angle, .parameter, .graph(.table):
            return .measure
        default:
            return nil
        }
    }
}

/// Default object colours for newly created geometry. Existing objects keep
/// their stored style, so changing these never recolours an open sketch.
struct AppearancePreferences: Codable, Hashable {
    var pointColor: RGBA = .black
    var lineColor: RGBA = .black
    var circleColor: RGBA = .black
    var regionColor: RGBA = .black
    var measureColor: RGBA = .black

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pointColor = try c.decodeIfPresent(RGBA.self, forKey: .pointColor) ?? .black
        lineColor = try c.decodeIfPresent(RGBA.self, forKey: .lineColor) ?? .black
        circleColor = try c.decodeIfPresent(RGBA.self, forKey: .circleColor) ?? .black
        regionColor = try c.decodeIfPresent(RGBA.self, forKey: .regionColor) ?? .black
        measureColor = try c.decodeIfPresent(RGBA.self, forKey: .measureColor) ?? .black
    }

    func color(for family: AppearanceFamily) -> RGBA {
        switch family {
        case .point:
            return pointColor
        case .line:
            return lineColor
        case .circle:
            return circleColor
        case .region:
            return regionColor
        case .measure:
            return measureColor
        }
    }

    mutating func setColor(_ color: RGBA, for family: AppearanceFamily) {
        switch family {
        case .point:
            pointColor = color
        case .line:
            lineColor = color
        case .circle:
            circleColor = color
        case .region:
            regionColor = color
        case .measure:
            measureColor = color
        }
    }
}

/// Defaults for new sketches. A document keeps its own `CanvasSettings`, so
/// changing these never rewrites a sketch that is already open.
enum AppPreferences {
    static let currentDefaultsVersion = 2

    enum Keys {
        static let defaultsVersion = "defaults.version"
        static let lengthUnit = "newSketch.lengthUnit"
        static let angleUnit = "newSketch.angleUnit"
        static let precision = "newSketch.precision"
        static let grid = "newSketch.grid"
        static let gridType = "newSketch.gridType"
        static let gridColor = "newSketch.gridColor"
        static let gridBold = "newSketch.gridBold"
        static let backgroundColor = "newSketch.backgroundColor"
        static let useMetalRenderer = "newSketch.useMetalRenderer"
        static let axes = "newSketch.axes"
        static let axesLabels = "newSketch.axesLabels"
        static let axesLabelBold = "newSketch.axesLabelBold"
        static let axesLabelSerif = "newSketch.axesLabelSerif"
        static let snap = "newSketch.snap"
        static let showLabels = "newSketch.showLabels"
        static let smartGuides = "newSketch.smartGuides"
        static let angleSnap = "newSketch.angleSnap"
        static let appearance = "appearance.defaults"
        static let onboardingCompleted = "onboarding.completed"
    }

    static func canvasSettings(from defaults: UserDefaults = .standard) -> CanvasSettings {
        var settings = CanvasSettings()
        let version = defaults.integer(forKey: Keys.defaultsVersion)
        if version >= currentDefaultsVersion,
           let raw = defaults.string(forKey: Keys.lengthUnit),
           let unit = LengthUnit(rawValue: raw) {
            settings.lengthUnit = unit
        }
        if let raw = defaults.string(forKey: Keys.angleUnit),
           let unit = AngleUnit(rawValue: raw) {
            settings.angleUnit = unit
        }
        if defaults.object(forKey: Keys.precision) != nil {
            settings.precision = min(max(defaults.integer(forKey: Keys.precision), 0), 5)
        }
        if defaults.object(forKey: Keys.grid) != nil {
            settings.grid = defaults.bool(forKey: Keys.grid)
        }
        if let raw = defaults.string(forKey: Keys.gridType),
           let type = GridType(rawValue: raw) {
            settings.gridType = type
        }
        if let raw = defaults.string(forKey: Keys.gridColor),
           let color = RGBA(hexString: raw) {
            settings.gridColor = color
        }
        if defaults.object(forKey: Keys.gridBold) != nil {
            settings.gridBold = defaults.bool(forKey: Keys.gridBold)
        }
        if let data = defaults.data(forKey: Keys.backgroundColor),
           let color = try? JSONDecoder().decode(RGBA.self, from: data) {
            settings.backgroundColor = color
        }
        if defaults.object(forKey: Keys.useMetalRenderer) != nil {
            settings.useMetalRenderer = defaults.bool(forKey: Keys.useMetalRenderer)
        }
        if defaults.object(forKey: Keys.axes) != nil {
            settings.axes = defaults.bool(forKey: Keys.axes)
        }
        if defaults.object(forKey: Keys.axesLabels) != nil {
            settings.axesLabels = defaults.bool(forKey: Keys.axesLabels)
        }
        if defaults.object(forKey: Keys.axesLabelBold) != nil {
            settings.axesLabelStyle.bold = defaults.bool(forKey: Keys.axesLabelBold)
        }
        if defaults.object(forKey: Keys.axesLabelSerif) != nil {
            settings.axesLabelStyle.serif = defaults.bool(forKey: Keys.axesLabelSerif)
        }
        if defaults.object(forKey: Keys.snap) != nil {
            settings.snap = defaults.bool(forKey: Keys.snap)
        }
        if defaults.object(forKey: Keys.showLabels) != nil {
            settings.showLabels = defaults.bool(forKey: Keys.showLabels)
        }
        if defaults.object(forKey: Keys.smartGuides) != nil {
            settings.smartGuides = defaults.bool(forKey: Keys.smartGuides)
        }
        if defaults.object(forKey: Keys.angleSnap) != nil {
            let stored = defaults.double(forKey: Keys.angleSnap)
            settings.angleSnap = CanvasSettings.angleSnapChoices.contains(stored) ? stored : 0
        }
        return settings
    }

    /// Writes the new-sketch defaults. Scale and centre are intentionally not
    /// stored: every new document starts at the standard zoom and origin.
    static func save(_ settings: CanvasSettings, to defaults: UserDefaults = .standard) {
        defaults.set(currentDefaultsVersion, forKey: Keys.defaultsVersion)
        defaults.set(settings.lengthUnit.rawValue, forKey: Keys.lengthUnit)
        defaults.set(settings.angleUnit.rawValue, forKey: Keys.angleUnit)
        defaults.set(settings.precision, forKey: Keys.precision)
        defaults.set(settings.grid, forKey: Keys.grid)
        defaults.set(settings.gridType.rawValue, forKey: Keys.gridType)
        defaults.set(settings.gridColor.hex, forKey: Keys.gridColor)
        defaults.set(settings.gridBold, forKey: Keys.gridBold)
        if let data = try? JSONEncoder().encode(settings.backgroundColor) {
            defaults.set(data, forKey: Keys.backgroundColor)
        }
        defaults.set(settings.useMetalRenderer, forKey: Keys.useMetalRenderer)
        defaults.set(settings.axes, forKey: Keys.axes)
        defaults.set(settings.axesLabels, forKey: Keys.axesLabels)
        defaults.set(settings.axesLabelStyle.bold, forKey: Keys.axesLabelBold)
        defaults.set(settings.axesLabelStyle.serif, forKey: Keys.axesLabelSerif)
        defaults.set(settings.snap, forKey: Keys.snap)
        defaults.set(settings.showLabels, forKey: Keys.showLabels)
        defaults.set(settings.smartGuides, forKey: Keys.smartGuides)
        defaults.set(settings.angleSnap, forKey: Keys.angleSnap)
    }

    static func appearance(from defaults: UserDefaults = .standard) -> AppearancePreferences {
        guard let data = defaults.data(forKey: Keys.appearance),
              let value = try? JSONDecoder().decode(AppearancePreferences.self, from: data) else {
            return AppearancePreferences()
        }
        return value
    }

    static func saveAppearance(_ appearance: AppearancePreferences,
                               to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(appearance) {
            defaults.set(data, forKey: Keys.appearance)
        }
    }

    /// The welcome sheet runs once per install; Help > Tips brings it back.
    static func hasCompletedOnboarding(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Keys.onboardingCompleted)
    }

    static func markOnboardingCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Keys.onboardingCompleted)
    }
}
