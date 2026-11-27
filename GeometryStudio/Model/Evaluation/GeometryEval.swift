import Foundation

struct EvalResult {
    var point: Vec2?
    var path: EvalPath?
    var fill: EvalPath?
    var text: String?
    var anchor: Vec2?
    var value: Double?
    var anglePoints: (Vec2, Vec2, Vec2)?
    var angleValue: Double?
    /// A directed vector drawn from `from` to `to`, used for the arrowhead.
    var arrow: (from: Vec2, to: Vec2)?
}

struct GeometryEval {
    /// Tolerances, sampling counts, label radii and number formatting shared
    /// by the evaluator; none of them are user-facing units, so they live here
    /// rather than in `SketchMetrics`.
    enum Metrics {
        static let epsilon = 1e-9
        static let degenerate = 1e-12
        static let locusSamples = 96
        static let arcFillSamples = 96
        static let locusDedupTolerance = 1e-6
        static let angleLabelRadius = 0.72
        static let measuredAngleLabelRadius = 0.95
        static let scientificThreshold = 1_000_000.0
        static let scientificDigits = 3
        static let maximumFractionDigits = 6
    }

    struct AngleGeometry {
        let start: Vec2
        let vertex: Vec2
        let end: Vec2
        let value: Double
        let bisector: Vec2
    }

    let objects: [UUID: SketchObject]
    let settings: CanvasSettings
    var cache: [UUID: EvalResult] = [:]
    var visiting: Set<UUID> = []

    init(objects: [SketchObject], settings: CanvasSettings) {
        self.objects = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        self.settings = settings
    }

    // MARK: - Evaluation

    mutating func evaluate(_ id: UUID) -> EvalResult {
        if let cached = cache[id] {
            return cached
        }
        guard let object = objects[id], !visiting.contains(id) else {
            return EvalResult()
        }
        visiting.insert(id)
        defer {
            visiting.remove(id)
        }

        var result = resolve(object)
        if let anchor = result.anchor {
            result.anchor = anchor + object.offset
        }
        cache[id] = result
        return result
    }

    mutating func resolve(_ object: SketchObject) -> EvalResult {
        var result = EvalResult()
        switch object.kind {
        case .freePoint:
            result.point = object.position ?? .zero

        case .pointOnPath(let parent, let param):
            if let path = path(parent) {
                if case .functionPlot(let expression) = path {
                    if var parser = Expression(expression) {
                        parser.setAngleUnit(settings.angleUnit)
                        if let y = parser.evaluate(x: param) {
                            result.point = Vec2(param, y)
                        }
                    }
                } else {
                    result.point = path.point(at: param)
                }
            }

        case .midpoint(let a, let b):
            if let pa = point(a), let pb = point(b) {
                result.point = pa.lerp(to: pb, 0.5)
            }

        case .intersection(let a, let b, let index):
            if let pa = path(a), let pb = path(b) {
                let hits = pa.intersections(with: pb)
                if index >= 0, index < hits.count {
                    result.point = hits[index]
                }
            }

        case .segment(let a, let b):
            if let pa = point(a), let pb = point(b) {
                result.path = .segment(pa, pb)
            }

        case .ray(let a, let b):
            if let pa = point(a), let pb = point(b) {
                result.path = .ray(pa, pb)
            }

        case .line(let a, let b):
            if let pa = point(a), let pb = point(b) {
                result.path = .line(pa, pb)
            }

        case .perpendicular(let lineID, let pointID):
            if let straight = path(lineID)?.straight, let p = point(pointID) {
                let direction = (straight.b - straight.a).perpendicular().normalized()
                result.path = .line(p, p + direction)
            }

        case .parallel(let lineID, let pointID):
            if let straight = path(lineID)?.straight, let p = point(pointID) {
                let direction = (straight.b - straight.a).normalized()
                result.path = .line(p, p + direction)
            }

        case .angleBisector(let a, let vertex, let c):
            if let pa = point(a), let pv = point(vertex), let pc = point(c) {
                let u = (pa - pv).normalized()
                let v = (pc - pv).normalized()
                var direction = (u + v).normalized()
                if direction.length < Metrics.epsilon {
                    direction = u.perpendicular()
                }
                result.path = .line(pv, pv + direction)
            }

        case .circle(let center, let through):
            if let pc = point(center), let pt = point(through) {
                result.path = .circle(pc, pc.distance(to: pt))
            }

        case .circleRadius(let center, let radius):
            if let pc = point(center) {
                result.path = .circle(pc, radius)
            }

        case .arcOnCircle(let circle, let startPoint, let endPoint):
            if let circlePath = path(circle),
               case .circle(let center, let radius) = circlePath,
               let ps = point(startPoint),
               let pe = point(endPoint) {
                let start = (ps - center).angle
                var sweep = (pe - center).angle - start
                while sweep <= Metrics.epsilon {
                    sweep += 2 * .pi
                }
                if sweep < 2 * .pi - Metrics.epsilon {
                    result.path = .arc(center: center, radius: radius, start: start, sweep: sweep)
                    result.fill = arcFillRegion(result.path, fill: object.arcFill)
                }
            }

        case .arcThroughPoints(let a, let b, let c):
            if let pa = point(a), let pb = point(b), let pc = point(c),
               let arc = arcThrough(pa, pb, pc) {
                result.path = arc
                result.fill = arcFillRegion(arc, fill: object.arcFill)
            }

        case .polygon(let vertices):
            let points = vertices.compactMap { point($0) }
            if points.count == vertices.count, points.count >= 2 {
                result.path = .polygon(points)
            }

        case .angle(let a, let vertex, let c):
            result = angleResult(a: a, vertex: vertex, c: c, label: object.label)

        case .measurement(let kind, let refs):
            result = measurement(kind: kind, refs: refs)

        case .calculation(let expression):
            result = calculationResult(expression)

        case .caption(let text):
            result.text = text
            result.anchor = object.position ?? .zero

        case .functionPlot(let expression):
            result.path = .functionPlot(expression)

        case .transformed(let source, let spec):
            let sourceResult = evaluate(source)
            if let sourcePoint = sourceResult.point,
               let mapped = transform(sourcePoint, by: spec) {
                result.point = mapped
            } else if let sourcePath = sourceResult.path,
                      let mapped = transform(sourcePath, by: spec) {
                result.path = mapped
            }

        case .locus(let driver, let target):
            if let curve = locusCurve(driver: driver, target: target) {
                result.path = .polyline(curve)
            }

        case .parameter(let value, _, _):
            result.value = value
            let name = object.label.isEmpty ? "x" : object.label
            result.text = "\(name) = \(formatNumber(value, precision: settings.precision))"
            result.anchor = object.position ?? .zero

        case .construction(let kind):
            result = constructionResult(kind)

        case .vector(let kind):
            result = vectorResult(kind)

        case .coordinateSystem:
            if case .coordinateSystem(_, let origin, _, _) = object.kind {
                result.anchor = point(origin)
            }

        case .graph(let feature):
            result = graphResult(feature, object: object)
        }
        return result
    }















    mutating func point(_ id: UUID) -> Vec2? {
        evaluate(id).point
    }

    mutating func path(_ id: UUID) -> EvalPath? {
        evaluate(id).path
    }

    // MARK: - Measurements








    // MARK: - Transforms





    // MARK: - Formatting







}
