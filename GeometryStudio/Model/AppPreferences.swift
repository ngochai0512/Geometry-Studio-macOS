import Foundation

/// Defaults for new sketches. A document keeps its own `CanvasSettings`, so
/// changing these never rewrites a sketch that is already open.
enum AppPreferences {
    enum Keys {
        static let lengthUnit = "newSketch.lengthUnit"
        static let angleUnit = "newSketch.angleUnit"
        static let precision = "newSketch.precision"
        static let grid = "newSketch.grid"
        static let gridType = "newSketch.gridType"
        static let axes = "newSketch.axes"
        static let snap = "newSketch.snap"
        static let showLabels = "newSketch.showLabels"
    }

    static func canvasSettings(from defaults: UserDefaults = .standard) -> CanvasSettings {
        var settings = CanvasSettings()
        if let raw = defaults.string(forKey: Keys.lengthUnit),
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
        if defaults.object(forKey: Keys.axes) != nil {
            settings.axes = defaults.bool(forKey: Keys.axes)
        }
        if defaults.object(forKey: Keys.snap) != nil {
            settings.snap = defaults.bool(forKey: Keys.snap)
        }
        if defaults.object(forKey: Keys.showLabels) != nil {
            settings.showLabels = defaults.bool(forKey: Keys.showLabels)
        }
        return settings
    }
}
