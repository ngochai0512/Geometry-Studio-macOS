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

    // MARK: parameters, constructors, vectors and coordinate systems

    func addParameter() {
        let name = nextParameterName()
        checkpoint("Add Parameter")
        var object = SketchObject(kind: .parameter(value: 1, minimum: 0, maximum: 10))
        object.label = name
        object.position = hoverWorld ?? settings.center
        object.order = (objects.map(\.order).max() ?? 0) + 1
        object.showLabel = true
        objects.append(object)
        selection = [object.id]
        statusMessage = "Parameter \(name) created"
    }

    private func nextParameterName() -> String {
        let used = Set(objects.compactMap { object -> String? in
            guard case .parameter = object.kind else {
                return nil
            }
            return object.label
        })
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            let name = String(letter)
            if !used.contains(name) {
                return name
            }
        }
        var index = 1
        while true {
            let name = "p\(index)"
            if !used.contains(name) {
                return name
            }
            index += 1
        }
    }

    func constructPerpendicularBisector() {
        let points = selectedPoints()
        guard points.count >= 2 else {
            statusMessage = "Select two points"
            return
        }
        checkpoint("Construct Perpendicular Bisector")
        let id = commit(kind: .construction(.perpendicularBisector(a: points[0], b: points[1])),
                        label: "")
        selection = [id]
        statusMessage = "Perpendicular bisector created"
    }

    func constructTangents() {
        var e = evaluator()
        var circles: [UUID] = []
        for object in selectedObjects {
            if case .circle = e.path(object.id) {
                circles.append(object.id)
            }
        }
        let points = selectedPoints()
        if circles.count >= 2 {
            checkpoint("Construct Common Tangents")
            var created: [UUID] = []
            for index in 0..<4 {
                created.append(commit(
                    kind: .construction(.tangentCircleToCircle(a: circles[0], b: circles[1], index: index)),
                    label: ""
                ))
            }
            var eval = evaluator()
            let valid = created.filter { eval.path($0) != nil }
            if valid.count != created.count {
                objects.removeAll { created.contains($0.id) && !valid.contains($0.id) }
            }
            selection = valid
            statusMessage = "\(valid.count) common tangent\(valid.count == 1 ? "" : "s") created"
            return
        }
        if let point = points.first, let circle = circles.first {
            checkpoint("Construct Tangents")
            var created: [UUID] = []
            for index in 0..<2 {
                created.append(commit(
                    kind: .construction(.tangentPointToCircle(point: point, circle: circle, index: index)),
                    label: ""
                ))
            }
            var eval = evaluator()
            let valid = created.filter { eval.path($0) != nil }
            if valid.count != created.count {
                objects.removeAll { created.contains($0.id) && !valid.contains($0.id) }
            }
            selection = valid
            statusMessage = "\(valid.count) tangent\(valid.count == 1 ? "" : "s") created"
            return
        }
        statusMessage = "Select a point and a circle, or two circles"
    }

    func constructRadicalAxis() {
        var e = evaluator()
        var circles: [UUID] = []
        for object in selectedObjects {
            if case .circle = e.path(object.id) {
                circles.append(object.id)
            }
        }
        guard circles.count >= 2 else {
            statusMessage = "Select two circles"
            return
        }
        checkpoint("Construct Radical Axis")
        let id = commit(kind: .construction(.radicalAxis(a: circles[0], b: circles[1])), label: "")
        selection = [id]
        statusMessage = "Radical axis created"
    }

    func constructVector() {
        let points = selectedPoints()
        guard points.count >= 2 else {
            statusMessage = "Select a tail and a head point"
            return
        }
        checkpoint("Construct Vector")
        let id = commit(kind: .vector(.fromPoints(from: points[0], to: points[1])), label: "")
        selection = [id]
        statusMessage = "Vector created"
    }

    func constructVectorSum(subtract: Bool) {
        let vectors = selectedObjects.filter { object in
            if case .vector = object.kind {
                return true
            }
            return false
        }
        guard vectors.count >= 2 else {
            statusMessage = "Select two vectors"
            return
        }
        checkpoint(subtract ? "Construct Vector Difference" : "Construct Vector Sum")
        let id = commit(kind: .vector(.sum(a: vectors[0].id, b: vectors[1].id, subtract: subtract)),
                        label: "")
        selection = [id]
        statusMessage = subtract ? "Vector difference created" : "Vector sum created"
    }

    func constructCoordinateSystem(_ kind: CoordinateKind) {
        checkpoint("Add Coordinate System")
        let origin = selectedPoints().first
            ?? ensureSilentPoint(at: hoverWorld ?? settings.center)
        let step = GridMetrics.step(scale: settings.scale,
                                    perUnit: settings.lengthUnit.perUnit)
        let id = commit(kind: .coordinateSystem(kind: kind, origin: origin,
                                                step: step, unit: settings.lengthUnit),
                        label: "")
        selection = [id]
        statusMessage = "\(kind.title) coordinate system created"
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

    private func currentFunctionExpression() -> String? {
        for object in selectedObjects {
            if case .functionPlot(let expression) = object.kind {
                return expression
            }
        }
        for object in objects where object.visible {
            if case .functionPlot(let expression) = object.kind {
                return expression
            }
        }
        return nil
    }

    func addDerivativePlot() {
        guard let source = currentFunctionExpression() else {
            statusMessage = "Select or plot a function first"
            return
        }
        checkpoint("Plot Derivative")
        let id = commit(kind: .graph(.derivative(source)), label: "")
        selection = [id]
        statusMessage = "Derivative plotted"
    }

    func addIntegralPlot(from: Double = -5, to: Double = 5) {
        guard let source = currentFunctionExpression() else {
            statusMessage = "Select or plot a function first"
            return
        }
        guard from.isFinite, to.isFinite, abs(to - from) > 1e-6 else {
            statusMessage = "Choose a valid interval"
            return
        }
        checkpoint("Shade Integral")
        let id = commit(kind: .graph(.integral(source, from: from, to: to)), label: "")
        selection = [id]
        statusMessage = "Integral shaded"
    }

    func addTangentAt(_ x: Double? = nil) {
        guard let source = currentFunctionExpression() else {
            statusMessage = "Select or plot a function first"
            return
        }
        let selectedX = selectedPoints().first.flatMap { objectByID($0)?.position?.x }
        let at = x ?? selectedX ?? 0
        guard at.isFinite else {
            statusMessage = "Choose a valid x"
            return
        }
        checkpoint("Plot Tangent")
        let id = commit(kind: .graph(.tangent(source, x: at)), label: "")
        selection = [id]
        statusMessage = "Tangent plotted"
    }

    func addValueTable(from: Double = -5, to: Double = 5, step: Double = 1) {
        guard let source = currentFunctionExpression() else {
            statusMessage = "Select or plot a function first"
            return
        }
        guard step.isFinite, abs(step) > 1e-6 else {
            statusMessage = "Choose a valid step"
            return
        }
        checkpoint("Add Value Table")
        let id = commit(kind: .graph(.table(source, from: from, to: to, step: step)), label: "")
        selection = [id]
        statusMessage = "Value table created"
    }

    func findFunctionRoots() {
        guard let source = currentFunctionExpression() else {
            statusMessage = "Select or plot a function first"
            return
        }
        let roots = numericalRoots(source, from: -20, to: 20)
        guard !roots.isEmpty else {
            statusMessage = "No roots found in the visible range"
            return
        }
        checkpoint("Find Roots")
        let created = roots.map { ensureSilentPoint(at: Vec2($0, 0)) }
        selection = created
        statusMessage = "\(created.count) root\(created.count == 1 ? "" : "s") found"
    }

    func findFunctionIntersections() {
        let expressions = selectedObjects.compactMap { object -> String? in
            if case .functionPlot(let expression) = object.kind {
                return expression
            }
            return nil
        }
        guard expressions.count >= 2 else {
            statusMessage = "Select two function plots"
            return
        }
        let difference = "((\(expressions[0])) - (\(expressions[1])))"
        let roots = numericalRoots(difference, from: -20, to: 20)
        guard !roots.isEmpty else {
            statusMessage = "No intersections found in the visible range"
            return
        }
        checkpoint("Find Intersections")
        let created = roots.map { x in
            ensureSilentPoint(at: Vec2(x, functionValue(expressions[0], at: x) ?? 0))
        }
        selection = created
        statusMessage = "\(created.count) intersection\(created.count == 1 ? "" : "s") found"
    }

    private func functionValue(_ source: String, at x: Double) -> Double? {
        guard var parser = Expression(source) else {
            return nil
        }
        parser.setAngleUnit(settings.angleUnit)
        return parser.evaluate(x: x)
    }

    private func numericalRoots(_ source: String, from: Double, to: Double) -> [Double] {
        let step = 0.1
        var roots: [Double] = []
        var x = from
        var previous = functionValue(source, at: x)
        while x < to {
            let next = x + step
            let value = functionValue(source, at: next)
            if let a = previous, let b = value {
                if abs(a) < 1e-9 {
                    roots.append(x)
                }
                if a * b < 0 {
                    var low = x
                    var high = next
                    for _ in 0..<40 {
                        let middle = (low + high) / 2
                        guard let middleValue = functionValue(source, at: middle) else {
                            break
                        }
                        if (a < 0 && middleValue < 0) || (a > 0 && middleValue > 0) {
                            low = middle
                        } else {
                            high = middle
                        }
                    }
                    roots.append((low + high) / 2)
                }
            }
            previous = value
            x = next
        }
        var unique: [Double] = []
        for root in roots where !unique.contains(where: { abs($0 - root) < 1e-4 }) {
            unique.append(root)
        }
        return unique
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
