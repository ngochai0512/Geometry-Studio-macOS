import Testing
@testable import GeometryStudio

/// Distance comparisons use the dedupe threshold already used by `EvalPath`.
private func near(_ a: Vec2?, _ b: Vec2, tolerance: Double = 1e-7) -> Bool {
    guard let a else {
        return false
    }
    return a.distance(to: b) <= tolerance
}

@Suite("Vec2")
struct Vec2Tests {
    @Test("distance and lerp")
    func distanceAndLerp() {
        let a = Vec2(0, 0)
        let b = Vec2(3, 4)
        #expect(abs(a.distance(to: b) - 5) < 1e-12)
        #expect(near(a.lerp(to: b, 0.5), Vec2(1.5, 2)))
    }

    @Test("perpendicular and rotation")
    func perpendicularAndRotation() {
        #expect(near(Vec2(1, 0).perpendicular(), Vec2(0, 1)))
        #expect(near(Vec2(1, 0).rotated(by: .pi / 2), Vec2(0, 1)))
    }
}

@Suite("EvalPath intersections")
struct EvalPathIntersectionTests {
    @Test("line and line cross once")
    func lineLine() {
        let hits = EvalPath.line(Vec2(0, 0), Vec2(2, 2))
            .intersections(with: .line(Vec2(0, 2), Vec2(2, 0)))
        #expect(hits.count == 1)
        #expect(near(hits.first, Vec2(1, 1)))
    }

    @Test("parallel lines do not intersect")
    func parallelLines() {
        let hits = EvalPath.line(Vec2(0, 0), Vec2(1, 0))
            .intersections(with: .line(Vec2(0, 1), Vec2(1, 1)))
        #expect(hits.isEmpty)
    }

    @Test("segments clamp to their bounds")
    func segmentBounds() {
        let hits = EvalPath.segment(Vec2(0, 0), Vec2(1, 0))
            .intersections(with: .segment(Vec2(2, -1), Vec2(2, 1)))
        #expect(hits.isEmpty)
    }

    @Test("line cuts a circle twice")
    func lineCircle() {
        let hits = EvalPath.line(Vec2(-2, 0), Vec2(2, 0))
            .intersections(with: .circle(Vec2(0, 0), 1))
        #expect(hits.count == 2)
        #expect(hits.contains { near($0, Vec2(-1, 0)) })
        #expect(hits.contains { near($0, Vec2(1, 0)) })
    }

    @Test("a tangent line touches once")
    func tangent() {
        let hits = EvalPath.line(Vec2(-2, 1), Vec2(2, 1))
            .intersections(with: .circle(Vec2(0, 0), 1))
        #expect(hits.count == 1)
        #expect(near(hits.first, Vec2(0, 1)))
    }

    @Test("overlapping circles cross twice")
    func circleCircle() {
        let hits = EvalPath.circle(Vec2(0, 0), 1)
            .intersections(with: .circle(Vec2(1, 0), 1))
        #expect(hits.count == 2)
        #expect(hits.contains { near($0, Vec2(0.5, 3.0.squareRoot() / 2)) })
        #expect(hits.contains { near($0, Vec2(0.5, -3.0.squareRoot() / 2)) })
    }

    @Test("distant circles do not intersect")
    func distantCircles() {
        let hits = EvalPath.circle(Vec2(0, 0), 1)
            .intersections(with: .circle(Vec2(5, 0), 1))
        #expect(hits.isEmpty)
    }
}

@Suite("EvalPath geometry")
struct EvalPathGeometryTests {
    @Test("polygon containment uses the winding number")
    func polygonContainment() {
        let triangle = EvalPath.polygon([Vec2(0, 0), Vec2(2, 0), Vec2(0, 2)])
        #expect(triangle.contains(Vec2(0.5, 0.5)))
        #expect(!triangle.contains(Vec2(2, 2)))
    }

    @Test("nearest parameter clamps on a segment")
    func nearestParamClamps() {
        let segment = EvalPath.segment(Vec2(0, 0), Vec2(10, 0))
        #expect(abs(segment.nearestParam(to: Vec2(20, 5)) - 1) < 1e-12)
        #expect(abs(segment.nearestParam(to: Vec2(5, 3)) - 0.5) < 1e-12)
    }

    @Test("circle distance is the gap to the rim")
    func circleDistance() {
        #expect(abs(EvalPath.circle(Vec2(0, 0), 1).distance(to: Vec2(2, 0)) - 1) < 1e-12)
    }

    @Test("circle length is the circumference")
    func circleLength() {
        let value = EvalPath.circle(Vec2(0, 0), 1).length(settings: CanvasSettings())
        #expect(abs((value ?? 0) - 2 * .pi) < 1e-12)
    }

    @Test("polygon area is independent of winding direction")
    func shoelaceArea() {
        let square = [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)]
        #expect(abs(polygonArea(square) - 4) < 1e-9)
        #expect(abs(polygonArea(Array(square.reversed())) - 4) < 1e-9)
        #expect(abs(polygonArea([Vec2(0, 0), Vec2(1, 0)]) - 0) < 1e-12)
    }
}
