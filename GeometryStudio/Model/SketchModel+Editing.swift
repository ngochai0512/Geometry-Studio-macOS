import SwiftUI

extension SketchModel {

    // MARK: selection

    func isSelected(_ id: UUID) -> Bool {
        selection.contains(id)
    }

    func select(_ id: UUID, additive: Bool = false) {
        if additive {
            if let i = selection.firstIndex(of: id) {
                selection.remove(at: i)
            } else {
                selection.append(id)
            }
        } else {
            selection = [id]
        }
        statusMessage = ""
    }

    func clearSelection() {
        selection = []
    }

    func selectAll() {
        selection = objects.filter(\.visible).map(\.id)
    }

    func deleteSelection() {
        guard !selection.isEmpty else {
            return
        }
        checkpoint(selection.count == 1 ? "Delete Object" : "Delete \(selection.count) Objects")
        var doomed = Set(selection)
        var changed = true
        while changed {
            changed = false
            for object in objects where !doomed.contains(object.id) {
                if parents(of: object).contains(where: { doomed.contains($0) }) {
                    doomed.insert(object.id)
                    changed = true
                }
            }
        }
        objects.removeAll { doomed.contains($0.id) }
        if let animated = animationPointID, doomed.contains(animated) {
            stopAnimationClock()
            animationPointID = nil
        }
        pruneMarks(removing: doomed)
        selection = []
        draft = []
        statusMessage = "Deleted \(doomed.count) object\(doomed.count == 1 ? "" : "s")"
    }

    func parents(of object: SketchObject) -> [UUID] {
        switch object.kind {
        case .freePoint, .caption, .functionPlot, .calculation:
            return []
        case .pointOnPath(let p, _):
            return [p]
        case .midpoint(let a, let b):
            return [a, b]
        case .intersection(let a, let b, _):
            return [a, b]
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            return [a, b]
        case .perpendicular(let l, let p), .parallel(let l, let p):
            return [l, p]
        case .angleBisector(let a, let v, let c):
            return [a, v, c]
        case .circle(let c, let t):
            return [c, t]
        case .circleRadius(let c, _):
            return [c]
        case .arcOnCircle(let circle, let start, let end):
            return [circle, start, end]
        case .arcThroughPoints(let a, let b, let c):
            return [a, b, c]
        case .polygon(let v):
            return v
        case .angle(let a, let v, let c):
            return [a, v, c]
        case .measurement(_, let refs):
            return refs
        case .transformed(let s, let spec):
            var out = [s]
            if let r = spec.reference {
                out.append(r)
            }
            if let r = spec.secondReference {
                out.append(r)
            }
            if let mark = spec.angleMark {
                out.append(contentsOf: [mark.a, mark.vertex, mark.c])
            }
            if let mark = spec.ratioMark {
                out.append(contentsOf: [mark.first, mark.second])
            }
            return out
        case .locus(let driver, let target):
            return [driver, target]
        case .parameter, .graph:
            return []
        case .construction(let kind):
            switch kind {
            case .perpendicularBisector(let a, let b):
                return [a, b]
            case .tangentPointToCircle(let point, let circle, _):
                return [point, circle]
            case .tangentCircleToCircle(let a, let b, _):
                return [a, b]
            case .radicalAxis(let a, let b):
                return [a, b]
            }
        case .vector(let kind):
            switch kind {
            case .fromPoints(let from, let to):
                return [from, to]
            case .sum(let a, let b, _):
                return [a, b]
            }
        case .coordinateSystem(_, let origin, _, _):
            return [origin]
        }
    }

    func definition(for object: SketchObject) -> String {
        let eval = evaluator()
        return eval.definition(of: object.id)
    }

    func hideSelection() {
        guard !selection.isEmpty else {
            return
        }
        checkpoint(selection.count == 1 ? "Hide Object" : "Hide \(selection.count) Objects")
        for id in selection {
            if let i = index(of: id) {
                objects[i].visible = false
            }
        }
        selection = []
        statusMessage = "Objects hidden"
    }

    func showAll() {
        checkpoint("Show All Objects")
        for i in objects.indices {
            objects[i].visible = true
        }
        statusMessage = "All hidden objects are visible again"
    }

    func toggleLabels(for ids: [UUID]) {
        guard !ids.isEmpty else {
            return
        }
        checkpoint("Toggle Labels")
        for id in ids {
            if let i = index(of: id) {
                objects[i].showLabel.toggle()
            }
        }
    }

}

extension SketchModel {

    // MARK: drag

    func beginDrag(at p: Vec2, tolerance: Double) -> UUID? {
        guard let hit = hitTest(p, tolerance: tolerance), let object = objectByID(hit) else {
            return nil
        }
        switch object.kind {
        case .freePoint, .pointOnPath:
            return hit
        default:
            return nil
        }
    }

    func dragPoint(_ id: UUID, to p: Vec2) {
        guard let i = index(of: id) else {
            return
        }
        switch objects[i].kind {
        case .freePoint:
            objects[i].position = snapped(p)
        case .pointOnPath(let parent, let oldParam):
            var e = evaluator()
            guard let path = e.path(parent) else {
                return
            }
            var target = p
            if settings.snap, case .circle(let c, _) = path {
                let a = atan2(target.y - c.y, target.x - c.x)
                let radius = c.distance(to: target)
                target = c + Vec2(cos(a), sin(a)) * radius
                // routine rounds the drag angle to 15° buckets. When the
                // bucket lands on a horizontal or vertical direction it keeps
                // the point's previous x or y, so the point does not jitter
                // across a cardinal point.
                let bucket = ((Int((a / (Double.pi / 12)).rounded()) % 12) + 12) % 12
                if let old = path.point(at: oldParam) {
                    if bucket == 0 {
                        let dy = old.y - c.y
                        let dx = max(radius * radius - dy * dy, 0).squareRoot()
                        target = Vec2(c.x + (cos(a) >= 0 ? dx : -dx), old.y)
                    } else if bucket == 6 {
                        let dx = old.x - c.x
                        let dy = max(radius * radius - dx * dx, 0).squareRoot()
                        target = Vec2(old.x, c.y + (sin(a) >= 0 ? dy : -dy))
                    }
                }
            }
            let param = path.nearestParam(to: target)
            objects[i].kind = .pointOnPath(path: parent, param: param)
        default:
            break
        }
        recordTraceSamples()
    }

    func translateObject(_ id: UUID, by delta: Vec2) {
        guard let i = index(of: id) else {
            return
        }
        switch objects[i].kind {
        case .freePoint, .caption:
            objects[i].position = (objects[i].position ?? .zero) + delta
        case .measurement, .calculation, .angle:
            objects[i].offset = objects[i].offset + delta
        default:
            break
        }
    }

    func setLabelOffset(_ id: UUID, _ offset: Vec2) {
        guard let i = index(of: id) else {
            return
        }
        objects[i].offset = offset
    }

    func setCaptionPosition(_ id: UUID, _ position: Vec2) {
        guard let i = index(of: id) else {
            return
        }
        objects[i].position = position
    }

    func setCaptionText(_ id: UUID, _ text: String) {
        guard let i = index(of: id) else {
            return
        }
        if case .caption = objects[i].kind {
            checkpoint("Edit Text")
            objects[i].kind = .caption(text)
        }
    }

    func moveLabel(_ id: UUID, by delta: Vec2) {
        guard let i = index(of: id) else {
            return
        }
        if case .measurement = objects[i].kind {
            objects[i].offset = objects[i].offset + delta
        } else if case .calculation = objects[i].kind {
            objects[i].offset = objects[i].offset + delta
        } else if case .caption = objects[i].kind {
            objects[i].position = (objects[i].position ?? .zero) + delta
        } else if case .angle = objects[i].kind {
            objects[i].offset = objects[i].offset + delta
        }
    }

}
