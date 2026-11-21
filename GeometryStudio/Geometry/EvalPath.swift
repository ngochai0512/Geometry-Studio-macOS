import Foundation

private typealias Tolerance = EvalPathTolerance

// MARK: - Evaluated path

enum EvalPath {
    case segment(Vec2, Vec2)
    case ray(Vec2, Vec2)
    case line(Vec2, Vec2)
    case circle(Vec2, Double)
    case arc(center: Vec2, radius: Double, start: Double, sweep: Double)
    case polygon([Vec2])
    case polyline([Vec2])
    case functionPlot(String)

    private static let cardinalAngles: [Double] = [0, .pi / 2, .pi, 3 * .pi / 2]

    var isStraight: Bool {
        switch self {
        case .segment, .ray, .line:
            return true
        default:
            return false
        }
    }

    /// The supporting line of a straight path. `kind` is one of the
    /// `StraightKind` values and selects the parameter domain.
    var straight: (a: Vec2, b: Vec2, kind: Int)? {
        switch self {
        case .segment(let a, let b):
            return (a, b, StraightKind.segment)
        case .ray(let a, let b):
            return (a, b, StraightKind.ray)
        case .line(let a, let b):
            return (a, b, StraightKind.line)
        default:
            return nil
        }
    }

    // MARK: - Sampling

    func point(at param: Double) -> Vec2? {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            return a.lerp(to: b, param)
        case .circle(let center, let radius):
            return pointOnCircle(center: center, radius: radius, angle: param)
        case .arc(let center, let radius, let start, let sweep):
            return pointOnCircle(center: center, radius: radius, angle: start + sweep * param)
        case .polygon(let points):
            return pointOnPolygon(points, at: param)
        case .polyline(let points):
            return pointOnPolyline(points, at: param)
        case .functionPlot:
            return nil
        }
    }

    private func pointOnCircle(center: Vec2, radius: Double, angle: Double) -> Vec2 {
        center + Vec2(cos(angle), sin(angle)) * radius
    }

    private func pointOnPolygon(_ points: [Vec2], at param: Double) -> Vec2? {
        guard points.count > 1 else {
            return points.first
        }
        let total = polygonLength(points)
        guard total > Tolerance.zero else {
            return points.first
        }
        var remaining = param.truncatingRemainder(dividingBy: 1)
        if remaining < 0 {
            remaining += 1
        }
        var target = remaining * total
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            let length = a.distance(to: b)
            if target <= length {
                return a.lerp(to: b, target / max(length, Tolerance.zero))
            }
            target -= length
        }
        return points.first
    }

    private func pointOnPolyline(_ points: [Vec2], at param: Double) -> Vec2? {
        guard points.count > 1 else {
            return points.first
        }
        let total = polygonLength(points)
        guard total > Tolerance.zero else {
            return points.first
        }
        let target = min(max(param, 0), 1) * total
        var walked = 0.0
        for index in 0..<(points.count - 1) {
            let a = points[index]
            let b = points[index + 1]
            let length = a.distance(to: b)
            if target <= walked + length {
                return a.lerp(to: b, (target - walked) / max(length, Tolerance.zero))
            }
            walked += length
        }
        return points.last
    }

    // MARK: - Distance and parameters

    func nearestParam(to point: Vec2) -> Double {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            let direction = b - a
            let denominator = direction.dot(direction)
            guard denominator > Tolerance.zero else {
                return 0
            }
            return clampedStraightParameter((point - a).dot(direction) / denominator)
        case .circle(let center, _):
            return normalizedAngle((point - center).angle)
        case .arc(let center, let radius, let start, let sweep):
            if let progress = arcProgress(of: (point - center).angle, start: start, sweep: sweep) {
                return progress
            }
            let startPoint = pointOnCircle(center: center, radius: radius, angle: start)
            let endPoint = pointOnCircle(center: center, radius: radius, angle: start + sweep)
            return point.distance(to: startPoint) <= point.distance(to: endPoint) ? 0 : 1
        case .polygon(let points):
            return polylineNearestParam(points, closed: true, to: point)
        case .polyline(let points):
            return polylineNearestParam(points, closed: false, to: point)
        case .functionPlot:
            return 0
        }
    }

    func distance(to point: Vec2) -> Double {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            let direction = b - a
            let denominator = direction.dot(direction)
            if denominator < Tolerance.zero {
                return point.distance(to: a)
            }
            let parameter = clampedStraightParameter((point - a).dot(direction) / denominator)
            return point.distance(to: a.lerp(to: b, parameter))
        case .circle(let center, let radius):
            return abs(point.distance(to: center) - radius)
        case .arc(let center, let radius, let start, let sweep):
            if arcProgress(of: (point - center).angle, start: start, sweep: sweep) != nil {
                return abs(point.distance(to: center) - radius)
            }
            let startPoint = pointOnCircle(center: center, radius: radius, angle: start)
            let endPoint = pointOnCircle(center: center, radius: radius, angle: start + sweep)
            return min(point.distance(to: startPoint), point.distance(to: endPoint))
        case .polygon(let points):
            return polylineDistance(points, closed: true, to: point)
        case .polyline(let points):
            return polylineDistance(points, closed: false, to: point)
        case .functionPlot:
            return .infinity
        }
    }

    func length(settings: CanvasSettings) -> Double? {
        switch self {
        case .segment(let a, let b):
            return a.distance(to: b)
        case .circle(_, let radius):
            return 2 * .pi * radius
        case .arc(_, let radius, _, let sweep):
            return radius * abs(sweep)
        case .polygon(let points), .polyline(let points):
            return polygonLength(points)
        case .ray, .line, .functionPlot:
            return nil
        }
    }

    private func clampedStraightParameter(_ parameter: Double) -> Double {
        switch self {
        case .segment:
            return min(max(parameter, 0), 1)
        case .ray:
            return max(parameter, 0)
        default:
            return parameter
        }
    }

    private func polylineNearestParam(_ points: [Vec2], closed: Bool, to point: Vec2) -> Double {
        guard points.count > 1 else {
            return 0
        }
        let total = polygonLength(points)
        guard total > Tolerance.zero else {
            return 0
        }
        var best = 0.0
        var bestDistance = Double.greatestFiniteMagnitude
        var walked = 0.0
        let count = closed ? points.count : points.count - 1
        for index in 0..<count {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            let length = a.distance(to: b)
            let direction = b - a
            let denominator = direction.dot(direction)
            var parameter = 0.0
            if denominator > Tolerance.zero {
                parameter = (point - a).dot(direction) / denominator
            }
            parameter = min(max(parameter, 0), 1)
            let closest = a.lerp(to: b, parameter)
            let distance = closest.distance(to: point)
            if distance < bestDistance {
                bestDistance = distance
                best = (walked + length * parameter) / total
            }
            walked += length
        }
        return best
    }

    private func polylineDistance(_ points: [Vec2], closed: Bool, to point: Vec2) -> Double {
        guard points.count > 1 else {
            return points.first?.distance(to: point) ?? .infinity
        }
        var best = Double.greatestFiniteMagnitude
        let count = closed ? points.count : points.count - 1
        for index in 0..<count {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            best = min(best, EvalPath.segment(a, b).distance(to: point))
        }
        return best
    }

    // MARK: - Bounds and containment

    var boundingBox: WorldRect? {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            return WorldRect(points: [a, b])
        case .circle(let center, let radius):
            return WorldRect(
                minX: center.x - radius,
                minY: center.y - radius,
                maxX: center.x + radius,
                maxY: center.y + radius
            )
        case .arc(let center, let radius, let start, let sweep):
            let startPoint = pointOnCircle(center: center, radius: radius, angle: start)
            var box = WorldRect(
                minX: startPoint.x,
                minY: startPoint.y,
                maxX: startPoint.x,
                maxY: startPoint.y
            )
            box.include(pointOnCircle(center: center, radius: radius, angle: start + sweep))
            for angle in Self.cardinalAngles
            where arcProgress(of: angle, start: start, sweep: sweep) != nil {
                box.include(pointOnCircle(center: center, radius: radius, angle: angle))
            }
            return box
        case .polygon(let points), .polyline(let points):
            return WorldRect(points: points)
        case .functionPlot:
            return nil
        }
    }

    /// Whether a point lies inside a closed polygon. The original
    /// (`routine`) walks the vertices, sums `atan2(cross, dot)` for the
    /// vectors seen from the point, divides by 2π and tests the fractional
    /// part against 0 within 1e-12. That is the winding-number test; a
    /// non-zero winding count means inside.
    func contains(_ p: Vec2) -> Bool {
        guard case .polygon(let points) = self, points.count >= 3 else {
            return false
        }
        var sum = 0.0
        for index in points.indices {
            let a = points[index] - p
            let b = points[(index + 1) % points.count] - p
            sum += atan2(a.cross(b), a.dot(b))
        }
        return abs(sum) > .pi
    }

    // MARK: - Arc progress

    func arcProgress(of angle: Double, start: Double, sweep: Double) -> Double? {
        guard abs(sweep) > Tolerance.zero else {
            return nil
        }
        if sweep > 0 {
            let delta = normalizedAngle(angle - start)
            guard delta <= sweep + Tolerance.boundary else {
                return nil
            }
            return min(delta / sweep, 1)
        }
        let delta = normalizedAngle(start - angle)
        guard delta <= -sweep + Tolerance.boundary else {
            return nil
        }
        return min(delta / -sweep, 1)
    }
}

// MARK: - Shared tolerances and parameter kinds

enum EvalPathTolerance {
    static let zero = 1e-12
    static let boundary = 1e-9
    static let dedupe = 1e-7
}

enum StraightKind {
    static let segment = 0
    static let ray = 1
    static let line = 2
}

private func normalizedAngle(_ angle: Double) -> Double {
    let twoPi = 2 * Double.pi
    var value = angle.truncatingRemainder(dividingBy: twoPi)
    if value < 0 {
        value += twoPi
    }
    return value
}

// MARK: - Bounds helpers

private extension WorldRect {
    init?(points: [Vec2]) {
        guard let first = points.first else {
            return nil
        }
        self.init(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for point in points.dropFirst() {
            include(point)
        }
    }

    mutating func include(_ point: Vec2) {
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
    }
}

// MARK: - Polygon measurements

func polygonLength(_ points: [Vec2]) -> Double {
    guard points.count > 1 else {
        return 0
    }
    var total = 0.0
    for index in points.indices {
        total += points[index].distance(to: points[(index + 1) % points.count])
    }
    return total
}

/// Absolute polygon area. The shoelace sum is accumulated explicitly so both
/// winding directions work and the compiler never has to solve a long chain of
/// collection operators.
func polygonArea(_ points: [Vec2]) -> Double {
    guard points.count >= 3 else {
        return 0
    }
    var twiceArea = 0.0
    for index in points.indices {
        let a = points[index]
        let b = points[(index + 1) % points.count]
        twiceArea += a.x * b.y - b.x * a.y
    }
    return abs(twiceArea) / 2
}
