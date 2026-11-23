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
        case .length, .perimeter, .circumference, .radius, .slope:
            guard let id = ids.first(where: { e.evaluate($0).path != nil }) else {
                statusMessage = "Select a path first"
                return
            }
            refs = [id]
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
            guard let id = ids.first(where: { e.evaluate($0).path != nil }) else {
                statusMessage = "Select a polygon or circle"
                return
            }
            refs = [id]
        case .ratio:
            let paths = ids.filter { e.evaluate($0).path?.straight != nil }
            guard paths.count >= 2 else {
                statusMessage = "Select two segments"
                return
            }
            refs = Array(paths.prefix(2))
        case .coordinates, .abscissa, .ordinate, .polarDistance, .polarDirection, .coordinateDistance:
            let pts = ids.filter { e.evaluate($0).point != nil }
            guard pts.count >= 2 else {
                statusMessage = kind == .coordinateDistance ? "Select two points" : "Select a point"
                return
            }
            refs = kind == .coordinateDistance ? Array(pts.prefix(2)) : [pts[0]]
            if kind == .coordinateDistance,
               let system = ids.first(where: { id in
                   if let object = objectByID(id), case .coordinateSystem = object.kind {
                       return true
                   }
                   return false
               }) {
                refs.append(system)
            }
        case .equation:
            guard let id = ids.first(where: { e.evaluate($0).path != nil }) else {
                statusMessage = "Select a line or circle"
                return
            }
            refs = [id]
        }
        _ = e
        checkpoint("Measure \(kind.title)")
        let id = commit(kind: .measurement(kind, refs: refs), label: "")
        selection = [id]
        statusMessage = "\(kind.title) measured"
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
        for id in selection {
            guard let object = objectByID(id) else {
                continue
            }
            switch object.kind {
            case .freePoint, .pointOnPath, .midpoint, .intersection:
                plans.append((.coordinates, [id]))
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
        checkpoint("Measure All")
        var created: [UUID] = []
        for (kind, refs) in plans {
            created.append(commit(kind: .measurement(kind, refs: refs), label: ""))
        }
        selection = created
        statusMessage = "\(created.count) measurement\(created.count == 1 ? "" : "s") created"
    }

}
