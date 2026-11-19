import Foundation

struct EvalResult {
    var point: Vec2?
    var path: EvalPath?
    var text: String?
    var anchor: Vec2?
    var value: Double?
    var anglePoints: (Vec2, Vec2, Vec2)?
    var angleValue: Double?
}

struct GeometryEval {
    let objects: [UUID: SketchObject]
    let settings: CanvasSettings
    private var cache: [UUID: EvalResult] = [:]
    private var visiting: Set<UUID> = []

    init(objects: [SketchObject], settings: CanvasSettings) {
        self.objects = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        self.settings = settings
    }

    mutating func evaluate(_ id: UUID) -> EvalResult {
        if let cached = cache[id] {
            return cached
        }
        guard let object = objects[id] else {
            return EvalResult()
        }
        if visiting.contains(id) {
            return EvalResult()
        }
        visiting.insert(id)
        defer {
            visiting.remove(id)
        }

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
                if index >= 0 && index < hits.count {
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
            if let s = path(lineID)?.straight, let p = point(pointID) {
                let direction = (s.b - s.a).perpendicular().normalized()
                result.path = .line(p, p + direction)
            }

        case .parallel(let lineID, let pointID):
            if let s = path(lineID)?.straight, let p = point(pointID) {
                let direction = (s.b - s.a).normalized()
                result.path = .line(p, p + direction)
            }

        case .angleBisector(let a, let vertex, let c):
            if let pa = point(a), let pv = point(vertex), let pc = point(c) {
                let u = (pa - pv).normalized()
                let v = (pc - pv).normalized()
                var d = (u + v).normalized()
                if d.length < 1e-9 {
                    d = u.perpendicular()
                }
                result.path = .line(pv, pv + d)
            }

        case .circle(let center, let through):
            if let pc = point(center), let pt = point(through) {
                result.path = .circle(pc, pc.distance(to: pt))
            }

        case .arcOnCircle(let circle, let startPoint, let endPoint):
            if let circlePath = path(circle),
               case .circle(let center, let radius) = circlePath,
               let ps = point(startPoint),
               let pe = point(endPoint) {
                let start = (ps - center).angle
                var sweep = (pe - center).angle - start
                while sweep <= 1e-9 {
                    sweep += 2 * .pi
                }
                if sweep < 2 * .pi - 1e-9 {
                    result.path = .arc(center: center, radius: radius, start: start, sweep: sweep)
                }
            }

        case .arcThroughPoints(let a, let b, let c):
            if let pa = point(a), let pb = point(b), let pc = point(c),
               let arc = arcThrough(pa, pb, pc) {
                result.path = .arc(center: arc.center, radius: arc.radius,
                                   start: arc.start, sweep: arc.sweep)
            }

        case .polygon(let vertices):
            let pts = vertices.compactMap { point($0) }
            if pts.count == vertices.count, pts.count >= 2 {
                result.path = .polygon(pts)
            }

        case .angle(let a, let vertex, let c):
            if let pa = point(a), let pv = point(vertex), let pc = point(c) {
                let u = (pa - pv).normalized()
                let v = (pc - pv).normalized()
                let unsigned = acos(min(max(u.dot(v), -1), 1))
                // Plain degrees are undirected (0–180°); directed degrees and
                // radians keep the sign, as in the original's preferences.
                let raw = settings.angleUnit == .degrees ? unsigned : atan2(u.cross(v), u.dot(v))
                var bis = (u + v).normalized()
                if bis.length < 1e-9 {
                    bis = u.perpendicular()
                }
                result.value = raw
                result.angleValue = raw
                result.anglePoints = (pa, pv, pc)
                result.anchor = pv + bis * 0.72
                let angleText = formatAngle(raw)
                result.text = object.label.isEmpty ? angleText : "\(object.label) = \(angleText)"
            }

        case .measurement(let kind, let refs):
            result = measurement(kind: kind, refs: refs)

        case .calculation(let expression):
            var parser = Expression(expression)
            parser?.setAngleUnit(settings.angleUnit)
            let vars = calculationVariables()
            if var p = parser, let value = p.evaluate(variables: vars) {
                let text = "\(expression) = \(formatNumber(value, precision: settings.precision))"
                result.text = text
                result.value = value
                result.anchor = objects.values.first(where: {
                    if case .measurement = $0.kind {
                        return true
                    }
                    return false
                })?.position ?? Vec2(0, 0)
            } else {
                result.text = "\(expression) = undefined"
            }

        case .caption(let text):
            result.text = text
            result.anchor = object.position ?? .zero

        case .functionPlot(let expression):
            result.path = .functionPlot(expression)

        case .transformed(let source, let spec):
            if let src = objects[source] {
                let sourceResult = evaluate(source)
                if let p = sourceResult.point, let mapped = map(p, spec) {
                    result.point = mapped
                } else if let p = sourceResult.path, let mapped = map(p, spec) {
                    result.path = mapped
                }
                _ = src
            }

        case .locus(let driver, let target):
            if let curve = locusCurve(driver: driver, target: target) {
                result.path = .polyline(curve)
            }
        }

        if result.anchor != nil {
            result.anchor = result.anchor! + object.offset
        }
        cache[id] = result
        return result
    }

    /// Circumcircle through three points, with the sweep chosen so the arc
    /// runs from `a` to `c` through `b`.
    private func arcThrough(_ a: Vec2, _ b: Vec2, _ c: Vec2)
        -> (center: Vec2, radius: Double, start: Double, sweep: Double)? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-12 else {
            return nil
        }
        let aa = a.dot(a)
        let bb = b.dot(b)
        let cc = c.dot(c)
        let ux = (aa * (b.y - c.y) + bb * (c.y - a.y) + cc * (a.y - b.y)) / d
        let uy = (aa * (c.x - b.x) + bb * (a.x - c.x) + cc * (b.x - a.x)) / d
        let center = Vec2(ux, uy)
        let radius = center.distance(to: a)
        guard radius > 1e-9 else {
            return nil
        }
        let start = (a - center).angle
        let end = (c - center).angle
        let through = (b - center).angle
        let ccwSweep = positiveAngle(end - start)
        guard ccwSweep > 1e-9 else {
            return nil
        }
        let throughOffset = positiveAngle(through - start)
        let sweep = throughOffset <= ccwSweep + 1e-9 ? ccwSweep : ccwSweep - 2 * .pi
        return (center, radius, start, sweep)
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
              objects[target] != nil else {
            return nil
        }
        if case .locus = objects[target]?.kind {
            return nil
        }
        let closed: Bool
        if case .circle = driverPath {
            closed = true
        } else {
            closed = false
        }
        let steps = 96
        var base = Array(objects.values)
        guard let i = base.firstIndex(where: { $0.id == driver }) else {
            return nil
        }
        var points: [Vec2] = []
        for step in 0...steps {
            let unit = Double(step) / Double(steps)
            let param = closed ? unit * 2 * .pi : unit
            base[i].kind = .pointOnPath(path: pathID, param: param)
            var sample = GeometryEval(objects: base, settings: settings)
            if let p = sample.evaluate(target).point,
               points.last?.distance(to: p) ?? 1 > 1e-6 {
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

    // MARK: measurement

    private mutating func measurement(kind: MeasureKind, refs: [UUID]) -> EvalResult {
        var result = EvalResult()
        func labels(_ ids: [UUID]) -> String {
            ids.map { name(of: $0) }.joined()
        }
        switch kind {
        case .distance:
            if refs.count >= 2, let a = point(refs[0]), let b = point(refs[1]) {
                let v = a.distance(to: b)
                result.value = v
                result.text = "m \(labels(Array(refs.prefix(2)))) = \(formatLength(v))"
                result.anchor = a.lerp(to: b, 0.5) + Vec2(0, 0.28)
            }
        case .length:
            if let first = refs.first, let p = path(first), let v = p.length(settings: settings) {
                result.value = v
                result.text = "m \(name(of: first)) = \(formatLength(v))"
                result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, 0.28)
            }
        case .perimeter:
            if let first = refs.first, let p = path(first), case .polygon(let pts) = p {
                let v = polygonLength(pts)
                result.value = v
                result.text = "Perimeter \(name(of: first)) = \(formatLength(v))"
                result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, 0.3)
            }
        case .circumference:
            if let first = refs.first, let p = path(first), case .circle(let c, let r) = p {
                let v = 2 * Double.pi * r
                result.value = v
                result.text = "Circumference \(name(of: first)) = \(formatLength(v))"
                result.anchor = c + Vec2(0, r + 0.3)
            }
        case .angle:
            if refs.count >= 3,
               let a = point(refs[0]),
               let v = point(refs[1]),
               let c = point(refs[2]) {
                let u = (a - v).normalized()
                let w = (c - v).normalized()
                let unsigned = acos(min(max(u.dot(w), -1), 1))
                let angle = settings.angleUnit == .degrees ? unsigned : atan2(u.cross(w), u.dot(w))
                result.value = angle
                result.anglePoints = (a, v, c)
                result.angleValue = angle
                var bis = (u + w).normalized()
                if bis.length < 1e-9 {
                    bis = u.perpendicular()
                }
                result.text = "m∠\(labels(Array(refs.prefix(3)))) = \(formatAngle(angle))"
                result.anchor = v + bis * 0.95
            }
        case .arcAngle:
            if let first = refs.first, let p = path(first), case .arc(_, _, _, let sweep) = p {
                let angle = settings.angleUnit == .degrees ? abs(sweep) : sweep
                result.value = angle
                result.text = "m \(name(of: first)) = \(formatAngle(angle))"
                result.anchor = arcLabelAnchor(p)
            }
        case .arcLength:
            if let first = refs.first, let p = path(first), case .arc(_, let radius, _, let sweep) = p {
                let length = radius * abs(sweep)
                result.value = length
                result.text = "\(name(of: first)) length = \(formatLength(length))"
                result.anchor = arcLabelAnchor(p)
            }
        case .area:
            if let first = refs.first, let p = path(first) {
                if case .polygon(let pts) = p, pts.count >= 3 {
                    let v = polygonArea(pts)
                    result.value = v
                    result.text = "Area \(name(of: first)) = \(formatArea(v))"
                    result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, -0.3)
                } else if case .circle(_, let r) = p {
                    let v = Double.pi * r * r
                    result.value = v
                    result.text = "Area \(name(of: first)) = \(formatArea(v))"
                    result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, -0.3)
                }
            }
        case .radius:
            if let first = refs.first, let p = path(first), case .circle(let c, let r) = p {
                result.value = r
                result.text = "r \(name(of: first)) = \(formatLength(r))"
                result.anchor = c + Vec2(r * 0.55, 0.3)
            }
        case .ratio:
            if refs.count >= 2,
               let p1 = path(refs[0]),
               let p2 = path(refs[1]),
               let l1 = p1.length(settings: settings),
               let l2 = p2.length(settings: settings),
               l2 > 1e-12 {
                let v = l1 / l2
                result.value = v
                result.text = "\(name(of: refs[0]))/\(name(of: refs[1])) = \(formatNumber(v, precision: settings.precision))"
                result.anchor = (p1.boundingBox?.center ?? .zero) + Vec2(0, 0.3)
            }
        case .coordinates:
            if let first = refs.first, let p = point(first) {
                let name = name(of: first)
                let x = p.x / settings.lengthUnit.perUnit
                let y = p.y / settings.lengthUnit.perUnit
                result.value = p.x
                result.text = "\(name) = (\(formatNumber(x, precision: settings.precision)), \(formatNumber(y, precision: settings.precision))) \(settings.lengthUnit.short)"
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
            if let first = refs.first, let p = path(first) {
                let prefix = name(of: first)
                if let s = p.straight {
                    let d = s.b - s.a
                    if abs(d.x) < 1e-9 {
                        result.text = "\(prefix): x = \(formatNumber(s.a.x / settings.lengthUnit.perUnit, precision: settings.precision))"
                    } else {
                        let m = d.y / d.x
                        let b = s.a.y - m * s.a.x
                        result.text = "\(prefix): y = \(formatNumber(m, precision: settings.precision))x \(b >= 0 ? "+" : "−") \(formatNumber(abs(b), precision: settings.precision))"
                    }
                } else if case .circle(let c, let r) = p {
                    let x = c.x / settings.lengthUnit.perUnit
                    let y = c.y / settings.lengthUnit.perUnit
                    let rr = r / settings.lengthUnit.perUnit
                    result.text = "\(prefix): (x \(x >= 0 ? "−" : "+") \(formatNumber(abs(x), precision: settings.precision)))² + (y \(y >= 0 ? "−" : "+") \(formatNumber(abs(y), precision: settings.precision)))² = \(formatNumber(rr * rr, precision: settings.precision))"
                }
                result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, 0.3)
            }
        case .slope:
            if let first = refs.first, let p = path(first), let s = p.straight {
                let d = s.b - s.a
                if abs(d.x) < 1e-9 {
                    result.text = "Slope \(name(of: first)) = undefined"
                } else {
                    let m = d.y / d.x
                    result.value = m
                    result.text = "Slope \(name(of: first)) = \(formatNumber(m, precision: settings.precision))"
                }
                result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, 0.28)
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
            return (objects[a]?.label ?? "") + (objects[b]?.label ?? "")
        case .circle(let c, _):
            return object.label.isEmpty ? "circle \((objects[c]?.label ?? ""))" : object.label
        case .arcOnCircle(_, let start, let end):
            let labels = [start, end].compactMap { objects[$0]?.label }.filter { !$0.isEmpty }.joined()
            return object.label.isEmpty ? (labels.isEmpty ? "arc" : "arc \(labels)") : object.label
        case .arcThroughPoints(let a, let b, let c):
            let labels = [a, b, c].compactMap { objects[$0]?.label }.filter { !$0.isEmpty }.joined()
            return object.label.isEmpty ? (labels.isEmpty ? "arc" : "arc \(labels)") : object.label
        case .polygon(let vertices):
            return vertices.compactMap { objects[$0]?.label }.joined()
        default:
            return object.label
        }
    }

    private mutating func calculationVariables() -> [String: Double] {
        var out: [String: Double] = [:]
        for object in objects.values {
            if case .measurement(let kind, let refs) = object.kind {
                let r = measurement(kind: kind, refs: refs)
                if let v = r.value, !object.label.isEmpty {
                    out[object.label.replacingOccurrences(of: " ", with: "_")] = v
                }
            }
        }
        return out
    }

    // MARK: transform

    private mutating func map(_ p: Vec2, _ spec: TransformSpec) -> Vec2? {
        switch spec.kind {
        case .reflect:
            guard let ref = spec.reference, let s = path(ref)?.straight else {
                return nil
            }
            let a = s.a
            let d = (s.b - s.a).normalized()
            let t = (p - a).dot(d)
            let foot = a + d * t
            return foot * 2 - p
        case .rotate:
            guard let ref = spec.reference, let c = point(ref) else {
                return nil
            }
            return c + (p - c).rotated(by: spec.angle * .pi / 180)
        case .translate:
            if let a = spec.reference,
               let b = spec.secondReference,
               let pa = point(a),
               let pb = point(b) {
                return p + (pb - pa)
            }
            return p + Vec2(spec.dx, spec.dy)
        case .dilate:
            guard let ref = spec.reference, let c = point(ref) else {
                return nil
            }
            return c + (p - c) * spec.factor
        }
    }

    private mutating func map(_ path: EvalPath, _ spec: TransformSpec) -> EvalPath? {
        switch path {
        case .segment(let a, let b):
            guard let ma = map(a, spec), let mb = map(b, spec) else {
                return nil
            }
            return .segment(ma, mb)
        case .ray(let a, let b):
            guard let ma = map(a, spec), let mb = map(b, spec) else {
                return nil
            }
            return .ray(ma, mb)
        case .line(let a, let b):
            guard let ma = map(a, spec), let mb = map(b, spec) else {
                return nil
            }
            return .line(ma, mb)
        case .circle(let c, let r):
            guard let mc = map(c, spec), let edge = map(c + Vec2(r, 0), spec) else {
                return nil
            }
            return .circle(mc, mc.distance(to: edge))
        case .arc(let center, let radius, let start, let sweep):
            let startPoint = center + Vec2(cos(start), sin(start)) * radius
            let midAngle = start + sweep / 2
            let midPoint = center + Vec2(cos(midAngle), sin(midAngle)) * radius
            guard let mc = map(center, spec),
                  let ms = map(startPoint, spec),
                  let mm = map(midPoint, spec) else {
                return nil
            }
            let newRadius = mc.distance(to: ms)
            guard newRadius > 1e-9 else {
                return nil
            }
            let newStart = (ms - mc).angle
            var delta = positiveAngle((mm - mc).angle - newStart)
            if delta > .pi {
                delta -= 2 * .pi
            }
            return .arc(center: mc, radius: newRadius, start: newStart, sweep: delta * 2)
        case .polygon(let pts):
            let mapped = pts.compactMap { map($0, spec) }
            return mapped.count == pts.count ? .polygon(mapped) : nil
        case .polyline(let pts):
            let mapped = pts.compactMap { map($0, spec) }
            return mapped.count == pts.count ? .polyline(mapped) : nil
        case .functionPlot:
            return nil
        }
    }

    // MARK: formatting

    func formatNumber(_ value: Double, precision: Int) -> String {
        if !value.isFinite {
            return "undefined"
        }
        if abs(value) >= 1_000_000 {
            return String(format: "%.3g", value)
        }
        return String(format: "%.\(max(0, min(precision, 6)))f", value)
    }

    func formatLength(_ cm: Double) -> String {
        let v = cm / settings.lengthUnit.perUnit
        return "\(formatNumber(v, precision: settings.precision)) \(settings.lengthUnit.short)"
    }

    func formatArea(_ cm2: Double) -> String {
        let v = cm2 / (settings.lengthUnit.perUnit * settings.lengthUnit.perUnit)
        return "\(formatNumber(v, precision: settings.precision)) \(settings.lengthUnit.short)²"
    }

    func formatAngle(_ radians: Double) -> String {
        if settings.angleUnit != .radians {
            return "\(formatNumber(radians * 180 / .pi, precision: settings.precision))°"
        }
        return "\(formatNumber(radians, precision: settings.precision)) rad"
    }
}

// MARK: - Tools
