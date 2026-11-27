import SwiftUI

extension SketchModel {

    // MARK: measurement commands

    func measure(_ kind: MeasureKind) {
        let ids = selection
        var e = evaluator()
        var refs: [UUID] = []
        switch kind {
        case .distance:
            let pts = ids.filter { e.evaluate($0).point != nil }
            guard pts.count >= 2 else {
                statusMessage = "Select two points"
                return
            }
            refs = Array(pts.prefix(2))
        case .length:
            var chosen: UUID?
            for id in ids {
                if let path = e.path(id), path.length(settings: settings) != nil {
                    chosen = id
                    break
                }
            }
            guard let chosen else {
                statusMessage = "Select a path with a finite length"
                return
            }
            refs = [chosen]
        case .perimeter:
            var chosen: UUID?
            for id in ids {
                if let path = e.path(id), case .polygon = path {
                    chosen = id
                    break
                }
            }
            guard let chosen else {
                statusMessage = "Select a polygon"
                return
            }
            refs = [chosen]
        case .circumference, .radius:
            var chosen: UUID?
            for id in ids {
                if let path = e.path(id), case .circle = path {
                    chosen = id
                    break
                }
            }
            guard let chosen else {
                statusMessage = "Select a circle"
                return
            }
            refs = [chosen]
        case .slope:
            var chosen: UUID?
            for id in ids {
                if let path = e.path(id), path.straight != nil {
                    chosen = id
                    break
                }
            }
            guard let chosen else {
                statusMessage = "Select a straight object"
                return
            }
            refs = [chosen]
        case .equation:
            var chosen: UUID?
            for id in ids {
                guard let path = e.path(id) else {
                    continue
                }
                if path.straight != nil {
                    chosen = id
                    break
                }
                if case .circle = path {
                    chosen = id
                    break
                }
            }
            guard let chosen else {
                statusMessage = "Select a line or circle"
                return
            }
            refs = [chosen]
        case .angle:
            let pts = ids.filter { e.evaluate($0).point != nil }
            guard pts.count >= 3 else {
                statusMessage = "Select three points"
                return
            }
            refs = Array(pts.prefix(3))
        case .arcAngle, .arcLength:
            guard let id = ids.first(where: { id in
                if case .arc = e.evaluate(id).path {
                    return true
                }
                return false
            }) else {
                statusMessage = "Select an arc"
                return
            }
            refs = [id]
        case .area:
            var chosen: UUID?
            for id in ids {
                guard let path = e.path(id) else {
                    continue
                }
                if case .polygon = path {
                    chosen = id
                    break
                }
                if case .circle = path {
                    chosen = id
                    break
                }
            }
            guard let chosen else {
                statusMessage = "Select a polygon or circle"
                return
            }
            refs = [chosen]
        case .ratio:
            let paths = ids.filter { e.evaluate($0).path?.straight != nil }
            guard paths.count >= 2 else {
                statusMessage = "Select two segments"
                return
            }
            refs = Array(paths.prefix(2))
        case .coordinates, .abscissa, .ordinate, .polarDistance, .polarDirection, .coordinateDistance:
            let pts = ids.filter { e.evaluate($0).point != nil }
            let needed = kind == .coordinateDistance ? 2 : 1
            guard pts.count >= needed else {
                statusMessage = needed == 2 ? "Select two points" : "Select a point"
                return
            }
            refs = kind == .coordinateDistance ? Array(pts.prefix(2)) : [pts[0]]
            if let system = ids.first(where: { id in
                if let object = objectByID(id), case .coordinateSystem = object.kind {
                    return true
                }
                return false
            }) {
                refs.append(system)
            }
        }
        guard measurementFits(kind, refs: refs, evaluator: &e) else {
            statusMessage = "That selection cannot be measured as \(kind.title)"
            return
        }
        checkpoint("Measure \(kind.title)")
        let id = commit(kind: .measurement(kind, refs: refs), label: "")
        selection = [id]
        statusMessage = "\(kind.title) measured"
    }

    /// Rejects a measurement whose selected objects cannot produce a value,
    /// so the canvas does not collect invisible measurement cards.
    private func measurementFits(_ kind: MeasureKind,
                                 refs: [UUID],
                                 evaluator: inout GeometryEval) -> Bool {
        switch kind {
        case .distance, .coordinateDistance:
            guard refs.count >= 2 else {
                return false
            }
            return evaluator.point(refs[0]) != nil && evaluator.point(refs[1]) != nil
        case .angle:
            guard refs.count >= 3 else {
                return false
            }
            return evaluator.point(refs[0]) != nil
                && evaluator.point(refs[1]) != nil
                && evaluator.point(refs[2]) != nil
        case .coordinates, .abscissa, .ordinate, .polarDistance, .polarDirection:
            guard let first = refs.first else {
                return false
            }
            return evaluator.point(first) != nil
        case .ratio:
            guard refs.count >= 2,
                  let firstPath = evaluator.path(refs[0]),
                  let secondPath = evaluator.path(refs[1]),
                  firstPath.length(settings: settings) != nil,
                  let second = secondPath.length(settings: settings) else {
                return false
            }
            return second > 1e-9
        case .length:
            guard let first = refs.first, let path = evaluator.path(first) else {
                return false
            }
            return path.length(settings: settings) != nil
        case .perimeter:
            guard let first = refs.first,
                  let path = evaluator.path(first),
                  case .polygon = path else {
                return false
            }
            return true
        case .circumference, .radius:
            guard let first = refs.first,
                  let path = evaluator.path(first),
                  case .circle = path else {
                return false
            }
            return true
        case .area:
            guard let first = refs.first, let path = evaluator.path(first) else {
                return false
            }
            switch path {
            case .polygon, .circle:
                return true
            default:
                return false
            }
        case .arcAngle, .arcLength:
            guard let first = refs.first,
                  let path = evaluator.path(first),
                  case .arc = path else {
                return false
            }
            return true
        case .slope:
            guard let first = refs.first, let path = evaluator.path(first) else {
                return false
            }
            return path.straight != nil
        case .equation:
            guard let first = refs.first, let path = evaluator.path(first) else {
                return false
            }
            if path.straight != nil {
                return true
            }
            if case .circle = path {
                return true
            }
            return false
        }
    }

    func addCalculation(expression: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        checkpoint("Add Calculation")
        let id = commit(kind: .calculation(trimmed), label: "")
        selection = [id]
        statusMessage = "Calculation added"
    }

    /// One sensible measurement for every selected object.
    func measureAll() {
        guard !selection.isEmpty else {
            statusMessage = "Select objects to measure"
            return
        }
        var plans: [(MeasureKind, [UUID])] = []
        var e = evaluator()
        for id in selection {
            guard let object = objectByID(id) else {
                continue
            }
            switch object.kind {
            case .freePoint, .pointOnPath, .midpoint, .intersection:
                plans.append((.coordinates, [id]))
            case .transformed, .locus:
                if e.evaluate(id).point != nil {
                    plans.append((.coordinates, [id]))
                }
            case .segment:
                plans.append((.length, [id]))
            case .ray, .line, .perpendicular, .parallel, .angleBisector,
                 .construction, .vector:
                plans.append((.slope, [id]))
            case .graph(.derivative), .graph(.tangent):
                plans.append((.slope, [id]))
            case .circle, .circleRadius:
                plans.append((.circumference, [id]))
            case .arcOnCircle, .arcThroughPoints:
                plans.append((.arcLength, [id]))
            case .polygon:
                plans.append((.area, [id]))
            case .angle(let a, let vertex, let c):
                plans.append((.angle, [a, vertex, c]))
            default:
                break
            }
        }
        guard !plans.isEmpty else {
            statusMessage = "No measurable objects are selected"
            return
        }
        if let system = selection.first(where: { id in
            if let object = objectByID(id), case .coordinateSystem = object.kind {
                return true
            }
            return false
        }) {
            for index in plans.indices {
                switch plans[index].0 {
                case .coordinates, .abscissa, .ordinate, .polarDistance, .polarDirection:
                    plans[index].1.append(system)
                default:
                    break
                }
            }
        }
        var validation = evaluator()
        var validPlans: [(MeasureKind, [UUID])] = []
        for plan in plans {
            if measurementFits(plan.0, refs: plan.1, evaluator: &validation) {
                validPlans.append(plan)
            }
        }
        guard !validPlans.isEmpty else {
            statusMessage = "No measurable objects are selected"
            return
        }
        checkpoint("Measure All")
        var created: [UUID] = []
        for (kind, refs) in validPlans {
            created.append(commit(kind: .measurement(kind, refs: refs), label: ""))
        }
        selection = created
        statusMessage = "\(created.count) measurement\(created.count == 1 ? "" : "s") created"
    }

    struct SelectionMetrics {
        var area: Double
        var perimeter: Double
    }

    /// Readout shown next to the pointer while a point is dragged: its
    /// position plus every measurement that depends on it.
    func dragReadout(for id: UUID) -> [(String, String)] {
        guard let object = objectByID(id), let point = evaluated(id).point else {
            return []
        }
        let unit = settings.lengthUnit
        let formatter = evaluator()
        let x = formatter.formatNumber(point.x / unit.perUnit, precision: settings.precision)
        let y = formatter.formatNumber(point.y / unit.perUnit, precision: settings.precision)
        var rows: [(String, String)] = [
            (object.label.isEmpty ? "Point" : object.label, "\(x), \(y) \(unit.short)")
        ]
        for measurement in objects {
            guard case .measurement(let kind, let refs) = measurement.kind,
                  refs.contains(id),
                  let text = evaluated(measurement.id).text else {
                continue
            }
            rows.append((measurement.label.isEmpty ? kind.title : measurement.label, text))
            if rows.count >= 4 {
                break
            }
        }
        return rows
    }

    /// Combined area and perimeter of the selected regions and paths, for the
    /// status bar. Straight rays and lines have no finite perimeter and are
    /// skipped.
    func selectionMetrics() -> SelectionMetrics? {
        guard !selection.isEmpty else {
            return nil
        }
        var area = 0.0
        var perimeter = 0.0
        var e = evaluator()
        var polygonEdges: Set<String> = []
        for id in selection {
            guard let object = objectByID(id), object.visible,
                  case .polygon(let vertices) = object.kind else {
                continue
            }
            for index in vertices.indices {
                polygonEdges.insert(edgeKey(vertices[index], vertices[(index + 1) % vertices.count]))
            }
        }
        for id in selection {
            guard let object = objectByID(id), object.visible else {
                continue
            }
            if case .segment(let a, let b) = object.kind,
               polygonEdges.contains(edgeKey(a, b)) {
                // A polygon already contributes this side's length.
                continue
            }
            let result = e.evaluate(id)
            if let fill = result.fill {
                area += polygonArea(of: fill)
            }
            if let path = result.path {
                switch path {
                case .polygon:
                    perimeter += path.length(settings: settings) ?? 0
                    area += polygonArea(of: path)
                case .circle(_, let radius):
                    area += Double.pi * radius * radius
                    perimeter += 2 * Double.pi * radius
                case .arc(_, let radius, _, let sweep):
                    perimeter += radius * abs(sweep)
                case .segment:
                    perimeter += path.length(settings: settings) ?? 0
                case .polyline:
                    perimeter += path.length(settings: settings) ?? 0
                case .ray, .line, .functionPlot:
                    break
                }
            }
        }
        guard area > 0 || perimeter > 0 else {
            return nil
        }
        return SelectionMetrics(area: area, perimeter: perimeter)
    }

    private func edgeKey(_ a: UUID, _ b: UUID) -> String {
        let first = a.uuidString
        let second = b.uuidString
        return first < second ? "\(first)|\(second)" : "\(second)|\(first)"
    }

    private func polygonArea(of path: EvalPath) -> Double {
        guard case .polygon(let points) = path, points.count >= 3 else {
            return 0
        }
        var sum = 0.0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            sum += a.cross(b)
        }
        return abs(sum) / 2
    }

}
