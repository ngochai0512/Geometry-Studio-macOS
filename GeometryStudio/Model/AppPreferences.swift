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
        static let gridColor = "newSketch.gridColor"
        static let gridBold = "newSketch.gridBold"
        static let backgroundColor = "newSketch.backgroundColor"
        static let useMetalRenderer = "newSketch.useMetalRenderer"
        static let axes = "newSketch.axes"
        static let axesLabels = "newSketch.axesLabels"
        static let axesLabelBold = "newSketch.axesLabelBold"
        static let axesLabelItalic = "newSketch.axesLabelItalic"
        static let axesLabelSerif = "newSketch.axesLabelSerif"
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
        if defaults.object(forKey: Keys.axesLabelItalic) != nil {
            settings.axesLabelStyle.italic = defaults.bool(forKey: Keys.axesLabelItalic)
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
        return settings
    }

    /// Writes the new-sketch defaults. Scale and centre are intentionally not
    /// stored: every new document starts at the standard zoom and origin.
    static func save(_ settings: CanvasSettings, to defaults: UserDefaults = .standard) {
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
        defaults.set(settings.axesLabelStyle.italic, forKey: Keys.axesLabelItalic)
        defaults.set(settings.axesLabelStyle.serif, forKey: Keys.axesLabelSerif)
        defaults.set(settings.snap, forKey: Keys.snap)
        defaults.set(settings.showLabels, forKey: Keys.showLabels)
    }
}
