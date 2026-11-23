import Foundation

extension GeometryEval {
    /// A one-line construction definition for the inspector and protocol.
    func definition(of id: UUID) -> String {
        guard let object = objects[id] else {
            return "Unknown object"
        }
        switch object.kind {
        case .freePoint:
            guard let position = object.position else {
                return "Free point \(name(of: id))"
            }
            return "Free point \(name(of: id)) at \(displayPoint(position))"
        case .pointOnPath(let path, _):
            return "Point \(name(of: id)) on \(reference(path))"
        case .midpoint(let a, let b):
            return "Midpoint \(name(of: id)) of \(reference(a)) and \(reference(b))"
        case .intersection(let a, let b, let index):
            return "Intersection \(name(of: id)) of \(reference(a)) and \(reference(b))"
                + " (solution \(index + 1))"
        case .segment(let a, let b):
            return "Segment \(segmentName(object, a: a, b: b))"
        case .ray(let a, let b):
            return "Ray \(segmentName(object, a: a, b: b))"
        case .line(let a, let b):
            return "Line \(segmentName(object, a: a, b: b))"
        case .perpendicular(let line, let point):
            return "Line through \(reference(point)) perpendicular to \(reference(line))"
        case .parallel(let line, let point):
            return "Line through \(reference(point)) parallel to \(reference(line))"
        case .angleBisector(let a, let vertex, let c):
            return "Angle bisector of ∠\(angleName(a, vertex, c))"
        case .circle(let center, let through):
            return "\(kindName(object, "Circle")) centered at \(reference(center))"
                + " through \(reference(through))"
        case .circleRadius(let center, let radius):
            return "\(kindName(object, "Circle")) centered at \(reference(center))"
                + " with radius \(formatLength(radius))"
        case .arcOnCircle(let circle, let start, let end):
            return "\(kindName(object, "Arc")) on \(reference(circle))"
                + " from \(reference(start)) to \(reference(end))"
        case .arcThroughPoints(let a, let b, let c):
            return "\(kindName(object, "Arc")) through \(references([a, b, c]))"
        case .polygon:
            let polygonName = object.label.isEmpty ? name(of: id) : object.label
            return polygonName.isEmpty ? "Polygon" : "Polygon \(polygonName)"
        case .angle(let a, let vertex, let c):
            return "Angle ∠\(angleName(a, vertex, c))"
        case .measurement(let kind, let refs):
            let name = object.label.isEmpty
                ? "\(kind.title) measurement"
                : "\(kind.title) measurement \(object.label)"
            return "\(name) of \(references(refs))"
        case .calculation(let expression):
            let name = object.label.isEmpty ? "Calculation" : "Calculation \(object.label)"
            return "\(name): \(expression)"
        case .caption(let text):
            return "Caption \"\(text)\""
        case .functionPlot(let expression):
            let name = object.label.isEmpty ? "Function plot" : "Function plot \(object.label)"
            return "\(name): \(expression)"
        case .transformed(let source, let spec):
            return "\(transformName(spec.kind)) of \(reference(source))"
        case .locus(let driver, let target):
            return "Locus of \(reference(target)) as \(reference(driver)) moves"
        case .parameter(let value, let minimum, let maximum):
            let name = object.label.isEmpty ? "Parameter" : "Parameter \(object.label)"
            return "\(name) = \(formatNumber(value, precision: settings.precision))"
                + " (\(formatNumber(minimum, precision: settings.precision))…\(formatNumber(maximum, precision: settings.precision)))"
        case .construction(let kind):
            switch kind {
            case .perpendicularBisector(let a, let b):
                return "Perpendicular bisector of \(reference(a))\(reference(b))"
            case .tangentPointToCircle(let point, let circle, _):
                return "Tangent from \(reference(point)) to \(reference(circle))"
            case .tangentCircleToCircle(let a, let b, _):
                return "Common tangent of \(reference(a)) and \(reference(b))"
            case .radicalAxis(let a, let b):
                return "Radical axis of \(reference(a)) and \(reference(b))"
            }
        case .vector(let kind):
            switch kind {
            case .fromPoints(let from, let to):
                return "Vector \(reference(from))→\(reference(to))"
            case .sum(let a, let b, let subtract):
                return "\(subtract ? "Difference" : "Sum") of \(reference(a)) and \(reference(b))"
            }
        case .coordinateSystem(let kind, let origin, let step, let unit):
            let stepText = formatNumber(step / max(unit.perUnit, 1e-6), precision: 2)
            return "\(kind.title) coordinate system at \(reference(origin)) · \(stepText) \(unit.short) step"
        case .graph(let feature):
            switch feature {
            case .derivative(let expression):
                return "Derivative of \(expression)"
            case .integral(let expression, let from, let to):
                return "Integral of \(expression) from \(formatNumber(from, precision: 2)) to \(formatNumber(to, precision: 2))"
            case .tangent(let expression, let x):
                return "Tangent of \(expression) at x = \(formatNumber(x, precision: 2))"
            case .table(let expression, _, _, _):
                return "Value table for \(expression)"
            }
        }
    }

    private func reference(_ id: UUID) -> String {
        let name = name(of: id)
        return name.isEmpty ? "?" : name
    }

    private func kindName(_ object: SketchObject, _ kind: String) -> String {
        object.label.isEmpty ? kind : "\(kind) \(object.label)"
    }

    private func segmentName(_ object: SketchObject, a: UUID, b: UUID) -> String {
        if !object.label.isEmpty {
            return object.label
        }
        let endpoints = "\(reference(a))\(reference(b))"
        return endpoints.isEmpty ? "segment" : endpoints
    }

    private func references(_ ids: [UUID]) -> String {
        ids.map { reference($0) }.joined(separator: ", ")
    }

    private func angleName(_ a: UUID, _ vertex: UUID, _ c: UUID) -> String {
        "\(reference(a))\(reference(vertex))\(reference(c))"
    }

    private func displayPoint(_ point: Vec2) -> String {
        let unit = settings.lengthUnit
        let x = formatNumber(point.x / unit.perUnit, precision: settings.precision)
        let y = formatNumber(point.y / unit.perUnit, precision: settings.precision)
        return "(\(x), \(y)) \(unit.short)"
    }

    private func transformName(_ kind: TransformKind) -> String {
        switch kind {
        case .reflect:
            return "Reflection"
        case .rotate:
            return "Rotation"
        case .translate:
            return "Translation"
        case .dilate:
            return "Dilation"
        }
    }
}
