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
                    if best == nil || d < best!.1 {
                        best = (object.id, d)
                    }
                }
            }
        }
        return best?.0
    }

    func ensurePoint(at p: Vec2, tolerance: Double) -> UUID {
        if let existing = existingPoint(near: p, tolerance: tolerance) {
            return existing
        }
        // Attach to a path when the click is close to one.
        var e = evaluator()
        var bestPath: (UUID, Double)?
        for object in objects where object.visible {
            if let path = e.evaluate(object.id).path {
                let d = path.distance(to: p)
                if d <= max(tolerance, 0.05) {
                    if bestPath == nil || d < bestPath!.1 {
                        bestPath = (object.id, d)
                    }
                }
            }
        }
        if let (id, _) = bestPath, let path = e.evaluate(id).path {
            checkpoint("Add Point")
            let param = path.nearestParam(to: p)
            var object = SketchObject(kind: .pointOnPath(path: id, param: param))
            object.label = nextPointLabel()
            object.order = (objects.map(\.order).max() ?? 0) + 1
            objects.append(object)
            return object.id
        }
        checkpoint("Add Point")
        var object = SketchObject(kind: .freePoint)
        object.position = p
        object.label = nextPointLabel()
        object.order = (objects.map(\.order).max() ?? 0) + 1
        objects.append(object)
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
                let first = draft[0]
                perform("Draw \(tool.title)") {
                    let id = ensurePoint(at: p, tolerance: tolerance)
                    if id == first {
                        statusMessage = "Choose a different second point"
                        return
                    }
                    let kind: ObjectKind
                    switch tool {
                    case .segment:
                        kind = .segment(a: first, b: id)
                    case .ray:
                        kind = .ray(a: first, b: id)
                    default:
                        kind = .line(a: first, b: id)
                    }
                    var object = SketchObject(kind: kind)
                    object.label = ""
                    object.order = (objects.map(\.order).max() ?? 0) + 1
                    objects.append(object)
                    selection = [object.id]
                    draft = []
                    statusMessage = "\(tool.title) created"
                }
            }

        case .circle:
            if draft.count == 0 {
                draft = [ensurePoint(at: p, tolerance: tolerance)]
                selection = draft
            } else {
                let center = draft[0]
                perform("Draw Circle") {
                    let id = ensurePoint(at: p, tolerance: tolerance)
                    guard id != center else {
                        return
                    }
                    var object = SketchObject(kind: .circle(center: center, through: id))
                    object.order = (objects.map(\.order).max() ?? 0) + 1
                    objects.append(object)
                    selection = [object.id]
                    draft = []
                    statusMessage = "Circle created"
                }
            }

        case .polygon:
            let id = ensurePoint(at: p, tolerance: tolerance)
            if let first = draft.first, id == first, draft.count >= 3 {
                finishPolygon()
                return
            }
            if !draft.contains(id) {
                draft.append(id)
            }
            selection = draft
            statusMessage = draft.count >= 3 ? "Press Return to close the polygon" : "Click more vertices"

        case .angle:
            if draft.count < 2 {
                let id = ensurePoint(at: p, tolerance: tolerance)
                if draft.count == 0 {
                    draft = [id]
                } else if id != draft[0] {
                    draft.append(id)
                }
            } else {
                if let existing = existingPoint(near: p, tolerance: tolerance),
                   existing == draft[0] || existing == draft[1] {
                    return
                }
                perform("Mark Angle") {
                    let id = ensurePoint(at: p, tolerance: tolerance)
                    if id == draft[0] || id == draft[1] {
                        return
                    }
                    draft.append(id)
                    var object = SketchObject(kind: .angle(a: draft[0], vertex: draft[1], c: draft[2]))
                    let firstLabel = objectByID(draft[0])?.label ?? ""
                    let vertexLabel = objectByID(draft[1])?.label ?? ""
                    let secondLabel = objectByID(draft[2])?.label ?? ""
                    object.label = "m∠\(firstLabel)\(vertexLabel)\(secondLabel)"
                    object.order = (objects.map(\.order).max() ?? 0) + 1
                    objects.append(object)
                    selection = [object.id]
                    draft = []
                    statusMessage = "Angle marked"
                }
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
        checkpoint("Draw Polygon")
        var object = SketchObject(kind: .polygon(vertices: draft))
        object.order = (objects.map(\.order).max() ?? 0) + 1
        objects.append(object)
        selection = [object.id]
        draft = []
        statusMessage = "Polygon created"
    }

    func cancelDraft() {
        draft = []
        statusMessage = "Cancelled"
    }

}
