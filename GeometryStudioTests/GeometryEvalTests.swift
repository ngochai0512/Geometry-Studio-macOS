import Testing
@testable import GeometryStudio

private func freePoint(_ p: Vec2) -> SketchObject {
    var object = SketchObject(kind: .freePoint)
    object.position = p
    return object
}

private func near(_ a: Vec2?, _ b: Vec2) -> Bool {
    guard let a else { return false }
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

    @Test("a self-referencing object yields nothing instead of recursing")
    func cycleSafety() {
        var object = SketchObject(kind: .freePoint)
        object.kind = .midpoint(a: object.id, b: object.id)
        var eval = GeometryEval(objects: [object], settings: CanvasSettings())
        #expect(eval.point(object.id) == nil)
    }
}
