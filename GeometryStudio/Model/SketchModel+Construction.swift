import SwiftUI

extension SketchModel {

    // MARK: construction commands

    func selectedPoints() -> [UUID] {
        selectedObjects.filter { object in
            var e = evaluator()
            return e.evaluate(object.id).point != nil
        }.map(\.id)
    }

    func selectedPaths() -> [UUID] {
        selectedObjects.filter { object in
            var e = evaluator()
            return e.evaluate(object.id).path != nil
        }.map(\.id)
    }

    func selectedStraights() -> [UUID] {
        selectedObjects.filter { object in
            var e = evaluator()
            guard let p = e.evaluate(object.id).path?.straight else {
                return false
            }
            _ = p
            return true
        }.map(\.id)
    }

    func constructMidpoint() {
        let pts = selectedPoints()
        if pts.count >= 2 {
            checkpoint("Construct Midpoint")
            let id = commit(kind: .midpoint(a: pts[0], b: pts[1]), label: nextPointLabel())
            selection = [id]
            statusMessage = "Midpoint created"
            return
        }
        var e = evaluator()
        if let pathID = selectedPaths().first, let s = e.path(pathID)?.straight {
            checkpoint("Construct Midpoint")
            let a = ensureSilentPoint(at: s.a)
            let b = ensureSilentPoint(at: s.b)
            let id = commit(kind: .midpoint(a: a, b: b), label: nextPointLabel())
            selection = [id]
            statusMessage = "Midpoint created"
            return
        }
        statusMessage = "Select two points or a segment first"
    }

    func constructPerpendicular() {
        let points = selectedPoints()
        let straights = selectedStraights()
        guard let point = points.first, let line = straights.first else {
            statusMessage = "Select a point and a straight object"
            return
        }
        checkpoint("Construct Perpendicular")
        let id = commit(kind: .perpendicular(line: line, point: point), label: "")
        selection = [id]
        statusMessage = "Perpendicular created"
    }

    func constructParallel() {
        let points = selectedPoints()
        let straights = selectedStraights()
        guard let point = points.first, let line = straights.first else {
            statusMessage = "Select a point and a straight object"
            return
        }
        checkpoint("Construct Parallel")
        let id = commit(kind: .parallel(line: line, point: point), label: "")
        selection = [id]
        statusMessage = "Parallel created"
    }

    func constructBisector() {
        let pts = selectedPoints()
        guard pts.count >= 3 else {
            statusMessage = "Select three points, with the vertex in the middle"
            return
        }
        checkpoint("Construct Angle Bisector")
        let id = commit(kind: .angleBisector(a: pts[0], vertex: pts[1], c: pts[2]), label: "")
        selection = [id]
        statusMessage = "Angle bisector created"
    }

    func constructIntersection() {
        let paths = selectedPaths()
        guard paths.count >= 2 else {
            statusMessage = "Select two paths first"
            return
        }
        var e = evaluator()
        guard let p1 = e.path(paths[0]), let p2 = e.path(paths[1]) else {
            return
        }
        let hits = p1.intersections(with: p2)
        guard !hits.isEmpty else {
            statusMessage = "Those objects do not meet"
            return
        }
        checkpoint("Construct Intersection")
        var created: [UUID] = []
        for i in hits.indices {
            let id = commit(kind: .intersection(a: paths[0], b: paths[1], index: i), label: nextPointLabel())
            created.append(id)
        }
        selection = created
        statusMessage = "\(created.count) intersection\(created.count == 1 ? "" : "s") created"
    }

    func constructSegment() {
        let pts = selectedPoints()
        guard pts.count >= 2 else {
            statusMessage = "Select at least two points"
            return
        }
        checkpoint("Construct Segment")
        var created: [UUID] = []
        for i in 0..<(pts.count - 1) {
            created.append(commit(kind: .segment(a: pts[i], b: pts[i + 1]), label: ""))
        }
        selection = created
        statusMessage = "Segment created"
    }

    func constructCircle() {
        let pts = selectedPoints()
        guard pts.count >= 2 else {
            statusMessage = "Select a center point and a point on the circle"
            return
        }
        checkpoint("Construct Circle")
        let id = commit(kind: .circle(center: pts[0], through: pts[1]), label: "")
        selection = [id]
        statusMessage = "Circle created"
    }

    func constructCircleRadius(_ displayRadius: Double) {
        guard let center = selectedPoints().first else {
            statusMessage = "Select a center point first"
            return
        }
        let radius = displayRadius * settings.lengthUnit.perUnit
        guard radius.isFinite, radius > 0 else {
            statusMessage = "Enter a radius greater than zero"
            return
        }
        checkpoint("Construct Circle by Radius")
        let id = commit(kind: .circleRadius(center: center, radius: radius), label: "")
        selection = [id]
        statusMessage = "Circle created"
    }

    func constructArcOnCircle() {
        guard let circle = selectedObjects.first(where: { object in
            switch object.kind {
            case .circle, .circleRadius:
                return true
            default:
                return false
            }
        }) else {
            statusMessage = "Select a circle and two points on it"
            return
        }
        let pts = selectedPoints()
        guard pts.count >= 2 else {
            statusMessage = "Select a circle and two points on it"
            return
        }
        var e = evaluator()
        guard let circlePath = e.path(circle.id),
              case .circle(let center, _) = circlePath,
              let ps = e.point(pts[0]),
              let pe = e.point(pts[1]) else {
            statusMessage = "Select a circle and two points on it"
            return
        }
        let start = (ps - center).angle
        var sweep = (pe - center).angle - start
        while sweep <= 1e-9 {
            sweep += 2 * .pi
        }
        guard sweep < 2 * .pi - 1e-9 else {
            statusMessage = "Choose two different points on the circle"
            return
        }
        checkpoint("Construct Arc")
        let id = commit(kind: .arcOnCircle(circle: circle.id, start: pts[0], end: pts[1]),
                        label: "")
        selection = [id]
        statusMessage = "Arc created"
    }

    func constructArcThroughPoints() {
        let pts = selectedPoints()
        guard pts.count >= 3 else {
            statusMessage = "Select three points: start, through, end"
            return
        }
        var e = evaluator()
        guard let a = e.point(pts[0]), let b = e.point(pts[1]), let c = e.point(pts[2]) else {
            statusMessage = "Select three points: start, through, end"
            return
        }
        guard abs((b - a).cross(c - a)) > 1e-9 else {
            statusMessage = "Those points are collinear"
            return
        }
        checkpoint("Construct Arc")
        let id = commit(kind: .arcThroughPoints(a: pts[0], b: pts[1], c: pts[2]), label: "")
        selection = [id]
        statusMessage = "Arc created"
    }

    func constructPolygon() {
        let pts = selectedPoints()
        guard pts.count >= 3 else {
            statusMessage = "Select at least three points"
            return
        }
        checkpoint("Construct Polygon")
        let id = commit(kind: .polygon(vertices: pts), label: "")
        selection = [id]
        statusMessage = "Polygon created"
    }

    func constructPointOnPath() {
        guard let id = selectedPaths().first, let object = objectByID(id) else {
            statusMessage = "Select a path first"
            return
        }
        _ = object
        var e = evaluator()
        guard let path = e.path(id) else {
            return
        }
        let worldCenter = settings.center
        checkpoint("Construct Point on Path")
        let newID = commit(kind: .pointOnPath(path: id, param: path.nearestParam(to: worldCenter)),
                            label: nextPointLabel())
        selection = [newID]
        statusMessage = "Point attached to the path"
    }

    func ensureSilentPoint(at p: Vec2) -> UUID {
        if let id = existingPoint(near: p, tolerance: 0.04) {
            return id
        }
        var object = SketchObject(kind: .freePoint)
        object.position = p
        object.label = nextPointLabel()
        object.order = (objects.map(\.order).max() ?? 0) + 1
        objects.append(object)
        return object.id
    }

    func commit(kind: ObjectKind, label: String) -> UUID {
        var object = SketchObject(kind: kind)
        object.label = label
        object.order = (objects.map(\.order).max() ?? 0) + 1
        object.showLabel = isLabelWorthy(kind)
        objects.append(object)
        return object.id
    }

    // MARK: graph

    func addFunctionPlot(expression: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Expression(trimmed) != nil else {
            statusMessage = "That expression could not be read"
            return
        }
        checkpoint("Plot Function")
        let id = commit(kind: .functionPlot(trimmed), label: "")
        selection = [id]
        statusMessage = "Function plotted"
    }

    // MARK: protocol

    func constructionProtocol() -> [String] {
        let eval = evaluator()
        let ordered = objects.enumerated()
            .sorted { left, right in
                if left.element.order == right.element.order {
                    return left.offset < right.offset
                }
                return left.element.order < right.element.order
            }
            .map { $0.element }
        return ordered.map { eval.definition(of: $0.id) }
    }
}
