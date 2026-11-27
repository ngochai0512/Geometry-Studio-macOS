import SwiftUI
import AppKit

extension InspectorView {

    func needsLabel(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection, .angle, .parameter:
            return true
        case .graph(.table):
            return true
        default:
            return false
        }
    }

    func isMeasurement(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .angle:
            return true
        default:
            return false
        }
    }

    func isLineObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector,
             .construction, .vector:
            return true
        case .graph(.derivative), .graph(.tangent):
            return true
        default:
            return false
        }
    }

    func isArcObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .arcOnCircle, .arcThroughPoints:
            return true
        default:
            return false
        }
    }

    func isRegionObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .circle, .circleRadius, .polygon:
            return true
        case .graph(.integral):
            return true
        default:
            return false
        }
    }

    func isMeasureObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .caption, .angle, .functionPlot:
            return true
        default:
            return false
        }
    }

    func isConstructionObject(_ object: SketchObject) -> Bool {
        if case .construction = object.kind {
            return true
        }
        return false
    }

    func isParameterObject(_ object: SketchObject) -> Bool {
        if case .parameter = object.kind {
            return true
        }
        return false
    }

    func isCoordinateObject(_ object: SketchObject) -> Bool {
        if case .coordinateSystem = object.kind {
            return true
        }
        return false
    }

    func isGraphObject(_ object: SketchObject) -> Bool {
        if case .graph = object.kind {
            return true
        }
        return false
    }

    func isVectorObject(_ object: SketchObject) -> Bool {
        if case .vector = object.kind {
            return true
        }
        return false
    }

    func isTransformedObject(_ object: SketchObject) -> Bool {
        if case .transformed = object.kind {
            return true
        }
        return false
    }

    func isLocusObject(_ object: SketchObject) -> Bool {
        if case .locus = object.kind {
            return true
        }
        return false
    }

    func typeDescription(_ object: SketchObject) -> String {
        switch object.kind {
        case .freePoint:
            return "Free point"
        case .pointOnPath:
            return "Point on an object"
        case .midpoint:
            return "Constructed midpoint"
        case .intersection:
            return "Constructed intersection"
        case .segment:
            return "Segment"
        case .ray:
            return "Ray"
        case .line:
            return "Line"
        case .perpendicular:
            return "Perpendicular line"
        case .parallel:
            return "Parallel line"
        case .angleBisector:
            return "Angle bisector"
        case .circle:
            return "Circle"
        case .circleRadius:
            return "Circle by radius"
        case .arcOnCircle:
            return "Arc on a circle"
        case .arcThroughPoints:
            return "Arc through three points"
        case .polygon:
            return "Polygon interior"
        case .angle:
            return "Angle marker"
        case .measurement(let kind, _):
            return "\(kind.title) measurement"
        case .calculation:
            return "Calculation"
        case .caption:
            return "Caption"
        case .functionPlot:
            return "Function plot"
        case .transformed(_, let spec):
            return "\(spec.kind.title) image"
        case .locus:
            return "Locus"
        case .parameter:
            return "Parameter"
        case .construction(let kind):
            switch kind {
            case .perpendicularBisector:
                return "Perpendicular bisector"
            case .tangentPointToCircle:
                return "Tangent from a point"
            case .tangentCircleToCircle:
                return "Common tangent"
            case .radicalAxis:
                return "Radical axis"
            }
        case .vector(let kind):
            switch kind {
            case .fromPoints:
                return "Vector"
            case .sum(_, _, let subtract):
                return subtract ? "Vector difference" : "Vector sum"
            }
        case .coordinateSystem(let kind, _, _, _):
            return "\(kind.title) coordinate system"
        case .graph(let feature):
            switch feature {
            case .derivative:
                return "Derivative plot"
            case .integral:
                return "Integral shading"
            case .tangent:
                return "Tangent line"
            case .table:
                return "Value table"
            }
        }
    }
}
