import Foundation

extension GeometryEval {

    mutating func transform(_ point: Vec2, by spec: TransformSpec) -> Vec2? {
        switch spec.kind {
        case .reflect:
            guard let reference = spec.reference, let straight = path(reference)?.straight else {
                return nil
            }
            let origin = straight.a
            let direction = (straight.b - straight.a).normalized()
            let distance = (point - origin).dot(direction)
            let foot = origin + direction * distance
            return foot * 2 - point

        case .rotate:
            guard let reference = spec.reference, let center = self.point(reference) else {
                return nil
            }
            let degrees = liveAngleDegrees(for: spec) ?? spec.angle
            return center + (point - center).rotated(by: degrees * .pi / 180)

        case .translate:
            if let a = spec.reference,
               let b = spec.secondReference,
               let pa = self.point(a),
               let pb = self.point(b) {
                return point + (pb - pa)
            }
            return point + Vec2(spec.dx, spec.dy)

        case .dilate:
            guard let reference = spec.reference, let center = self.point(reference) else {
                return nil
            }
            let factor = liveRatio(for: spec) ?? spec.factor
            return center + (point - center) * factor
        }
    }

    mutating func transform(_ shape: EvalPath, by spec: TransformSpec) -> EvalPath? {
        switch shape {
        case .segment(let a, let b):
            guard let ma = transform(a, by: spec), let mb = transform(b, by: spec) else {
                return nil
            }
            return .segment(ma, mb)
        case .ray(let a, let b):
            guard let ma = transform(a, by: spec), let mb = transform(b, by: spec) else {
                return nil
            }
            return .ray(ma, mb)
        case .line(let a, let b):
            guard let ma = transform(a, by: spec), let mb = transform(b, by: spec) else {
                return nil
            }
            return .line(ma, mb)
        case .circle(let center, let radius):
            guard let mappedCenter = transform(center, by: spec),
                  let edge = transform(center + Vec2(radius, 0), by: spec) else {
                return nil
            }
            return .circle(mappedCenter, mappedCenter.distance(to: edge))
        case .arc(let center, let radius, let start, let sweep):
            let startPoint = center + Vec2(cos(start), sin(start)) * radius
            let midAngle = start + sweep / 2
            let midPoint = center + Vec2(cos(midAngle), sin(midAngle)) * radius
            guard let mappedCenter = transform(center, by: spec),
                  let mappedStart = transform(startPoint, by: spec),
                  let mappedMid = transform(midPoint, by: spec) else {
                return nil
            }
            let newRadius = mappedCenter.distance(to: mappedStart)
            guard newRadius > Metrics.epsilon else {
                return nil
            }
            let newStart = (mappedStart - mappedCenter).angle
            var delta = positiveAngle((mappedMid - mappedCenter).angle - newStart)
            if delta > .pi {
                delta -= 2 * .pi
            }
            return .arc(center: mappedCenter, radius: newRadius, start: newStart, sweep: delta * 2)
        case .polygon(let points):
            let mapped = points.compactMap { transform($0, by: spec) }
            return mapped.count == points.count ? .polygon(mapped) : nil
        case .polyline(let points):
            let mapped = points.compactMap { transform($0, by: spec) }
            return mapped.count == points.count ? .polyline(mapped) : nil
        case .functionPlot:
            return nil
        }
    }

    /// The signed angle from the first side to the second side, in degrees.
    /// A missing mark falls back to the transform's snapshot.
    mutating func liveAngleDegrees(for spec: TransformSpec) -> Double? {
        guard let mark = spec.angleMark,
              let a = point(mark.a),
              let vertex = point(mark.vertex),
              let c = point(mark.c) else {
            return nil
        }
        let u = a - vertex
        let v = c - vertex
        return atan2(u.cross(v), u.dot(v)) * 180 / .pi
    }

    /// The ratio of the two marked path lengths. A missing path falls back to
    /// the transform's snapshot factor.
    mutating func liveRatio(for spec: TransformSpec) -> Double? {
        guard let mark = spec.ratioMark,
              let firstPath = path(mark.first),
              let secondPath = path(mark.second),
              let first = firstPath.length(settings: settings),
              let second = secondPath.length(settings: settings),
              second > Metrics.degenerate else {
            return nil
        }
        return first / second
    }
}
