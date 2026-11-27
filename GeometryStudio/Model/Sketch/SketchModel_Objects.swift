import SwiftUI

extension SketchModel {

    func index(of id: UUID) -> Int? {
        objects.firstIndex(where: { $0.id == id })
    }

    func objectByID(_ id: UUID) -> SketchObject? {
        objects.first(where: { $0.id == id })
    }

    /// The colour family defaults applied to a newly created object.
    func defaultObjectStyle(for kind: ObjectKind) -> ObjectStyle {
        var style = ObjectStyle()
        if let family = AppearanceFamily.family(for: kind) {
            style.color = AppPreferences.appearance().color(for: family)
        }
        return style
    }

    func makeObject(kind: ObjectKind) -> SketchObject {
        var object = SketchObject(kind: kind)
        object.style = defaultObjectStyle(for: kind)
        return object
    }

    @discardableResult
    func add(kind: ObjectKind,
             label: String? = nil,
             kindLabel: String? = nil,
             position: Vec2? = nil,
             style: ObjectStyle? = nil,
             silent: Bool = false) -> UUID {
        if !silent {
            let name = label ?? kindLabel
            if let name, !name.isEmpty {
                checkpoint("Add \(name)")
            } else {
                checkpoint("Add Object")
            }
        }
        var object = makeObject(kind: kind)
        object.label = label ?? kindLabel ?? autoLabel(for: kind)
        object.position = position
        if let style {
            object.style = style
        }
        object.order = (objects.map(\.order).max() ?? 0) + 1
        object.showLabel = isLabelWorthy(kind)
        objects.append(object)
        return object.id
    }

    func isLabelWorthy(_ kind: ObjectKind) -> Bool {
        switch kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return true
        case .caption, .measurement, .calculation, .angle:
            return true
        case .parameter:
            return true
        case .graph(.table):
            return true
        default:
            return false
        }
    }

    func autoLabel(for kind: ObjectKind) -> String {
        switch kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return nextPointLabel()
        default:
            return ""
        }
    }

    func nextPointLabel() -> String {
        let used = Set(objects.filter { $0.isPointLike }.map(\.label))
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for letter in letters {
            let s = String(letter)
            if !used.contains(s) {
                return s
            }
        }
        var i = 1
        while true {
            for letter in letters {
                let s = "\(letter)\(i)"
                if !used.contains(s) {
                    return s
                }
            }
            i += 1
        }
    }

    func displayName(for object: SketchObject) -> String {
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return object.label.isEmpty ? "Point" : "Point \(object.label)"
        case .segment(let a, let b):
            return "Segment \(objectByID(a)?.label ?? "")\(objectByID(b)?.label ?? "")"
        case .ray(let a, let b):
            return "Ray \(objectByID(a)?.label ?? "")\(objectByID(b)?.label ?? "")"
        case .line(let a, let b):
            return "Line \(objectByID(a)?.label ?? "")\(objectByID(b)?.label ?? "")"
        case .perpendicular:
            return "Perpendicular"
        case .parallel:
            return "Parallel"
        case .angleBisector:
            return "Angle Bisector"
        case .circle, .circleRadius:
            return "Circle"
        case .arcOnCircle, .arcThroughPoints:
            return "Arc"
        case .polygon:
            return "Polygon"
        case .angle:
            return "Angle \(object.label)"
        case .measurement(let kind, _):
            return "\(kind.title) \(object.label)"
        case .calculation:
            return "Calculation"
        case .caption:
            return "Text"
        case .functionPlot:
            return "Function Plot"
        case .transformed:
            return "Transformed Image"
        case .locus:
            return "Locus"
        case .parameter:
            return "Parameter"
        case .construction(let kind):
            switch kind {
            case .perpendicularBisector:
                return "Perpendicular Bisector"
            case .tangentPointToCircle, .tangentCircleToCircle:
                return "Tangent"
            case .radicalAxis:
                return "Radical Axis"
            }
        case .vector(let kind):
            switch kind {
            case .fromPoints:
                return "Vector"
            case .sum(_, _, let subtract):
                return subtract ? "Vector Difference" : "Vector Sum"
            }
        case .coordinateSystem(let kind, _, _, _):
            return "\(kind.title) Coordinate System"
        case .graph(let feature):
            switch feature {
            case .derivative:
                return "Derivative Plot"
            case .integral:
                return "Integral"
            case .tangent:
                return "Tangent"
            case .table:
                return "Value Table"
            }
        }
    }

    func symbol(for object: SketchObject) -> String {
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return "circle.fill"
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector:
            return "line.diagonal"
        case .circle, .circleRadius:
            return "circle"
        case .arcOnCircle, .arcThroughPoints:
            return "circle.dotted"
        case .polygon:
            return "pentagon"
        case .angle:
            return "angle"
        case .measurement, .calculation:
            return "ruler"
        case .caption:
            return "textformat"
        case .functionPlot:
            return "function"
        case .transformed:
            return "arrow.triangle.2.circlepath"
        case .locus:
            return "scribble"
        case .parameter:
            return "slider.horizontal.3"
        case .construction(let kind):
            switch kind {
            case .perpendicularBisector:
                return "line.diagonal"
            case .tangentPointToCircle, .tangentCircleToCircle:
                return "line.diagonal.arrow"
            case .radicalAxis:
                return "line.diagonal"
            }
        case .vector:
            return "arrow.right"
        case .coordinateSystem(let kind, _, _, _):
            return kind == .polar ? "circle.grid.cross" : "grid"
        case .graph(let feature):
            switch feature {
            case .derivative:
                return "function"
            case .integral:
                return "square.split.bottomrightquarter"
            case .tangent:
                return "line.diagonal"
            case .table:
                return "tablecells"
            }
        }
    }
}
