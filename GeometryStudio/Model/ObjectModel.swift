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

struct TransformSpec: Codable, Hashable {
    var kind: TransformKind
    var reference: UUID?
    var secondReference: UUID?
    var angle: Double = 90
    var factor: Double = 2
    var dx: Double = 1
    var dy: Double = 0

    init(kind: TransformKind, reference: UUID? = nil, secondReference: UUID? = nil,
         angle: Double = 90, factor: Double = 2, dx: Double = 1, dy: Double = 0) {
        self.kind = kind
        self.reference = reference
        self.secondReference = secondReference
        self.angle = angle
        self.factor = factor
        self.dx = dx
        self.dy = dy
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
             .functionPlot, .transformed, .locus:
            return true
        default:
            return false
        }
    }
}
