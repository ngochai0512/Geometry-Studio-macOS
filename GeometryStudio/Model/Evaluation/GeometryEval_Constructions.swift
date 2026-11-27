import Foundation

extension GeometryEval {

    mutating func constructionResult(_ kind: ConstructionKind) -> EvalResult {
        var result = EvalResult()
        switch kind {
        case .perpendicularBisector(let a, let b):
            guard let pa = point(a), let pb = point(b) else {
                return result
            }
            let middle = pa.lerp(to: pb, 0.5)
            let direction = (pb - pa).perpendicular().normalized()
            guard direction.length > Metrics.epsilon else {
                return result
            }
            result.path = .line(middle, middle + direction)

        case .tangentPointToCircle(let pointID, let circleID, let index):
            guard let p = point(pointID),
                  case .circle(let center, let radius)? = path(circleID) else {
                return result
            }
            let lines = tangentLines(from: p, center: center, radius: radius)
            if index >= 0, index < lines.count {
                result.path = lines[index]
            }

        case .tangentCircleToCircle(let a, let b, let index):
            guard case .circle(let c1, let r1)? = path(a),
                  case .circle(let c2, let r2)? = path(b) else {
                return result
            }
            let lines = commonTangents(c1: c1, r1: r1, c2: c2, r2: r2)
            if index >= 0, index < lines.count {
                result.path = lines[index]
            }

        case .radicalAxis(let a, let b):
            guard case .circle(let c1, let r1)? = path(a),
                  case .circle(let c2, let r2)? = path(b) else {
                return result
            }
            let axis = c2 - c1
            let d2 = axis.dot(axis)
            guard d2 > Metrics.epsilon else {
                return result
            }
            let rhs = (c2.dot(c2) - c1.dot(c1) - r2 * r2 + r1 * r1) / 2
            let origin = axis * (rhs / d2)
            let direction = axis.perpendicular().normalized()
            result.path = .line(origin, origin + direction)
        }
        return result
    }

    func tangentLines(from p: Vec2, center: Vec2, radius: Double) -> [EvalPath] {
        let v = p - center
        let d2 = v.dot(v)
        guard radius > Metrics.epsilon, d2 > radius * radius + Metrics.epsilon else {
            return []
        }
        let base = center + v * (radius * radius / d2)
        let offset = v.perpendicular() * (radius * sqrt(d2 - radius * radius) / d2)
        return [.line(p, base + offset), .line(p, base - offset)]
    }

    /// The four common tangents of two circles, external first.
    func commonTangents(c1: Vec2, r1: Double, c2: Vec2, r2: Double) -> [EvalPath] {
        let delta = c2 - c1
        let d = delta.length
        guard d > Metrics.epsilon else {
            return []
        }
        let direction = delta.normalized()
        let normal = direction.perpendicular()
        var lines: [EvalPath] = []
        for offset in [r2 - r1, -(r1 + r2)] {
            let ratio = offset / d
            guard abs(ratio) <= 1 + Metrics.epsilon else {
                continue
            }
            let side = sqrt(max(0, 1 - ratio * ratio))
            for sign in [1.0, -1.0] {
                let n = direction * ratio + normal * (side * sign)
                let c = r1 - n.dot(c1)
                let origin = n * (-c)
                let tangent = n.perpendicular().normalized()
                lines.append(.line(origin, origin + tangent))
            }
        }
        return lines
    }

    mutating func vectorResult(_ kind: VectorKind) -> EvalResult {
        var result = EvalResult()
        switch kind {
        case .fromPoints(let from, let to):
            guard let a = point(from), let b = point(to) else {
                return result
            }
            result.path = .segment(a, b)
            result.arrow = (from: a, to: b)

        case .sum(let a, let b, let subtract):
            guard let first = evaluate(a).arrow, let second = evaluate(b).arrow else {
                return result
            }
            let firstVector = first.to - first.from
            let secondVector = second.to - second.from
            let sum = subtract ? firstVector - secondVector : firstVector + secondVector
            let start = first.from
            let end = start + sum
            result.path = .segment(start, end)
            result.arrow = (from: start, to: end)
        }
        return result
    }
}
