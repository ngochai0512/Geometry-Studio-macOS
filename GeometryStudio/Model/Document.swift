import Foundation

struct CanvasSettings: Codable, Hashable {
    var grid: Bool = true
    var axes: Bool = true
    var snap: Bool = false
    var showLabels: Bool = true
    // Defaults read from the original's preference initialiser (routine):
    // distance unit index 2 (inches), precision 2 (hundredths). The distance
    // factor table there is [1, 72/2.54, 72], so index 2 is inches.
    var lengthUnit: LengthUnit = .inches
    var angleUnit: AngleUnit = .degrees
    var precision: Int = 2
    var scale: Double = SketchMetrics.pixelsPerCentimetre
    var center: Vec2 = Vec2(0, 0)
}

struct SketchDocument: Codable {
    var objects: [SketchObject] = []
    var settings: CanvasSettings = CanvasSettings()
    var title: String = "Untitled Sketch"
}
