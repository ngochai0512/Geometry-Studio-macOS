import SwiftUI

extension SketchModel {

    // MARK: marks

    func markMirror() {
        guard let mirror = selectedStraights().last,
              let object = objectByID(mirror) else {
            statusMessage = "Select a straight object to mark as the mirror"
            return
        }
        marks.mirror = mirror
        statusMessage = "Mirror marked: \(displayName(for: object))"
    }

    func markCenter() {
        guard let center = selectedPoints().first,
              let object = objectByID(center) else {
            statusMessage = "Select a point to mark as the center"
            return
        }
        marks.center = center
        statusMessage = "Center marked: \(displayName(for: object))"
    }

    func markAngle() {
        let points = selectedPoints()
        guard points.count >= 3 else {
            statusMessage = "Select three points: first side, vertex, second side"
            return
        }
        marks.angle = AngleMark(a: points[0], vertex: points[1], c: points[2])
        statusMessage = "Angle marked: \(markName(points[0])) \(markName(points[1])) \(markName(points[2]))"
    }

    func markRatio() {
        let paths = selectedPaths()
        guard paths.count >= 2 else {
            statusMessage = "Select the two objects whose lengths define the ratio"
            return
        }
        var e = evaluator()
        guard let firstPath = e.path(paths[0]),
              let secondPath = e.path(paths[1]),
              firstPath.length(settings: settings) != nil,
              secondPath.length(settings: settings) != nil else {
            statusMessage = "Both marked objects need a measurable length"
            return
        }
        marks.ratio = RatioMark(first: paths[0], second: paths[1])
        statusMessage = "Ratio marked: \(markName(paths[0])) / \(markName(paths[1]))"
    }

    func markVector() {
        let points = selectedPoints()
        guard points.count >= 2 else {
            statusMessage = "Select two points to mark the vector"
            return
        }
        marks.vector = VectorMark(from: points[0], to: points[1])
        statusMessage = "Vector marked: \(markName(points[0])) → \(markName(points[1]))"
    }

    func clearMarks() {
        guard !marks.isEmpty else {
            statusMessage = "No marks to clear"
            return
        }
        marks = TransformMarks()
        statusMessage = "Marks cleared"
    }

    /// Drops any mark that points at an object the user just deleted.
    func pruneMarks(removing doomed: Set<UUID>) {
        var updated = marks
        if let mirror = updated.mirror, doomed.contains(mirror) {
            updated.mirror = nil
        }
        if let center = updated.center, doomed.contains(center) {
            updated.center = nil
        }
        if let angle = updated.angle,
           doomed.contains(angle.a) || doomed.contains(angle.vertex) || doomed.contains(angle.c) {
            updated.angle = nil
        }
        if let ratio = updated.ratio, doomed.contains(ratio.first) || doomed.contains(ratio.second) {
            updated.ratio = nil
        }
        if let vector = updated.vector, doomed.contains(vector.from) || doomed.contains(vector.to) {
            updated.vector = nil
        }
        if updated != marks {
            marks = updated
        }
    }

    func markName(_ id: UUID?) -> String {
        guard let id, let object = objectByID(id) else {
            return "—"
        }
        return object.label.isEmpty ? displayName(for: object) : object.label
    }

    private func markedAngleRadians() -> Double? {
        guard let mark = marks.angle else {
            return nil
        }
        var e = evaluator()
        guard let a = e.point(mark.a),
              let vertex = e.point(mark.vertex),
              let c = e.point(mark.c) else {
            return nil
        }
        let u = a - vertex
        let v = c - vertex
        return atan2(u.cross(v), u.dot(v))
    }

    private func markedRatio() -> Double? {
        guard let mark = marks.ratio else {
            return nil
        }
        var e = evaluator()
        guard let firstPath = e.path(mark.first),
              let secondPath = e.path(mark.second),
              let first = firstPath.length(settings: settings),
              let second = secondPath.length(settings: settings),
              second > 1e-9 else {
            return nil
        }
        return first / second
    }

    private func transformSources(excluding ids: Set<UUID>) -> [UUID] {
        selection.filter { !ids.contains($0) }
    }

    private func applied(_ name: String, sources: [UUID], spec: TransformSpec) {
        checkpoint(name)
        var created: [UUID] = []
        for source in sources {
            created.append(commit(kind: .transformed(source: source, spec: spec), label: ""))
        }
        selection = created
        statusMessage = "\(name) created"
    }

    // MARK: transform commands

    func reflectSelection() {
        let mirror = marks.mirror ?? selectedStraights().last
        guard let mirror, objectByID(mirror) != nil else {
            statusMessage = "Mark a mirror line, or select one with the other objects"
            return
        }
        let sources = transformSources(excluding: [mirror])
        guard !sources.isEmpty else {
            statusMessage = "Select objects to reflect as well as the mirror"
            return
        }
        applied("Reflect", sources: sources,
                spec: TransformSpec(kind: .reflect, reference: mirror))
    }

    func rotateSelection() {
        guard let center = marks.center, objectByID(center) != nil else {
            statusMessage = "Mark a center point first"
            return
        }
        guard let radians = markedAngleRadians() else {
            statusMessage = "Mark an angle first"
            return
        }
        var excluded: Set<UUID> = [center]
        if let angle = marks.angle {
            excluded.formUnion([angle.a, angle.vertex, angle.c])
        }
        let sources = transformSources(excluding: excluded)
        guard !sources.isEmpty else {
            statusMessage = "Select objects to rotate after marking the center and angle"
            return
        }
        applied("Rotate", sources: sources,
                spec: TransformSpec(kind: .rotate, reference: center,
                                    angle: radians * 180 / .pi,
                                    angleMark: marks.angle))
    }

    func dilateSelection() {
        guard let center = marks.center, objectByID(center) != nil else {
            statusMessage = "Mark a center point first"
            return
        }
        guard let factor = markedRatio() else {
            statusMessage = "Mark a ratio first"
            return
        }
        var excluded: Set<UUID> = [center]
        if let ratio = marks.ratio {
            excluded.formUnion([ratio.first, ratio.second])
        }
        let sources = transformSources(excluding: excluded)
        guard !sources.isEmpty else {
            statusMessage = "Select objects to dilate after marking the center and ratio"
            return
        }
        applied("Dilate", sources: sources,
                spec: TransformSpec(kind: .dilate, reference: center, factor: factor,
                                    ratioMark: marks.ratio))
    }

    func translateSelection() {
        guard let vector = marks.vector,
              objectByID(vector.from) != nil,
              objectByID(vector.to) != nil else {
            statusMessage = "Mark a vector first"
            return
        }
        let sources = transformSources(excluding: [vector.from, vector.to])
        guard !sources.isEmpty else {
            statusMessage = "Select objects to translate after marking the vector"
            return
        }
        applied("Translate", sources: sources,
                spec: TransformSpec(kind: .translate, reference: vector.from,
                                    secondReference: vector.to))
    }

}
