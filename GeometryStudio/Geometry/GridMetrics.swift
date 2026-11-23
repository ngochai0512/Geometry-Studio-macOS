import Foundation

/// Grid spacing shared by the canvas and the SVG exporter.
///
/// The original labels the grid in the chosen distance unit, so a one-inch
/// grid is one inch wide even though world coordinates are centimetres. Step
/// the display-unit candidates until one is at least 50 screen points wide,
/// matching `CanvasDrawing.drawGrid`.
enum GridMetrics {
    private static let candidates: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100]

    /// One grid cell in world units. `minimumSpacing` is the smallest screen
    /// gap the grid may use, so the dense variant can share the candidate
    /// ladder without duplicating it.
    static func step(scale: Double, perUnit: Double, minimumSpacing: Double = 50) -> Double {
        let unit = max(perUnit, 1e-6)
        for candidate in candidates where candidate * unit * scale >= minimumSpacing {
            return candidate * unit
        }
        return (candidates.last ?? 1) * unit
    }

    /// Label every nth tick when the grid gets too dense for every label.
    static func labelEvery(step: Double, scale: Double) -> Int {
        step * scale < 55 ? 5 : 1
    }

    /// Axis and scale-bar labels drop a trailing `.0`.
    static func cleanNumber(_ value: Double) -> String {
        if abs(value - value.rounded()) < 1e-9 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}
