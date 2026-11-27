import Foundation

// MARK: - Object model













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
    case circleRadius(center: UUID, radius: Double)
    case arcOnCircle(circle: UUID, start: UUID, end: UUID)
    case arcThroughPoints(a: UUID, b: UUID, c: UUID)
    case polygon(vertices: [UUID])
    case angle(a: UUID, vertex: UUID, c: UUID)
    case measurement(MeasureKind, refs: [UUID])
    case calculation(String)
    case caption(String)
    case functionPlot(String)
    case transformed(source: UUID, spec: TransformSpec)
    /// The sampled path of `target` as `driver` (a point on a path) sweeps
    /// through its domain, as in the Locus command.
    case locus(driver: UUID, target: UUID)
    /// A numeric parameter displayed as a card and edited with a slider.
    case parameter(value: Double, minimum: Double, maximum: Double)
    /// Perpendicular bisector, tangents and radical axis.
    case construction(ConstructionKind)
    /// A directed segment or the sum/difference of two vectors.
    case vector(VectorKind)
    /// A coordinate system drawn at a point, with its own scale and unit.
    case coordinateSystem(kind: CoordinateKind, origin: UUID, step: Double, unit: LengthUnit)
    /// Derivative plot, integral shading, tangent at x, or a value table.
    case graph(GraphFeature)
}

struct SketchObject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: ObjectKind
    var label: String = ""
    var showLabel: Bool = true
    var visible: Bool = true
    var style: ObjectStyle = ObjectStyle()
    var arcFill: ArcFill = .none
    var offset: Vec2 = .zero
    var position: Vec2? = nil
    var order: Int = 0
    var isLocked: Bool = false

    init(kind: ObjectKind) {
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ObjectKind.self, forKey: .kind)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        showLabel = try c.decodeIfPresent(Bool.self, forKey: .showLabel) ?? true
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        style = try c.decodeIfPresent(ObjectStyle.self, forKey: .style) ?? ObjectStyle()
        arcFill = try c.decodeIfPresent(ArcFill.self, forKey: .arcFill) ?? .none
        offset = try c.decodeIfPresent(Vec2.self, forKey: .offset) ?? .zero
        position = try c.decodeIfPresent(Vec2.self, forKey: .position)
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }

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
             .circle, .circleRadius, .arcOnCircle, .arcThroughPoints, .polygon,
             .functionPlot, .transformed, .locus, .construction, .vector, .graph:
            return true
        default:
            return false
        }
    }
}
