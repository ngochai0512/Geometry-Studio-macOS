import SwiftUI

extension SketchModel {

    // MARK: point creation

    func existingPoint(near p: Vec2, tolerance: Double) -> UUID? {
        var e = evaluator()
        var best: (UUID, Double)?
        for object in objects where object.visible {
            if let pt = e.evaluate(object.id).point {
                let d = pt.distance(to: p)
                if d <= max(tolerance, 0.05) {
                    if best == nil || d < best!.1 { best = (object.id, d) }
                }
            }
        }
        return best?.0
    }

    func ensurePoint(at p: Vec2, tolerance: Double) -> UUID {
        if let existing = existingPoint(near: p, tolerance: tolerance) { return existing }
        // Attach to a path when the click is close to one.
        var e = evaluator()
        var bestPath: (UUID, Double)?
        for object in objects where object.visible {
            if let path = e.evaluate(object.id).path {
                let d = path.distance(to: p)
                if d <= max(tolerance, 0.05) {
                    if bestPath == nil || d < bestPath!.1 { bestPath = (object.id, d) }
                }
            }
        }
        if let (id, _) = bestPath, let path = e.evaluate(id).path {
            checkpoint()
            let param = path.nearestParam(to: p)
            var object = SketchObject(kind: .pointOnPath(path: id, param: param))
            object.label = nextPointLabel()
            object.order = (objects.map(\.order).max() ?? 0) + 1
            objects.append(object)
            isDirty = true
            return object.id
        }
        checkpoint()
        var object = SketchObject(kind: .freePoint)
        object.position = p
        object.label = nextPointLabel()
        object.order = (objects.map(\.order).max() ?? 0) + 1
        objects.append(object)
        isDirty = true
        return object.id
    }

    // MARK: canvas tool actions

    func clickCanvas(at p: Vec2, tolerance: Double, additive: Bool) {
        switch tool {
        case .select:
            if let hit = hitTest(p, tolerance: tolerance) {
                select(hit, additive: additive)
            } else {
                clearSelection()
            }

        case .point:
            if let existing = existingPoint(near: p, tolerance: tolerance) {
                select(existing)
                return
            }
            let id = ensurePoint(at: p, tolerance: tolerance)
            selection = [id]
            statusMessage = "Point created"

        case .segment, .ray, .line:
            if draft.count == 0 {
                let id = ensurePoint(at: p, tolerance: tolerance)
                draft = [id]
                selection = [id]
            } else if draft.count == 1 {
                let id = ensurePoint(at: p, tolerance: tolerance)
                if id == draft[0] {
                    statusMessage = "Choose a different second point"
                    return
                }
                checkpoint()
                let kind: ObjectKind
                switch tool {
                case .segment: kind = .segment(a: draft[0], b: id)
                case .ray: kind = .ray(a: draft[0], b: id)
                default: kind = .line(a: draft[0], b: id)
                }
                var object = SketchObject(kind: kind)
                object.label = ""
                object.order = (objects.map(\.order).max() ?? 0) + 1
                objects.append(object)
                selection = [object.id]
                draft = []
                isDirty = true
                statusMessage = "\(tool.title) created"
            }

        case .circle:
            if draft.count == 0 {
                draft = [ensurePoint(at: p, tolerance: tolerance)]
                selection = draft
            } else {
                let id = ensurePoint(at: p, tolerance: tolerance)
                if id == draft[0] { return }
                checkpoint()
                var object = SketchObject(kind: .circle(center: draft[0], through: id))
                object.order = (objects.map(\.order).max() ?? 0) + 1
                objects.append(object)
                selection = [object.id]
                draft = []
                isDirty = true
                statusMessage = "Circle created"
            }

        case .polygon:
            let id = ensurePoint(at: p, tolerance: tolerance)
            if let first = draft.first, id == first, draft.count >= 3 {
                finishPolygon()
                return
            }
            if !draft.contains(id) { draft.append(id) }
            selection = draft
            statusMessage = draft.count >= 3 ? "Press Return to close the polygon" : "Click more vertices"

        case .angle:
            let id = ensurePoint(at: p, tolerance: tolerance)
            if draft.count == 0 {
                draft = [id]
            } else if draft.count == 1 {
                if id != draft[0] { draft.append(id) }
            } else {
                if id == draft[0] || id == draft[1] { return }
                draft.append(id)
                checkpoint()
                var object = SketchObject(kind: .angle(a: draft[0], vertex: draft[1], c: draft[2]))
                object.label = "m∠\(objectByID(draft[0])?.label ?? "")\(objectByID(draft[1])?.label ?? "")\(objectByID(draft[2])?.label ?? "")"
                object.order = (objects.map(\.order).max() ?? 0) + 1
                objects.append(object)
                selection = [object.id]
                draft = []
                isDirty = true
                statusMessage = "Angle marked"
            }

        case .text:
            break
        }
    }

    func finishPolygon() {
        guard draft.count >= 3 else {
            statusMessage = "A polygon needs at least three points"
            return
        }
        checkpoint()
        var object = SketchObject(kind: .polygon(vertices: draft))
        object.order = (objects.map(\.order).max() ?? 0) + 1
        objects.append(object)
        selection = [object.id]
        draft = []
        isDirty = true
        statusMessage = "Polygon created"
    }

    func cancelDraft() {
        draft = []
        statusMessage = "Cancelled"
    }

}
