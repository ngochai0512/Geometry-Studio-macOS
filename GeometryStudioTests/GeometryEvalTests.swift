import Foundation
import Testing
@testable import GeometryStudio

private func freePoint(_ p: Vec2) -> SketchObject {
    var object = SketchObject(kind: .freePoint)
    object.position = p
    return object
}

private func near(_ a: Vec2?, _ b: Vec2) -> Bool {
    guard let a else {
        return false
    }
    return a.distance(to: b) <= 1e-7
}

@Suite("GeometryEval")
struct GeometryEvalTests {
    @Test("midpoint resolves its parent points")
    func midpoint() {
        let a = freePoint(Vec2(0, 0))
        let b = freePoint(Vec2(4, 2))
        let mid = SketchObject(kind: .midpoint(a: a.id, b: b.id))
        var eval = GeometryEval(objects: [mid, a, b], settings: CanvasSettings())
        #expect(near(eval.point(mid.id), Vec2(2, 1)))
    }

    @Test("dependents evaluate even when listed first")
    func dependencyOrdering() {
        let p = freePoint(Vec2(0, 0))
        let lineA = freePoint(Vec2(0, 1))
        let lineB = freePoint(Vec2(1, 1))
        let line = SketchObject(kind: .line(a: lineA.id, b: lineB.id))
        let spec = TransformSpec(kind: .reflect, reference: line.id)
        let image = SketchObject(kind: .transformed(source: p.id, spec: spec))
        var eval = GeometryEval(objects: [image, line, p, lineA, lineB], settings: CanvasSettings())
        #expect(near(eval.point(image.id), Vec2(0, 2)))
    }

    @Test("a marked rotation angle is read live")
    func markedRotation() {
        let center = freePoint(Vec2(0, 0))
        let first = freePoint(Vec2(1, 0))
        let second = freePoint(Vec2(0, 1))
        let target = freePoint(Vec2(2, 0))
        let spec = TransformSpec(
            kind: .rotate,
            reference: center.id,
            angle: 10,
            angleMark: AngleMark(a: first.id, vertex: center.id, c: second.id)
        )
        let image = SketchObject(kind: .transformed(source: target.id, spec: spec))

        var eval = GeometryEval(objects: [target, image, center, first, second],
                                settings: CanvasSettings())
        #expect(near(eval.point(image.id), Vec2(0, 2)))

        var moved = second
        moved.position = Vec2(0, -1)
        var reevaluated = GeometryEval(objects: [target, image, center, first, moved],
                                       settings: CanvasSettings())
        #expect(near(reevaluated.point(image.id), Vec2(0, -2)))
    }

    @Test("a marked dilation ratio is read live")
    func markedDilation() {
        let center = freePoint(Vec2(0, 0))
        let a = freePoint(Vec2(2, 0))
        let b = freePoint(Vec2(0, 1))
        let target = freePoint(Vec2(1, 1))
        let first = SketchObject(kind: .segment(a: center.id, b: a.id))
        let second = SketchObject(kind: .segment(a: center.id, b: b.id))
        let spec = TransformSpec(
            kind: .dilate,
            reference: center.id,
            factor: 0.5,
            ratioMark: RatioMark(first: first.id, second: second.id)
        )
        let image = SketchObject(kind: .transformed(source: target.id, spec: spec))

        var eval = GeometryEval(objects: [target, image, center, a, b, first, second],
                                settings: CanvasSettings())
        #expect(near(eval.point(image.id), Vec2(2, 2)))

        var movedB = b
        movedB.position = Vec2(0, 2)
        var reevaluated = GeometryEval(objects: [target, image, center, a, movedB, first, second],
                                       settings: CanvasSettings())
        #expect(near(reevaluated.point(image.id), Vec2(1, 1)))
    }

    @Test("point on a segment at half its parameter is the midpoint")
    func pointOnPath() {
        let a = freePoint(Vec2(0, 0))
        let b = freePoint(Vec2(2, 0))
        let segment = SketchObject(kind: .segment(a: a.id, b: b.id))
        let onPath = SketchObject(kind: .pointOnPath(path: segment.id, param: 0.5))
        var eval = GeometryEval(objects: [onPath, segment, a, b], settings: CanvasSettings())
        #expect(near(eval.point(onPath.id), Vec2(1, 0)))
    }

    @Test("intersection returns the requested root")
    func intersectionIndex() {
        let a = freePoint(Vec2(-2, 0))
        let b = freePoint(Vec2(2, 0))
        let c = freePoint(Vec2(0, -2))
        let d = freePoint(Vec2(0, 2))
        let horizontal = SketchObject(kind: .line(a: a.id, b: b.id))
        let vertical = SketchObject(kind: .line(a: c.id, b: d.id))
        let hit = SketchObject(kind: .intersection(a: horizontal.id, b: vertical.id, index: 0))
        var eval = GeometryEval(objects: [hit, horizontal, vertical, a, b, c, d],
                                settings: CanvasSettings())
        #expect(near(eval.point(hit.id), Vec2(0, 0)))
    }

    @Test("distance measurement reports the gap")
    func distanceMeasurement() {
        let a = freePoint(Vec2(0, 0))
        let b = freePoint(Vec2(3, 4))
        let measurement = SketchObject(kind: .measurement(.distance, refs: [a.id, b.id]))
        var eval = GeometryEval(objects: [a, b, measurement], settings: CanvasSettings())
        let result = eval.evaluate(measurement.id)
        #expect(abs((result.value ?? 0) - 5) < 1e-9)
        #expect(result.text?.hasPrefix("m ") == true)
    }

    @Test("coordinate measurements read x, y, radius and direction")
    func coordinateMeasurements() {
        let a = freePoint(Vec2(3, 4))
        let abscissa = SketchObject(kind: .measurement(.abscissa, refs: [a.id]))
        let ordinate = SketchObject(kind: .measurement(.ordinate, refs: [a.id]))
        let polarDistance = SketchObject(kind: .measurement(.polarDistance, refs: [a.id]))
        let polarDirection = SketchObject(kind: .measurement(.polarDirection, refs: [a.id]))
        var eval = GeometryEval(objects: [a, abscissa, ordinate, polarDistance, polarDirection],
                                settings: CanvasSettings())

        #expect(abs((eval.evaluate(abscissa.id).value ?? 0) - 3) < 1e-9)
        #expect(abs((eval.evaluate(ordinate.id).value ?? 0) - 4) < 1e-9)
        #expect(abs((eval.evaluate(polarDistance.id).value ?? 0) - 5) < 1e-9)
        #expect(abs((eval.evaluate(polarDirection.id).value ?? 0) - atan2(4.0, 3.0)) < 1e-9)
    }

    @Test("an arc through three points is centred on their circumcircle")
    func arcThroughPoints() {
        let a = freePoint(Vec2(0, 0))
        let b = freePoint(Vec2(1, 1))
        let c = freePoint(Vec2(2, 0))
        let arc = SketchObject(kind: .arcThroughPoints(a: a.id, b: b.id, c: c.id))
        var eval = GeometryEval(objects: [a, b, c, arc], settings: CanvasSettings())

        guard case .arc(let center, let radius, let start, let sweep)? = eval.path(arc.id) else {
            Issue.record("expected an arc")
            return
        }
        #expect(center.distance(to: Vec2(1, 0)) < 1e-9)
        #expect(abs(radius - 1) < 1e-9)
        #expect(abs(start - .pi) < 1e-9)
        #expect(abs(sweep + .pi) < 1e-9)
    }

    @Test("an arc on a circle runs counter-clockwise between its points")
    func arcOnCircle() {
        let center = freePoint(Vec2(0, 0))
        let through = freePoint(Vec2(2, 0))
        let circle = SketchObject(kind: .circle(center: center.id, through: through.id))
        let start = freePoint(Vec2(2, 0))
        let end = freePoint(Vec2(0, 2))
        let arc = SketchObject(kind: .arcOnCircle(circle: circle.id, start: start.id, end: end.id))
        var eval = GeometryEval(objects: [center, through, circle, start, end, arc],
                                settings: CanvasSettings())

        guard case .arc(let arcCenter, let radius, let arcStart, let sweep)? = eval.path(arc.id) else {
            Issue.record("expected an arc")
            return
        }
        #expect(arcCenter.distance(to: Vec2(0, 0)) < 1e-9)
        #expect(abs(radius - 2) < 1e-9)
        #expect(abs(arcStart) < 1e-9)
        #expect(abs(sweep - .pi / 2) < 1e-9)
    }

    @Test("arc angle and length measurements")
    func arcMeasurements() {
        let a = freePoint(Vec2(0, 0))
        let b = freePoint(Vec2(1, 1))
        let c = freePoint(Vec2(2, 0))
        let arc = SketchObject(kind: .arcThroughPoints(a: a.id, b: b.id, c: c.id))
        let angle = SketchObject(kind: .measurement(.arcAngle, refs: [arc.id]))
        let length = SketchObject(kind: .measurement(.arcLength, refs: [arc.id]))
        var eval = GeometryEval(objects: [a, b, c, arc, angle, length],
                                settings: CanvasSettings())

        #expect(abs((eval.evaluate(angle.id).value ?? 0) - .pi) < 1e-9)
        #expect(abs((eval.evaluate(length.id).value ?? 0) - .pi) < 1e-9)
    }

    @Test("a self-referencing object yields nothing instead of recursing")
    func cycleSafety() {
        var object = SketchObject(kind: .freePoint)
        object.kind = .midpoint(a: object.id, b: object.id)
        var eval = GeometryEval(objects: [object], settings: CanvasSettings())
        #expect(eval.point(object.id) == nil)
    }

    @Test("a circle can be built from its centre and a numeric radius")
    func circleByRadius() {
        let center = freePoint(Vec2(1, 2))
        let circle = SketchObject(kind: .circleRadius(center: center.id, radius: 3))
        var eval = GeometryEval(objects: [center, circle], settings: CanvasSettings())

        guard case .circle(let resolvedCenter, let radius)? = eval.path(circle.id) else {
            Issue.record("expected a circle")
            return
        }
        #expect(near(resolvedCenter, Vec2(1, 2)))
        #expect(abs(radius - 3) < 1e-9)
    }

    @Test("arc fills produce sector and segment regions")
    func arcFills() {
        let a = freePoint(Vec2(0, 0))
        let b = freePoint(Vec2(1, 1))
        let c = freePoint(Vec2(2, 0))

        var sectorArc = SketchObject(kind: .arcThroughPoints(a: a.id, b: b.id, c: c.id))
        sectorArc.arcFill = .sector
        var segmentArc = SketchObject(kind: .arcThroughPoints(a: a.id, b: b.id, c: c.id))
        segmentArc.arcFill = .segment
        var eval = GeometryEval(objects: [a, b, c, sectorArc, segmentArc],
                                settings: CanvasSettings())

        guard case .polygon(let sectorPoints)? = eval.evaluate(sectorArc.id).fill else {
            Issue.record("expected a sector fill")
            return
        }
        #expect(sectorPoints.count > 2)
        #expect(near(sectorPoints.first, Vec2(1, 0)))

        guard case .polygon(let segmentPoints)? = eval.evaluate(segmentArc.id).fill else {
            Issue.record("expected a segment fill")
            return
        }
        #expect(segmentPoints.count > 2)
        #expect(!segmentPoints.contains { $0.distance(to: Vec2(1, 0)) < 1e-7 })
    }

    @Test("definitions name the parents of a construction")
    func definitions() {
        let a = freePoint(Vec2(0, 0))
        let b = freePoint(Vec2(4, 2))
        a.label = "A"
        b.label = "B"
        let midpoint = SketchObject(kind: .midpoint(a: a.id, b: b.id))
        var eval = GeometryEval(objects: [a, b, midpoint], settings: CanvasSettings())
        let definition = eval.definition(of: midpoint.id)
        #expect(definition.contains("Midpoint"))
        #expect(definition.contains("A"))
        #expect(definition.contains("B"))
    }
}
