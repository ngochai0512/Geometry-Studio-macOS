import SwiftUI

extension SketchModel {

    // MARK: animation, trace and locus

    /// The point an animation can move: a selected point on a path, or the
    /// first point-on-path parent of a selected dependent object.
    var animatablePoint: UUID? {
        for id in selection {
            if case .pointOnPath = objectByID(id)?.kind {
                return id
            }
        }
        for id in selection {
            var current = objectByID(id)
            var hops = 0
            while let object = current, hops < 24 {
                if case .pointOnPath = object.kind {
                    return object.id
                }
                current = parents(of: object).first.flatMap { objectByID($0) }
                hops += 1
            }
        }
        return nil
    }

    func toggleAnimation() {
        if animationPointID != nil {
            animationPointID = nil
            statusMessage = "Animation paused"
            return
        }
        guard let id = animatablePoint else {
            statusMessage = "Select a point on an object to animate"
            return
        }
        animationDirection = 1
        animationPointID = id
        statusMessage = "Animating \(objectByID(id)?.label ?? "point") — choose Animate again to pause"
    }

    /// Points on straight objects move back and forth; points on circles go
    /// all the way round, following the original's motion principles.
    func advanceAnimation() {
        var e = evaluator()
        guard let id = animationPointID,
              let i = index(of: id),
              case .pointOnPath(let parent, let param) = objects[i].kind,
              let path = e.path(parent) else {
            return
        }
        var next = param
        if case .circle = path {
            next = (param + 0.022).truncatingRemainder(dividingBy: 2 * .pi)
            if next < 0 {
                next += 2 * .pi
            }
        } else {
            next = param + 0.0045 * animationDirection
            if next > 1 {
                next = 1
                animationDirection = -1
            }
            if next < 0 {
                next = 0
                animationDirection = 1
            }
        }
        objects[i].kind = .pointOnPath(path: parent, param: next)
        recordTraceSamples()
    }

    func toggleTrace() {
        guard !selection.isEmpty else {
            statusMessage = "Select an object to trace"
            return
        }
        if selection.allSatisfy({ tracedIDs.contains($0) }) {
            for id in selection {
                tracedIDs.remove(id)
            }
            statusMessage = "Tracing off"
        } else {
            for id in selection {
                tracedIDs.insert(id)
            }
            statusMessage = "Tracing \(selection.count) object\(selection.count == 1 ? "" : "s")"
        }
    }

    func eraseTraces() {
        tracePaths.removeAll()
        statusMessage = "Traces erased"
    }

    func recordTraceSamples() {
        guard !tracedIDs.isEmpty else {
            return
        }
        var e = evaluator()
        for id in tracedIDs {
            guard let p = e.evaluate(id).point else {
                continue
            }
            var points = tracePaths[id] ?? []
            if points.last?.distance(to: p) ?? .greatestFiniteMagnitude > 0.004 {
                points.append(p)
            }
            if points.count > 800 {
                points.removeFirst(points.count - 800)
            }
            tracePaths[id] = points
        }
    }

    /// A locus is the set of positions of a driven object as its driver
    /// varies over the driver's path (the original's Locus definition).
    func constructLocus() {
        let chosen = selection.compactMap { objectByID($0) }
        guard let driver = chosen.first(where: {
            if case .pointOnPath = $0.kind {
                return true
            }
            return false
        }) else {
            statusMessage = "A locus needs a point on a path plus the point it drives"
            return
        }
        guard let target = chosen.last(where: { $0.id != driver.id && $0.isPointLike }) else {
            statusMessage = "Select the driven point after its driver"
            return
        }
        checkpoint("Construct Locus")
        var object = SketchObject(kind: .locus(driver: driver.id, target: target.id))
        object.order = (objects.map(\.order).max() ?? 0) + 1
        object.style.color = .violet
        object.style.lineWidth = 1.6
        objects.append(object)
        selection = [object.id]
        statusMessage = "Locus constructed"
    }

}
