import Foundation

private typealias Tolerance = EvalPathTolerance

// MARK: - Clipping

func clipLine(_ a: Vec2, _ b: Vec2, to rect: WorldRect) -> (Vec2, Vec2)? {
    // Liang–Barsky, used to draw infinite lines and rays inside the viewport.
    var lower = 0.0
    var upper = 1.0
    let delta = b - a
    let normals = [-delta.x, delta.x, -delta.y, delta.y]
    let distances = [
        a.x - rect.minX,
        rect.maxX - a.x,
        a.y - rect.minY,
        rect.maxY - a.y
    ]
    for index in 0..<4 {
        let normal = normals[index]
        let distance = distances[index]
        if abs(normal) < Tolerance.zero {
            if distance < 0 {
                return nil
            }
        } else {
            let ratio = distance / normal
            if normal < 0 {
                if ratio > upper {
                    return nil
                }
                if ratio > lower {
                    lower = ratio
                }
            } else {
                if ratio < lower {
                    return nil
                }
                if ratio < upper {
                    upper = ratio
                }
            }
        }
    }
    return (a.lerp(to: b, lower), a.lerp(to: b, upper))
}

// MARK: - Marquee intersection

extension EvalPath {
    /// True when any part of the path passes through `rect` or lies inside it.
    /// Marquee selection uses this instead of `boundingBox`, so the empty
    /// corner of a diagonal segment's rectangle no longer selects it.
    func intersects(_ rect: WorldRect) -> Bool {
        switch self {
        case .segment(let a, let b):
            return segmentIntersectsRect(a, b, rect)

        case .ray(let a, let b):
            let direction = (b - a).normalized()
            let far = max(rect.width, rect.height) * 4 + 1
            return clipLine(a, b + direction * far, to: rect) != nil

        case .line(let a, let b):
            let direction = (b - a).normalized()
            let far = max(rect.width, rect.height) * 4 + 1
            return clipLine(a - direction * far, b + direction * far, to: rect) != nil

        case .circle(let center, let radius):
            let nearestX = min(max(center.x, rect.minX), rect.maxX)
            let nearestY = min(max(center.y, rect.minY), rect.maxY)
            let nearest = center.distance(to: Vec2(nearestX, nearestY))
            let farX = max(abs(center.x - rect.minX), abs(center.x - rect.maxX))
            let farY = max(abs(center.y - rect.minY), abs(center.y - rect.maxY))
            let farthest = hypot(farX, farY)
            return nearest <= radius && radius <= farthest

        case .arc(let center, let radius, let start, let sweep):
            let steps = max(8, min(180, Int(abs(sweep) / (2 * .pi) * 180)))
            return sampledSegmentsIntersect(rect, count: steps) { index in
                let angle = start + sweep * Double(index) / Double(steps)
                return center + Vec2(cos(angle), sin(angle)) * radius
            }

        case .polygon(let points):
            return openPolylineIntersects(points, closed: true, rect: rect)

        case .polyline(let points):
            return openPolylineIntersects(points, closed: false, rect: rect)

        case .functionPlot:
            guard let box = boundingBox else {
                return false
            }
            return rect.minX <= box.maxX && rect.maxX >= box.minX
                && rect.minY <= box.maxY && rect.maxY >= box.minY
        }
    }

    private func openPolylineIntersects(_ points: [Vec2], closed: Bool,
                                        rect: WorldRect) -> Bool {
        guard let first = points.first else {
            return false
        }
        if points.contains(where: rect.contains) {
            return true
        }
        guard points.count > 1 else {
            return rect.contains(first)
        }
        for index in 0..<(points.count - 1) where segmentIntersectsRect(points[index], points[index + 1], rect) {
            return true
        }
        if closed, let last = points.last {
            return segmentIntersectsRect(last, first, rect)
        }
        return false
    }

    private func sampledSegmentsIntersect(_ rect: WorldRect, count: Int,
                                          point: (Int) -> Vec2) -> Bool {
        var previous = point(0)
        if rect.contains(previous) {
            return true
        }
        for index in 1...count {
            let current = point(index)
            if rect.contains(current) || segmentIntersectsRect(previous, current, rect) {
                return true
            }
            previous = current
        }
        return false
    }

    private func segmentIntersectsRect(_ a: Vec2, _ b: Vec2, _ rect: WorldRect) -> Bool {
        if rect.contains(a) || rect.contains(b) {
            return true
        }
        let corners = [
            Vec2(rect.minX, rect.minY),
            Vec2(rect.maxX, rect.minY),
            Vec2(rect.maxX, rect.maxY),
            Vec2(rect.minX, rect.maxY)
        ]
        for index in 0..<4 where segmentsCross(a, b, corners[index], corners[(index + 1) % 4]) {
            return true
        }
        return false
    }

    private func segmentsCross(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Bool {
        let d1 = orientation(a, b, c)
        let d2 = orientation(a, b, d)
        let d3 = orientation(c, d, a)
        let d4 = orientation(c, d, b)
        let first = (d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)
        let second = (d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)
        return first && second
    }

    private func orientation(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
}
