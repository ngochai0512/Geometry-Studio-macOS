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
}

struct GeometryEval {
    /// Tolerances, sampling counts, label radii and number formatting shared
    /// by the evaluator; none of them are user-facing units, so they live here
    /// rather than in `SketchMetrics`.
    private enum Metrics {
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

    private struct AngleGeometry {
        let start: Vec2
        let vertex: Vec2
        let end: Vec2
        let value: Double
        let bisector: Vec2
    }

    let objects: [UUID: SketchObject]
    let settings: CanvasSettings
    private var cache: [UUID: EvalResult] = [:]
    private var visiting: Set<UUID> = []

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

    private mutating func resolve(_ object: SketchObject) -> EvalResult {
        var result = EvalResult()
        switch object.kind {
        case .freePoint:
            result.point = object.position ?? .zero

        case .pointOnPath(let parent, let param):
            if let path = path(parent) {
                result.point = path.point(at: param)
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
        }
        return result
    }

    private mutating func angleResult(
        a: UUID,
        vertex: UUID,
        c: UUID,
        label: String
    ) -> EvalResult {
        var result = EvalResult()
        guard let angle = angleGeometry(a: a, vertex: vertex, c: c) else {
            return result
        }
        let text = formatAngle(angle.value)
        result.value = angle.value
        result.angleValue = angle.value
        result.anglePoints = (angle.start, angle.vertex, angle.end)
        result.anchor = angle.vertex + angle.bisector * Metrics.angleLabelRadius
        result.text = label.isEmpty ? text : "\(label) = \(text)"
        return result
    }

    private mutating func angleGeometry(a: UUID, vertex: UUID, c: UUID) -> AngleGeometry? {
        guard let pa = point(a), let pv = point(vertex), let pc = point(c) else {
            return nil
        }
        let u = (pa - pv).normalized()
        let v = (pc - pv).normalized()
        let unsigned = acos(min(max(u.dot(v), -1), 1))
        // Plain degrees are undirected (0–180°); directed degrees and
        // radians keep the sign, as in the original's preferences.
        let value = settings.angleUnit == .degrees ? unsigned : atan2(u.cross(v), u.dot(v))
        var bisector = (u + v).normalized()
        if bisector.length < Metrics.epsilon {
            bisector = u.perpendicular()
        }
        return AngleGeometry(start: pa, vertex: pv, end: pc, value: value, bisector: bisector)
    }

    private mutating func calculationResult(_ expression: String) -> EvalResult {
        var result = EvalResult()
        var parser = Expression(expression)
        parser?.setAngleUnit(settings.angleUnit)
        let variables = calculationVariables()
        guard var parsed = parser, let value = parsed.evaluate(variables: variables) else {
            result.text = "\(expression) = undefined"
            return result
        }
        result.text = "\(expression) = \(formatNumber(value, precision: settings.precision))"
        result.value = value
        result.anchor = objects.values.first(where: { object in
            if case .measurement = object.kind {
                return true
            }
            return false
        })?.position ?? .zero
        return result
    }

    /// Circumcircle through three points, with the sweep chosen so the arc
    /// runs from `a` to `c` through `b`.
    private func arcThrough(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> EvalPath? {
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
    private func arcFillRegion(_ path: EvalPath?, fill: ArcFill) -> EvalPath? {
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

    private func positiveAngle(_ angle: Double) -> Double {
        let twoPi = 2 * Double.pi
        var value = angle.truncatingRemainder(dividingBy: twoPi)
        if value < 0 {
            value += twoPi
        }
        return value
    }

    /// Samples a driven object while its driver sweeps the driver's whole
    /// path. reference application calls this a locus; a point on an open path uses the
    /// path parameter from 0 to 1, a point on a circle a full counter-clockwise
    /// turn, matching the original's animation direction rule.
    private mutating func locusCurve(driver: UUID, target: UUID) -> [Vec2]? {
        guard let driverObject = objects[driver],
              case .pointOnPath(let pathID, _) = driverObject.kind,
              let driverPath = path(pathID),
              let targetObject = objects[target] else {
            return nil
        }
        if case .locus = targetObject.kind {
            return nil
        }
        let closed: Bool
        if case .circle = driverPath {
            closed = true
        } else {
            closed = false
        }
        var base = Array(objects.values)
        guard let index = base.firstIndex(where: { $0.id == driver }) else {
            return nil
        }
        var points: [Vec2] = []
        for step in 0...Metrics.locusSamples {
            let unit = Double(step) / Double(Metrics.locusSamples)
            let param = closed ? unit * 2 * .pi : unit
            base[index].kind = .pointOnPath(path: pathID, param: param)
            var sample = GeometryEval(objects: base, settings: settings)
            guard let p = sample.evaluate(target).point else {
                continue
            }
            let last = points.last?.distance(to: p) ?? .infinity
            if last > Metrics.locusDedupTolerance {
                points.append(p)
            }
        }
        return points.count > 1 ? points : nil
    }

    mutating func point(_ id: UUID) -> Vec2? {
        evaluate(id).point
    }

    mutating func path(_ id: UUID) -> EvalPath? {
        evaluate(id).path
    }

    // MARK: - Measurements

    private mutating func measurement(kind: MeasureKind, refs: [UUID]) -> EvalResult {
        var result = EvalResult()
        let precision = settings.precision
        let perUnit = settings.lengthUnit.perUnit
        func labels(_ ids: [UUID]) -> String {
            ids.map { name(of: $0) }.joined()
        }
        switch kind {
        case .distance:
            if refs.count >= 2, let a = point(refs[0]), let b = point(refs[1]) {
                let value = a.distance(to: b)
                result.value = value
                result.text = "m \(labels(Array(refs.prefix(2)))) = \(formatLength(value))"
                result.anchor = a.lerp(to: b, 0.5) + Vec2(0, 0.28)
            }
        case .length:
            if let first = refs.first,
               let evaluated = path(first),
               let value = evaluated.length(settings: settings) {
                result.value = value
                result.text = "m \(name(of: first)) = \(formatLength(value))"
                result.anchor = (evaluated.boundingBox?.center ?? .zero) + Vec2(0, 0.28)
            }
        case .perimeter:
            if let first = refs.first,
               let evaluated = path(first),
               case .polygon(let points) = evaluated {
                let value = polygonLength(points)
                result.value = value
                result.text = "Perimeter \(name(of: first)) = \(formatLength(value))"
                result.anchor = (evaluated.boundingBox?.center ?? .zero) + Vec2(0, 0.3)
            }
        case .circumference:
            if let first = refs.first,
               let evaluated = path(first),
               case .circle(let center, let radius) = evaluated {
                let value = 2 * Double.pi * radius
                result.value = value
                result.text = "Circumference \(name(of: first)) = \(formatLength(value))"
                result.anchor = center + Vec2(0, radius + 0.3)
            }
        case .angle:
            if refs.count >= 3, let angle = angleGeometry(a: refs[0], vertex: refs[1], c: refs[2]) {
                result.value = angle.value
                result.anglePoints = (angle.start, angle.vertex, angle.end)
                result.angleValue = angle.value
                result.text = "m∠\(labels(Array(refs.prefix(3)))) = \(formatAngle(angle.value))"
                result.anchor = angle.vertex + angle.bisector * Metrics.measuredAngleLabelRadius
            }
        case .arcAngle:
            if let first = refs.first,
               let evaluated = path(first),
               case .arc(_, _, _, let sweep) = evaluated {
                let angle = settings.angleUnit == .degrees ? abs(sweep) : sweep
                result.value = angle
                result.text = "m \(name(of: first)) = \(formatAngle(angle))"
                result.anchor = arcLabelAnchor(evaluated)
            }
        case .arcLength:
            if let first = refs.first,
               let evaluated = path(first),
               case .arc(_, let radius, _, let sweep) = evaluated {
                let length = radius * abs(sweep)
                result.value = length
                result.text = "\(name(of: first)) length = \(formatLength(length))"
                result.anchor = arcLabelAnchor(evaluated)
            }
        case .area:
            if let first = refs.first, let evaluated = path(first) {
                var area: Double?
                if case .polygon(let points) = evaluated, points.count >= 3 {
                    area = polygonArea(points)
                } else if case .circle(_, let radius) = evaluated {
                    area = Double.pi * radius * radius
                }
                if let area {
                    result.value = area
                    result.text = "Area \(name(of: first)) = \(formatArea(area))"
                    result.anchor = (evaluated.boundingBox?.center ?? .zero) + Vec2(0, -0.3)
                }
            }
        case .radius:
            if let first = refs.first,
               let evaluated = path(first),
               case .circle(let center, let radius) = evaluated {
                result.value = radius
                result.text = "r \(name(of: first)) = \(formatLength(radius))"
                result.anchor = center + Vec2(radius * 0.55, 0.3)
            }
        case .ratio:
            if refs.count >= 2,
               let firstPath = path(refs[0]),
               let secondPath = path(refs[1]),
               let firstLength = firstPath.length(settings: settings),
               let secondLength = secondPath.length(settings: settings),
               secondLength > Metrics.degenerate {
                let value = firstLength / secondLength
                let label = "\(name(of: refs[0]))/\(name(of: refs[1]))"
                result.value = value
                result.text = "\(label) = \(formatNumber(value, precision: precision))"
                result.anchor = (firstPath.boundingBox?.center ?? .zero) + Vec2(0, 0.3)
            }
        case .coordinates:
            if let first = refs.first, let p = point(first) {
                let name = name(of: first)
                let x = formatNumber(p.x / perUnit, precision: precision)
                let y = formatNumber(p.y / perUnit, precision: precision)
                result.value = p.x
                result.text = "\(name) = (\(x), \(y)) \(settings.lengthUnit.short)"
                result.anchor = p + Vec2(0.55, 0.5)
            }
        case .abscissa:
            if let first = refs.first, let p = point(first) {
                result.value = p.x
                result.text = "x \(name(of: first)) = \(formatLength(p.x))"
                result.anchor = p + Vec2(0.55, 0.35)
            }
        case .ordinate:
            if let first = refs.first, let p = point(first) {
                result.value = p.y
                result.text = "y \(name(of: first)) = \(formatLength(p.y))"
                result.anchor = p + Vec2(0.55, 0.1)
            }
        case .polarDistance:
            if let first = refs.first, let p = point(first) {
                let distance = p.length
                result.value = distance
                result.text = "r \(name(of: first)) = \(formatLength(distance))"
                result.anchor = p + Vec2(0.55, -0.15)
            }
        case .polarDirection:
            if let first = refs.first, let p = point(first) {
                var direction = atan2(p.y, p.x)
                if settings.angleUnit == .degrees, direction < 0 {
                    direction += 2 * .pi
                }
                result.value = direction
                result.text = "θ \(name(of: first)) = \(formatAngle(direction))"
                result.anchor = p + Vec2(0.55, -0.4)
            }
        case .equation:
            if let first = refs.first, let evaluated = path(first) {
                result.text = equationText(for: evaluated, name: name(of: first))
                result.anchor = (evaluated.boundingBox?.center ?? .zero) + Vec2(0, 0.3)
            }
        case .slope:
            if let first = refs.first, let evaluated = path(first), let straight = evaluated.straight {
                let delta = straight.b - straight.a
                if abs(delta.x) < Metrics.epsilon {
                    result.text = "Slope \(name(of: first)) = undefined"
                } else {
                    let slope = delta.y / delta.x
                    result.value = slope
                    let text = formatNumber(slope, precision: precision)
                    result.text = "Slope \(name(of: first)) = \(text)"
                }
                result.anchor = (evaluated.boundingBox?.center ?? .zero) + Vec2(0, 0.28)
            }
        }
        return result
    }

    private func arcLabelAnchor(_ path: EvalPath) -> Vec2? {
        guard case .arc(let center, let radius, let start, let sweep) = path else {
            return nil
        }
        let angle = start + sweep / 2
        return center + Vec2(cos(angle), sin(angle)) * (radius + 0.3)
    }

    func name(of id: UUID) -> String {
        guard let object = objects[id] else {
            return "?"
        }
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return object.label.isEmpty ? "P" : object.label
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            return label(of: a) + label(of: b)
        case .circle(let center, _), .circleRadius(let center, _):
            return object.label.isEmpty ? "circle \(label(of: center))" : object.label
        case .arcOnCircle(_, let start, let end):
            return arcName(object, labels: joinedLabels([start, end]))
        case .arcThroughPoints(let a, let b, let c):
            return arcName(object, labels: joinedLabels([a, b, c]))
        case .polygon(let vertices):
            return joinedLabels(vertices)
        default:
            return object.label
        }
    }

    private func label(of id: UUID) -> String {
        objects[id]?.label ?? ""
    }

    private func joinedLabels(_ ids: [UUID]) -> String {
        ids.compactMap { objects[$0]?.label }.filter { !$0.isEmpty }.joined()
    }

    private func arcName(_ object: SketchObject, labels: String) -> String {
        if !object.label.isEmpty {
            return object.label
        }
        return labels.isEmpty ? "arc" : "arc \(labels)"
    }

    private mutating func calculationVariables() -> [String: Double] {
        var variables: [String: Double] = [:]
        for object in objects.values {
            if case .measurement(let kind, let refs) = object.kind {
                let result = measurement(kind: kind, refs: refs)
                if let value = result.value, !object.label.isEmpty {
                    variables[object.label.replacingOccurrences(of: " ", with: "_")] = value
                }
            }
        }
        return variables
    }

    // MARK: - Transforms

    private mutating func transform(_ point: Vec2, by spec: TransformSpec) -> Vec2? {
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

    /// The signed angle from the first side to the second side, in degrees.
    /// A missing mark falls back to the transform's snapshot.
    private mutating func liveAngleDegrees(for spec: TransformSpec) -> Double? {
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
    private mutating func liveRatio(for spec: TransformSpec) -> Double? {
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

    private mutating func transform(_ shape: EvalPath, by spec: TransformSpec) -> EvalPath? {
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

    // MARK: - Formatting

    private func equationText(for path: EvalPath, name: String) -> String? {
        if let straight = path.straight {
            return lineEquationText(straight, name: name)
        }
        if case .circle(let center, let radius) = path {
            return circleEquationText(center: center, radius: radius, name: name)
        }
        return nil
    }

    private func lineEquationText(
        _ straight: (a: Vec2, b: Vec2, kind: Int),
        name: String
    ) -> String {
        let precision = settings.precision
        let delta = straight.b - straight.a
        if abs(delta.x) < Metrics.epsilon {
            let x = formatNumber(straight.a.x / settings.lengthUnit.perUnit, precision: precision)
            return "\(name): x = \(x)"
        }
        let slope = delta.y / delta.x
        let intercept = straight.a.y - slope * straight.a.x
        let sign = intercept >= 0 ? "+" : "−"
        let slopeText = formatNumber(slope, precision: precision)
        let interceptText = formatNumber(abs(intercept), precision: precision)
        return "\(name): y = \(slopeText)x \(sign) \(interceptText)"
    }

    private func circleEquationText(center: Vec2, radius: Double, name: String) -> String {
        let precision = settings.precision
        let perUnit = settings.lengthUnit.perUnit
        let x = center.x / perUnit
        let y = center.y / perUnit
        let r = radius / perUnit
        let xSign = x >= 0 ? "−" : "+"
        let ySign = y >= 0 ? "−" : "+"
        let xText = formatNumber(abs(x), precision: precision)
        let yText = formatNumber(abs(y), precision: precision)
        let radiusSquared = formatNumber(r * r, precision: precision)
        return "\(name): (x \(xSign) \(xText))² + (y \(ySign) \(yText))² = \(radiusSquared)"
    }

    func formatNumber(_ value: Double, precision: Int) -> String {
        if !value.isFinite {
            return "undefined"
        }
        if abs(value) >= Metrics.scientificThreshold {
            return String(format: "%.\(Metrics.scientificDigits)g", value)
        }
        let digits = max(0, min(precision, Metrics.maximumFractionDigits))
        return String(format: "%.\(digits)f", value)
    }

    func formatLength(_ cm: Double) -> String {
        let value = cm / settings.lengthUnit.perUnit
        return "\(formatNumber(value, precision: settings.precision)) \(settings.lengthUnit.short)"
    }

    func formatArea(_ cm2: Double) -> String {
        let perUnit = settings.lengthUnit.perUnit
        let value = cm2 / (perUnit * perUnit)
        return "\(formatNumber(value, precision: settings.precision)) \(settings.lengthUnit.short)²"
    }

    func formatAngle(_ radians: Double) -> String {
        if settings.angleUnit != .radians {
            return "\(formatNumber(radians * 180 / .pi, precision: settings.precision))°"
        }
        return "\(formatNumber(radians, precision: settings.precision)) rad"
    }
}
