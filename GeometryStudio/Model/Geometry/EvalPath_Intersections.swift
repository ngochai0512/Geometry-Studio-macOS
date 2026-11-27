import Foundation

private typealias Tolerance = EvalPathTolerance

extension EvalPath {
    // MARK: - Intersections

    func intersections(with other: EvalPath) -> [Vec2] {
        if let first = straight, let second = other.straight {
            return straightIntersections(first, second)
        }
        if let first = straight, case .circle(let center, let radius) = other {
            return lineCircle(first, center, radius)
        }
        if case .circle(let center, let radius) = self, let second = other.straight {
            return lineCircle(second, center, radius)
        }
        if case .circle(let firstCenter, let firstRadius) = self,
           case .circle(let secondCenter, let secondRadius) = other {
            return circleCircle(firstCenter, firstRadius, secondCenter, secondRadius)
        }
        if case .arc(let center, let radius, let start, let sweep) = self {
            return arcIntersections(center: center, radius: radius, start: start, sweep: sweep, with: other)
        }
        if case .arc(let center, let radius, let start, let sweep) = other {
            return arcIntersections(center: center, radius: radius, start: start, sweep: sweep, with: self)
        }
        if case .polygon(let points) = self {
            return dedupe(intersectionsOfSegments(points, closed: true, with: other))
        }
        if case .polygon(let points) = other {
            return dedupe(intersections(of: self, withSegments: points, closed: true))
        }
        if case .polyline(let points) = self {
            return dedupe(intersectionsOfSegments(points, closed: false, with: other))
        }
        if case .polyline(let points) = other {
            return dedupe(intersections(of: self, withSegments: points, closed: false))
        }
        return []
    }

    private func arcIntersections(
        center: Vec2,
        radius: Double,
        start: Double,
        sweep: Double,
        with other: EvalPath
    ) -> [Vec2] {
        var hits: [Vec2] = []
        if let straight = other.straight {
            hits = lineCircle(straight, center, radius)
        } else {
            switch other {
            case .circle(let otherCenter, let otherRadius):
                hits = circleCircle(center, radius, otherCenter, otherRadius)
            case .arc(let otherCenter, let otherRadius, let otherStart, let otherSweep):
                hits = circleCircle(center, radius, otherCenter, otherRadius).filter {
                    arcProgress(
                        of: ($0 - otherCenter).angle,
                        start: otherStart,
                        sweep: otherSweep
                    ) != nil
                }
            case .polygon(let points):
                hits = intersectionsOfSegments(points, closed: true, with: .circle(center, radius))
            case .polyline(let points):
                hits = intersectionsOfSegments(points, closed: false, with: .circle(center, radius))
            case .segment, .ray, .line, .functionPlot:
                break
            }
        }
        return dedupe(hits.filter {
            arcProgress(of: ($0 - center).angle, start: start, sweep: sweep) != nil
        })
    }

    private func intersectionsOfSegments(
        _ points: [Vec2],
        closed: Bool,
        with other: EvalPath
    ) -> [Vec2] {
        guard points.count > 1 else {
            return []
        }
        var hits: [Vec2] = []
        let count = closed ? points.count : points.count - 1
        for index in 0..<count {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            hits.append(contentsOf: EvalPath.segment(a, b).intersections(with: other))
        }
        return hits
    }

    private func intersections(
        of shape: EvalPath,
        withSegments points: [Vec2],
        closed: Bool
    ) -> [Vec2] {
        guard points.count > 1 else {
            return []
        }
        var hits: [Vec2] = []
        let count = closed ? points.count : points.count - 1
        for index in 0..<count {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            hits.append(contentsOf: shape.intersections(with: .segment(a, b)))
        }
        return hits
    }
}

// MARK: - Intersection helpers

private func parameterIsOnPath(_ parameter: Double, kind: Int) -> Bool {
    // Negated rejections keep a NaN parameter on the path, as before.
    if kind == StraightKind.segment {
        return !(parameter < -Tolerance.boundary || parameter > 1 + Tolerance.boundary)
    }
    if kind == StraightKind.ray {
        return !(parameter < -Tolerance.boundary)
    }
    return true
}

private func dedupe(_ points: [Vec2]) -> [Vec2] {
    var unique: [Vec2] = []
    for point in points where !unique.contains(where: { $0.distance(to: point) < Tolerance.dedupe }) {
        unique.append(point)
    }
    return unique
}

private func straightIntersections(
    _ first: (a: Vec2, b: Vec2, kind: Int),
    _ second: (a: Vec2, b: Vec2, kind: Int)
) -> [Vec2] {
    let firstDirection = first.b - first.a
    let secondDirection = second.b - second.a
    let denominator = firstDirection.cross(secondDirection)
    guard abs(denominator) > Tolerance.zero else {
        return []
    }
    let offset = second.a - first.a
    let firstParameter = offset.cross(secondDirection) / denominator
    let secondParameter = offset.cross(firstDirection) / denominator
    guard parameterIsOnPath(firstParameter, kind: first.kind),
          parameterIsOnPath(secondParameter, kind: second.kind) else {
        return []
    }
    return [first.a.lerp(to: first.b, firstParameter)]
}

private func lineCircle(
    _ straight: (a: Vec2, b: Vec2, kind: Int),
    _ center: Vec2,
    _ radius: Double
) -> [Vec2] {
    let direction = straight.b - straight.a
    let offset = straight.a - center
    let quadraticA = direction.dot(direction)
    guard quadraticA > Tolerance.zero else {
        return []
    }
    let quadraticB = 2 * offset.dot(direction)
    let quadraticC = offset.dot(offset) - radius * radius
    let discriminant = quadraticB * quadraticB - 4 * quadraticA * quadraticC
    if discriminant < -Tolerance.boundary {
        return []
    }
    let root = sqrt(max(discriminant, 0))
    let denominator = 2 * quadraticA
    var parameters = [
        (-quadraticB - root) / denominator,
        (-quadraticB + root) / denominator
    ]
    parameters.sort()
    var hits: [Vec2] = []
    for parameter in parameters where parameterIsOnPath(parameter, kind: straight.kind) {
        hits.append(straight.a.lerp(to: straight.b, parameter))
    }
    return dedupe(hits)
}

private func circleCircle(
    _ firstCenter: Vec2,
    _ firstRadius: Double,
    _ secondCenter: Vec2,
    _ secondRadius: Double
) -> [Vec2] {
    let distance = firstCenter.distance(to: secondCenter)
    if distance < Tolerance.zero
        || distance > firstRadius + secondRadius + Tolerance.boundary
        || distance < abs(firstRadius - secondRadius) - Tolerance.boundary {
        return []
    }
    let midpointDistance = (
        firstRadius * firstRadius
        - secondRadius * secondRadius
        + distance * distance
    ) / (2 * distance)
    let halfChordSquared = firstRadius * firstRadius - midpointDistance * midpointDistance
    let halfChord = sqrt(max(halfChordSquared, 0))
    let axis = (secondCenter - firstCenter).normalized()
    let midpoint = firstCenter + axis * midpointDistance
    let perpendicular = axis.perpendicular()
    if halfChord < Tolerance.boundary {
        return [midpoint]
    }
    return [midpoint + perpendicular * halfChord, midpoint - perpendicular * halfChord]
}
