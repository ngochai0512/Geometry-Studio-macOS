import Foundation

// MARK: - Object model

enum MeasureKind: String, Codable, CaseIterable, Identifiable {
    case distance
    case length
    case perimeter
    case circumference
    case angle
    case arcAngle
    case arcLength
    case area
    case radius
    case ratio
    case coordinates
    case abscissa
    case ordinate
    case polarDistance
    case polarDirection
    case coordinateDistance
    case equation
    case slope
    var id: String {
        rawValue
    }
    var title: String {
        switch self {
        case .distance:
            return "Distance"
        case .length:
            return "Length"
        case .perimeter:
            return "Perimeter"
        case .circumference:
            return "Circumference"
        case .angle:
            return "Angle"
        case .arcAngle:
            return "Arc Angle"
        case .arcLength:
            return "Arc Length"
        case .area:
            return "Area"
        case .radius:
            return "Radius"
        case .ratio:
            return "Ratio"
        case .coordinates:
            return "Coordinates"
        case .abscissa:
            return "Abscissa"
        case .ordinate:
            return "Ordinate"
        case .polarDistance:
            return "Polar Distance"
        case .polarDirection:
            return "Polar Direction"
        case .coordinateDistance:
            return "Coordinate Distance"
        case .equation:
            return "Equation"
        case .slope:
            return "Slope"
        }
    }
}

enum TransformKind: String, Codable, CaseIterable, Identifiable {
    case reflect
    case rotate
    case translate
    case dilate
    var id: String {
        rawValue
    }
    var title: String {
        rawValue.capitalized
    }
}

/// How an arc fills the region it cuts from its circle.
enum ArcFill: String, Codable, CaseIterable, Identifiable {
    case none
    case sector
    case segment
    var id: String {
        rawValue
    }
    var title: String {
        switch self {
        case .none:
            return "None"
        case .sector:
            return "Sector"
        case .segment:
            return "Segment"
        }
    }
}

enum CoordinateKind: String, Codable, CaseIterable, Identifiable {
    case cartesian
    case polar

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .cartesian:
            return "Cartesian"
        case .polar:
            return "Polar"
        }
    }
}

/// The constructed straight objects that are not a single segment between two
/// selected points: perpendicular bisectors, tangents and radical axes.
enum ConstructionKind: Codable, Hashable {
    case perpendicularBisector(a: UUID, b: UUID)
    case tangentPointToCircle(point: UUID, circle: UUID, index: Int)
    case tangentCircleToCircle(a: UUID, b: UUID, index: Int)
    case radicalAxis(a: UUID, b: UUID)
}

enum VectorKind: Codable, Hashable {
    case fromPoints(from: UUID, to: UUID)
    case sum(a: UUID, b: UUID, subtract: Bool)
}

enum GraphFeature: Codable, Hashable {
    case derivative(String)
    case integral(String, from: Double, to: Double)
    case tangent(String, x: Double)
    case table(String, from: Double, to: Double, step: Double)
}

struct TransformSpec: Codable, Hashable {
    var kind: TransformKind
    var reference: UUID?
    var secondReference: UUID?
    var angle: Double = 90
    var factor: Double = 2
    var dx: Double = 1
    var dy: Double = 0
    /// Live angle definition from the Mark Angle command. When the three
    /// points still resolve, the rotation uses their current angle; `angle`
    /// is the snapshot used when the mark is gone.
    var angleMark: AngleMark?
    /// Live ratio definition from the Mark Ratio command, with `factor` as
    /// the fallback when either path is gone.
    var ratioMark: RatioMark?

    init(kind: TransformKind, reference: UUID? = nil, secondReference: UUID? = nil,
         angle: Double = 90, factor: Double = 2, dx: Double = 1, dy: Double = 0,
         angleMark: AngleMark? = nil, ratioMark: RatioMark? = nil) {
        self.kind = kind
        self.reference = reference
        self.secondReference = secondReference
        self.angle = angle
        self.factor = factor
        self.dx = dx
        self.dy = dy
        self.angleMark = angleMark
        self.ratioMark = ratioMark
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(TransformKind.self, forKey: .kind)
        reference = try c.decodeIfPresent(UUID.self, forKey: .reference)
        secondReference = try c.decodeIfPresent(UUID.self, forKey: .secondReference)
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 90
        factor = try c.decodeIfPresent(Double.self, forKey: .factor) ?? 2
        dx = try c.decodeIfPresent(Double.self, forKey: .dx) ?? 1
        dy = try c.decodeIfPresent(Double.self, forKey: .dy) ?? 0
        angleMark = try c.decodeIfPresent(AngleMark.self, forKey: .angleMark)
        ratioMark = try c.decodeIfPresent(RatioMark.self, forKey: .ratioMark)
    }
}

/// The three points that define an angle mark: first side, vertex, second side.
struct AngleMark: Codable, Hashable {
    var a: UUID
    var vertex: UUID
    var c: UUID
}

/// Two paths whose lengths define the marked ratio.
struct RatioMark: Codable, Hashable {
    var first: UUID
    var second: UUID
}

/// Two points whose displacement defines the marked vector.
struct VectorMark: Codable, Hashable {
    var from: UUID
    var to: UUID
}

/// The persistent transform parameters the Mark commands set.
/// Marks live in the document, not in a modal dialog, and transforms read the
/// mark at the moment they run.
struct TransformMarks: Codable, Hashable {
    var mirror: UUID?
    var center: UUID?
    var angle: AngleMark?
    var ratio: RatioMark?
    var vector: VectorMark?

    init() {}

    var isEmpty: Bool {
        mirror == nil && center == nil && angle == nil && ratio == nil && vector == nil
    }
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
