import SwiftUI

enum SketchTool: String, CaseIterable, Identifiable {
    case select
    case pan
    case point
    case segment
    case ray
    case line
    case circle
    case polygon
    case angle
    case text
    var id: String {
        rawValue
    }
    var title: String {
        switch self {
        case .select:
            return "Select"
        case .pan:
            return "Pan"
        case .point:
            return "Point"
        case .segment:
            return "Segment"
        case .ray:
            return "Ray"
        case .line:
            return "Line"
        case .circle:
            return "Circle"
        case .polygon:
            return "Polygon"
        case .angle:
            return "Angle"
        case .text:
            return "Text"
        }
    }
    var symbol: String {
        switch self {
        case .select:
            return "cursorarrow"
        case .pan:
            return "hand.raised"
        case .point:
            return "dot.square"
        case .segment:
            return "line.diagonal"
        case .ray:
            return "arrow.up.right"
        case .line:
            return "arrow.down.left.and.arrow.up.right"
        case .circle:
            return "circle"
        case .polygon:
            return "pentagon"
        case .angle:
            return "angle"
        case .text:
            return "textformat"
        }
    }
    var shortcut: KeyEquivalent {
        switch self {
        case .select:
            return "v"
        case .pan:
            return "h"
        case .point:
            return "p"
        case .segment:
            return "s"
        case .ray:
            return "r"
        case .line:
            return "l"
        case .circle:
            return "c"
        case .polygon:
            return "g"
        case .angle:
            return "a"
        case .text:
            return "t"
        }
    }
    var hint: String {
        switch self {
        case .select:
            return "Click to select. Drag a point to move it. Shift-click adds to the selection."
        case .pan:
            return "Drag the canvas to move the view. Scroll or pinch to zoom."
        case .point:
            return "Click empty space for a free point, or click a line or circle to attach a point to it."
        case .segment:
            return "Click two points to draw a segment."
        case .ray:
            return "Click a start point, then a point the ray passes through."
        case .line:
            return "Click two points to draw an infinite line."
        case .circle:
            return "Click the center, then a point on the circle."
        case .polygon:
            return "Click the vertices. Click the first point again or press Return to close."
        case .angle:
            return "Click three points: first side, vertex, second side."
        case .text:
            return "Click the canvas to add a caption."
        }
    }
}

// MARK: - The editing model
