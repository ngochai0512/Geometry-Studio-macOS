import Foundation

// MARK: - Object model

enum MeasureKind: String, Codable, CaseIterable, Identifiable {
    case distance, length, perimeter, circumference, angle, area, radius, ratio,
         coordinates, equation, slope
    var id: String { rawValue }
    var title: String {
        switch self {
        case .distance: return "Distance"
        case .length: return "Length"
        case .perimeter: return "Perimeter"
        case .circumference: return "Circumference"
        case .angle: return "Angle"
        case .area: return "Area"
        case .radius: return "Radius"
        case .ratio: return "Ratio"
        case .coordinates: return "Coordinates"
        case .equation: return "Equation"
        case .slope: return "Slope"
        }
    }
}

enum TransformKind: String, Codable, CaseIterable, Identifiable {
    case reflect, rotate, translate, dilate
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct TransformSpec: Codable, Hashable {
    var kind: TransformKind
    var reference: UUID?
    var secondReference: UUID?
    var angle: Double = 90
    var factor: Double = 2
    var dx: Double = 1
    var dy: Double = 0
}

enum ObjectKind: Codable, Hashable {
    case freePoint
    case pointOnPath(path: UUID, param: Double)
    case midpoint(a: UUID, b: UUID)
    case intersection(a: UUID, b: UUID, index: Int)
    case segment(a: UUID, b: UUID)
    case ray(a: UUID, b: UUID)
    case line(a: UUID, b: UUID)
    case perpendicular(line: UUID, point: UUID)
    case parallel(line: UUID, point: UUID)
    case angleBisector(a: UUID, vertex: UUID, c: UUID)
    case circle(center: UUID, through: UUID)
    case polygon(vertices: [UUID])
    case angle(a: UUID, vertex: UUID, c: UUID)
    case measurement(MeasureKind, refs: [UUID])
    case calculation(String)
    case caption(String)
    case functionPlot(String)
    case transformed(source: UUID, spec: TransformSpec)
    /// The sampled path of `target` as `driver` (a point on a path) sweeps
    /// through its domain, as in the original's Locus command.
    case locus(driver: UUID, target: UUID)
}

struct SketchObject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: ObjectKind
    var label: String = ""
    var showLabel: Bool = true
    var visible: Bool = true
    var style: ObjectStyle = ObjectStyle()
    var offset: Vec2 = .zero
    var position: Vec2? = nil
    var order: Int = 0
    var isLocked: Bool = false

    var isPointLike: Bool {
        switch kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return true
        case .transformed(_, _):
            return false
        default:
            return false
        }
    }

    var isPathLike: Bool {
        switch kind {
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector,
             .circle, .polygon, .functionPlot, .transformed, .locus:
            return true
        default:
            return false
        }
    }
}
