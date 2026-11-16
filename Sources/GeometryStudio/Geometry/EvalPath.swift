import Foundation

// MARK: - Evaluated path

enum EvalPath {
    case segment(Vec2, Vec2)
    case ray(Vec2, Vec2)
    case line(Vec2, Vec2)
    case circle(Vec2, Double)
    case polygon([Vec2])
    case polyline([Vec2])
    case functionPlot(String)

    var isStraight: Bool {
        switch self {
        case .segment, .ray, .line: return true
        default: return false
        }
    }

    var straight: (a: Vec2, b: Vec2, kind: Int)? {
        switch self {
        case .segment(let a, let b): return (a, b, 0)
        case .ray(let a, let b): return (a, b, 1)
        case .line(let a, let b): return (a, b, 2)
        default: return nil
        }
    }

    func point(at param: Double) -> Vec2? {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            return a.lerp(to: b, param)
        case .circle(let c, let r):
            return c + Vec2(cos(param), sin(param)) * r
        case .polygon(let pts):
            guard pts.count > 1 else { return pts.first }
            let total = polygonLength(pts)
            guard total > 1e-12 else { return pts.first }
            var remaining = param.truncatingRemainder(dividingBy: 1)
            if remaining < 0 { remaining += 1 }
            var target = remaining * total
            for i in 0..<pts.count {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                let l = a.distance(to: b)
                if target <= l {
                    return a.lerp(to: b, target / max(l, 1e-12))
                }
                target -= l
            }
            return pts.first
        case .polyline(let pts):
            guard pts.count > 1 else { return pts.first }
            let total = polygonLength(pts)
            guard total > 1e-12 else { return pts.first }
            let target = min(max(param, 0), 1) * total
            var walked = 0.0
            for i in 0..<(pts.count - 1) {
                let a = pts[i]
                let b = pts[i + 1]
                let l = a.distance(to: b)
                if target <= walked + l {
                    return a.lerp(to: b, (target - walked) / max(l, 1e-12))
                }
                walked += l
            }
            return pts.last
        case .functionPlot:
            return nil
        }
    }

    func nearestParam(to p: Vec2) -> Double {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            let d = b - a
            let denom = d.dot(d)
            guard denom > 1e-12 else { return 0 }
            var t = (p - a).dot(d) / denom
            switch self {
            case .segment: t = min(max(t, 0), 1)
            case .ray: t = max(t, 0)
            default: break
            }
            return t
        case .circle(let c, _):
            var a = (p - c).angle
            if a < 0 { a += .pi * 2 }
            return a
        case .polygon(let pts):
            guard pts.count > 1 else { return 0 }
            let total = polygonLength(pts)
            guard total > 1e-12 else { return 0 }
            var best = 0.0
            var bestDist = Double.greatestFiniteMagnitude
            var walked = 0.0
            for i in 0..<pts.count {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                let l = a.distance(to: b)
                let d = b - a
                let denom = d.dot(d)
                var t = denom > 1e-12 ? (p - a).dot(d) / denom : 0
                t = min(max(t, 0), 1)
                let q = a.lerp(to: b, t)
                let dist = q.distance(to: p)
                if dist < bestDist {
                    bestDist = dist
                    best = (walked + l * t) / total
                }
                walked += l
            }
            return best
        case .polyline(let pts):
            guard pts.count > 1 else { return 0 }
            let total = polygonLength(pts)
            guard total > 1e-12 else { return 0 }
            var best = 0.0
            var bestDist = Double.greatestFiniteMagnitude
            var walked = 0.0
            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i + 1]
                let l = a.distance(to: b)
                let d = b - a
                let denom = d.dot(d)
                var t = denom > 1e-12 ? (p - a).dot(d) / denom : 0
                t = min(max(t, 0), 1)
                let q = a.lerp(to: b, t)
                let dist = q.distance(to: p)
                if dist < bestDist {
                    bestDist = dist
                    best = (walked + l * t) / total
                }
                walked += l
            }
            return best
        case .functionPlot:
            return 0
        }
    }

    func distance(to p: Vec2) -> Double {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            let d = b - a
            let denom = d.dot(d)
            if denom < 1e-12 { return p.distance(to: a) }
            var t = (p - a).dot(d) / denom
            switch self {
            case .segment: t = min(max(t, 0), 1)
            case .ray: t = max(t, 0)
            default: break
            }
            return p.distance(to: a.lerp(to: b, t))
        case .circle(let c, let r):
            return abs(p.distance(to: c) - r)
        case .polygon(let pts):
            guard pts.count > 1 else { return pts.first?.distance(to: p) ?? .infinity }
            var best = Double.greatestFiniteMagnitude
            for i in 0..<pts.count {
                let seg = EvalPath.segment(pts[i], pts[(i + 1) % pts.count])
                best = min(best, seg.distance(to: p))
            }
            return best
        case .polyline(let pts):
            guard pts.count > 1 else { return pts.first?.distance(to: p) ?? .infinity }
            var best = Double.greatestFiniteMagnitude
            for i in 0..<(pts.count - 1) {
                best = min(best, EvalPath.segment(pts[i], pts[i + 1]).distance(to: p))
            }
            return best
        case .functionPlot:
            return .infinity
        }
    }

    var boundingBox: WorldRect? {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            return WorldRect(minX: min(a.x, b.x), minY: min(a.y, b.y),
                             maxX: max(a.x, b.x), maxY: max(a.y, b.y))
        case .circle(let c, let r):
            return WorldRect(minX: c.x - r, minY: c.y - r, maxX: c.x + r, maxY: c.y + r)
        case .polygon(let pts):
            guard let first = pts.first else { return nil }
            var box = WorldRect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
            for p in pts {
                box.minX = min(box.minX, p.x); box.maxX = max(box.maxX, p.x)
                box.minY = min(box.minY, p.y); box.maxY = max(box.maxY, p.y)
            }
            return box
        case .polyline(let pts):
            guard let first = pts.first else { return nil }
            var box = WorldRect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
            for p in pts {
                box.minX = min(box.minX, p.x); box.maxX = max(box.maxX, p.x)
                box.minY = min(box.minY, p.y); box.maxY = max(box.maxY, p.y)
            }
            return box
        case .functionPlot:
            return nil
        }
    }

    func length(settings: CanvasSettings) -> Double? {
        switch self {
        case .segment(let a, let b): return a.distance(to: b)
        case .circle(let _, let r): return 2 * .pi * r
        case .polygon(let pts): return polygonLength(pts)
        case .polyline(let pts): return polygonLength(pts)
        case .ray, .line, .functionPlot: return nil
        }
    }

    /// Whether a point lies inside a closed polygon. The original
    /// (`routine`) walks the vertices, sums `atan2(cross, dot)` for the
    /// vectors seen from the point, divides by 2π and tests the fractional
    /// part against 0 within 1e-12. That is the winding-number test; a
    /// non-zero winding count means inside.
    func contains(_ p: Vec2) -> Bool {
        guard case .polygon(let pts) = self, pts.count >= 3 else { return false }
        var sum = 0.0
        for i in 0..<pts.count {
            let a = pts[i] - p
            let b = pts[(i + 1) % pts.count] - p
            sum += atan2(a.cross(b), a.dot(b))
        }
        return abs(sum) > .pi
    }

    func intersections(with other: EvalPath) -> [Vec2] {
        if let s1 = straight, let s2 = other.straight {
            return straightIntersections(s1, s2)
        }
        if let s = straight, case .circle(let c, let r) = other {
            return lineCircle(s, c, r)
        }
        if case .circle(let c, let r) = self, let s = other.straight {
            return lineCircle(s, c, r)
        }
        if case .circle(let c1, let r1) = self, case .circle(let c2, let r2) = other {
            return circleCircle(c1, r1, c2, r2)
        }
        if case .polygon(let pts) = self {
            var out: [Vec2] = []
            for i in 0..<max(pts.count, 1) {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                out.append(contentsOf: EvalPath.segment(a, b).intersections(with: other))
            }
            return dedupe(out)
        }
        if case .polygon(let pts) = other {
            var out: [Vec2] = []
            for i in 0..<max(pts.count, 1) {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                out.append(contentsOf: self.intersections(with: .segment(a, b)))
            }
            return dedupe(out)
        }
        if case .polyline(let pts) = self {
            var out: [Vec2] = []
            for i in 0..<max(pts.count - 1, 0) {
                out.append(contentsOf: EvalPath.segment(pts[i], pts[i + 1]).intersections(with: other))
            }
            return dedupe(out)
        }
        if case .polyline(let pts) = other {
            var out: [Vec2] = []
            for i in 0..<max(pts.count - 1, 0) {
                out.append(contentsOf: self.intersections(with: .segment(pts[i], pts[i + 1])))
            }
            return dedupe(out)
        }
        return []
    }
}

private func polygonLength(_ pts: [Vec2]) -> Double {
    guard pts.count > 1 else { return 0 }
    var total = 0.0
    for i in 0..<pts.count {
        total += pts[i].distance(to: pts[(i + 1) % pts.count])
    }
    return total
}

private func dedupe(_ pts: [Vec2]) -> [Vec2] {
    var out: [Vec2] = []
    for p in pts where !out.contains(where: { $0.distance(to: p) < 1e-7 }) {
        out.append(p)
    }
    return out
}

private func straightIntersections(_ s1: (a: Vec2, b: Vec2, kind: Int),
                                   _ s2: (a: Vec2, b: Vec2, kind: Int)) -> [Vec2] {
    let r = s1.b - s1.a
    let s = s2.b - s2.a
    let denom = r.cross(s)
    if abs(denom) < 1e-12 { return [] }
    let qp = s2.a - s1.a
    let t = qp.cross(s) / denom
    let u = qp.cross(r) / denom
    if s1.kind == 0 && (t < -1e-9 || t > 1 + 1e-9) { return [] }
    if s1.kind == 1 && t < -1e-9 { return [] }
    if s2.kind == 0 && (u < -1e-9 || u > 1 + 1e-9) { return [] }
    if s2.kind == 1 && u < -1e-9 { return [] }
    return [s1.a.lerp(to: s1.b, t)]
}

private func lineCircle(_ s: (a: Vec2, b: Vec2, kind: Int), _ c: Vec2, _ r: Double) -> [Vec2] {
    let d = s.b - s.a
    let f = s.a - c
    let a = d.dot(d)
    guard a > 1e-12 else { return [] }
    let b = 2 * f.dot(d)
    let cc = f.dot(f) - r * r
    let disc = b * b - 4 * a * cc
    if disc < -1e-9 { return [] }
    let sq = sqrt(max(disc, 0))
    var ts = [(-b - sq) / (2 * a), (-b + sq) / (2 * a)]
    ts.sort()
    var out: [Vec2] = []
    for t in ts {
        if s.kind == 0 && (t < -1e-9 || t > 1 + 1e-9) { continue }
        if s.kind == 1 && t < -1e-9 { continue }
        let p = s.a.lerp(to: s.b, t)
        if !out.contains(where: { $0.distance(to: p) < 1e-7 }) { out.append(p) }
    }
    return out
}

private func circleCircle(_ c1: Vec2, _ r1: Double, _ c2: Vec2, _ r2: Double) -> [Vec2] {
    let d = c1.distance(to: c2)
    if d < 1e-12 || d > r1 + r2 + 1e-9 || d < abs(r1 - r2) - 1e-9 { return [] }
    let a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
    let h2 = r1 * r1 - a * a
    let h = sqrt(max(h2, 0))
    let mid = c1 + (c2 - c1).normalized() * a
    let perp = (c2 - c1).normalized().perpendicular()
    if h < 1e-9 { return [mid] }
    return [mid + perp * h, mid - perp * h]
}

func clipLine(_ a: Vec2, _ b: Vec2, to rect: WorldRect) -> (Vec2, Vec2)? {
    // Liang–Barsky, used to draw infinite lines and rays inside the viewport.
    var t0 = 0.0
    var t1 = 1.0
    let dx = b.x - a.x
    let dy = b.y - a.y
    let p = [-dx, dx, -dy, dy]
    let q = [a.x - rect.minX, rect.maxX - a.x, a.y - rect.minY, rect.maxY - a.y]
    for i in 0..<4 {
        if abs(p[i]) < 1e-12 {
            if q[i] < 0 { return nil }
        } else {
            let r = q[i] / p[i]
            if p[i] < 0 {
                if r > t1 { return nil }
                if r > t0 { t0 = r }
            } else {
                if r < t0 { return nil }
                if r < t1 { t1 = r }
            }
        }
    }
    return (a.lerp(to: b, t0), a.lerp(to: b, t1))
}
