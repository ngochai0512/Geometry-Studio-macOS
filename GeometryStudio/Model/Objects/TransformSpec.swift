import Foundation

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
