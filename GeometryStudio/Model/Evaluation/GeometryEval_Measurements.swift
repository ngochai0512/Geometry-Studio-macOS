import Foundation

extension GeometryEval {

    mutating func measurement(kind: MeasureKind, refs: [UUID]) -> EvalResult {
        var result = EvalResult()
        let precision = settings.precision
        var frameOrigin = Vec2.zero
        var frameUnit = settings.lengthUnit
        if refs.count >= 2,
           let object = objects[refs[1]],
           case .coordinateSystem(_, let originID, _, let unit) = object.kind,
           let origin = point(originID) {
            frameOrigin = origin
            frameUnit = unit
        }
        let framePerUnit = max(frameUnit.perUnit, 1e-6)
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
                let local = p - frameOrigin
                let x = formatNumber(local.x / framePerUnit, precision: precision)
                let y = formatNumber(local.y / framePerUnit, precision: precision)
                result.value = local.x
                result.text = "\(name) = (\(x), \(y)) \(frameUnit.short)"
                result.anchor = p + Vec2(0.55, 0.5)
            }
        case .abscissa:
            if let first = refs.first, let p = point(first) {
                let local = p.x - frameOrigin.x
                result.value = local
                result.text = "x \(name(of: first)) = \(formatNumber(local / framePerUnit, precision: precision)) \(frameUnit.short)"
                result.anchor = p + Vec2(0.55, 0.35)
            }
        case .ordinate:
            if let first = refs.first, let p = point(first) {
                let local = p.y - frameOrigin.y
                result.value = local
                result.text = "y \(name(of: first)) = \(formatNumber(local / framePerUnit, precision: precision)) \(frameUnit.short)"
                result.anchor = p + Vec2(0.55, 0.1)
            }
        case .polarDistance:
            if let first = refs.first, let p = point(first) {
                let distance = (p - frameOrigin).length
                result.value = distance
                result.text = "r \(name(of: first)) = \(formatNumber(distance / framePerUnit, precision: precision)) \(frameUnit.short)"
                result.anchor = p + Vec2(0.55, -0.15)
            }
        case .polarDirection:
            if let first = refs.first, let p = point(first) {
                var direction = atan2(p.y - frameOrigin.y, p.x - frameOrigin.x)
                if settings.angleUnit == .degrees, direction < 0 {
                    direction += 2 * .pi
                }
                result.value = direction
                result.text = "θ \(name(of: first)) = \(formatAngle(direction))"
                result.anchor = p + Vec2(0.55, -0.4)
            }
        case .coordinateDistance:
            if refs.count >= 2, let a = point(refs[0]), let b = point(refs[1]) {
                var first = a
                var second = b
                var unit = settings.lengthUnit
                if refs.count >= 3,
                   let object = objects[refs[2]],
                   case .coordinateSystem(_, let originID, _, let systemUnit) = object.kind,
                   let origin = point(originID) {
                    first = a - origin
                    second = b - origin
                    unit = systemUnit
                }
                let dx = second.x - first.x
                let dy = second.y - first.y
                let perUnit = max(unit.perUnit, 1e-6)
                result.value = hypot(b.x - a.x, b.y - a.y)
                result.text = "Δx \(name(of: refs[0]))\(name(of: refs[1])) = "
                    + "\(formatNumber(dx / perUnit, precision: settings.precision)) \(unit.short), "
                    + "Δy = \(formatNumber(dy / perUnit, precision: settings.precision)) \(unit.short)"
                result.anchor = a.lerp(to: b, 0.5) + Vec2(0, 0.28)
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

    func arcLabelAnchor(_ path: EvalPath) -> Vec2? {
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

    func label(of id: UUID) -> String {
        objects[id]?.label ?? ""
    }

    func joinedLabels(_ ids: [UUID]) -> String {
        ids.compactMap { objects[$0]?.label }.filter { !$0.isEmpty }.joined()
    }

    func arcName(_ object: SketchObject, labels: String) -> String {
        if !object.label.isEmpty {
            return object.label
        }
        return labels.isEmpty ? "arc" : "arc \(labels)"
    }

    mutating func calculationResult(_ expression: String) -> EvalResult {
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

    mutating func calculationVariables() -> [String: Double] {
        var variables: [String: Double] = [:]
        for object in objects.values {
            if case .measurement(let kind, let refs) = object.kind {
                let result = measurement(kind: kind, refs: refs)
                if let value = result.value, !object.label.isEmpty {
                    variables[object.label.replacingOccurrences(of: " ", with: "_")] = value
                }
            }
            if case .parameter(let value, _, _) = object.kind, !object.label.isEmpty {
                variables[object.label.replacingOccurrences(of: " ", with: "_")] = value
            }
        }
        return variables
    }

    mutating func angleResult(
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

    mutating func angleGeometry(a: UUID, vertex: UUID, c: UUID) -> AngleGeometry? {
        guard let pa = point(a), let pv = point(vertex), let pc = point(c) else {
            return nil
        }
        let u = (pa - pv).normalized()
        let v = (pc - pv).normalized()
        let unsigned = acos(min(max(u.dot(v), -1), 1))
        // Plain degrees are undirected (0–180°); directed degrees and
        // radians keep the sign.
        let value = settings.angleUnit == .degrees ? unsigned : atan2(u.cross(v), u.dot(v))
        var bisector = (u + v).normalized()
        if bisector.length < Metrics.epsilon {
            bisector = u.perpendicular()
        }
        return AngleGeometry(start: pa, vertex: pv, end: pc, value: value, bisector: bisector)
    }

    func positiveAngle(_ angle: Double) -> Double {
        let twoPi = 2 * Double.pi
        var value = angle.truncatingRemainder(dividingBy: twoPi)
        if value < 0 {
            value += twoPi
        }
        return value
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

    func equationText(for path: EvalPath, name: String) -> String? {
        if let straight = path.straight {
            return lineEquationText(straight, name: name)
        }
        if case .circle(let center, let radius) = path {
            return circleEquationText(center: center, radius: radius, name: name)
        }
        return nil
    }

    func lineEquationText(
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

    func circleEquationText(center: Vec2, radius: Double, name: String) -> String {
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
}
