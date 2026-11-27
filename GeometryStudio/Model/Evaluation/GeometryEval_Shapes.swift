import Foundation

extension GeometryEval {

    /// Circumcircle through three points, with the sweep chosen so the arc
    /// runs from `a` to `c` through `b`.
    func arcThrough(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> EvalPath? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > Metrics.degenerate else {
            return nil
        }
        let aa = a.dot(a)
        let bb = b.dot(b)
        let cc = c.dot(c)
        let ux = (aa * (b.y - c.y) + bb * (c.y - a.y) + cc * (a.y - b.y)) / d
        let uy = (aa * (c.x - b.x) + bb * (a.x - c.x) + cc * (b.x - a.x)) / d
        let center = Vec2(ux, uy)
        let radius = center.distance(to: a)
        guard radius > Metrics.epsilon else {
            return nil
        }
        let start = (a - center).angle
        let end = (c - center).angle
        let through = (b - center).angle
        let ccwSweep = positiveAngle(end - start)
        guard ccwSweep > Metrics.epsilon else {
            return nil
        }
        let throughOffset = positiveAngle(through - start)
        let sweep = throughOffset <= ccwSweep + Metrics.epsilon ? ccwSweep : ccwSweep - 2 * .pi
        return .arc(center: center, radius: radius, start: start, sweep: sweep)
    }

    /// The filled region cut from an arc's circle. A sector includes the
    /// centre; a segment closes the sampled arc with its chord.
    func arcFillRegion(_ path: EvalPath?, fill: ArcFill) -> EvalPath? {
        guard fill != .none,
              let path,
              case .arc(let center, let radius, let start, let sweep) = path else {
            return nil
        }
        let steps = max(
            2,
            Int(abs(sweep) / (2 * .pi) * Double(Metrics.arcFillSamples))
        )
        var points: [Vec2] = []
        points.reserveCapacity(steps + 1)
        for index in 0...steps {
            let t = Double(index) / Double(steps)
            let angle = start + sweep * t
            points.append(center + Vec2(cos(angle), sin(angle)) * radius)
        }
        switch fill {
        case .none:
            return nil
        case .sector:
            return .polygon([center] + points)
        case .segment:
            return .polygon(points)
        }
    }
}
