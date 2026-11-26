import AppKit
import SwiftUI

/// Objects copied to the pasteboard. The payload carries parent objects too,
/// so pasting into another document keeps constructions intact.
private struct CopiedObjectPayload: Codable {
    var objects: [SketchObject]
}

private let sketchObjectPasteboardType =
    NSPasteboard.PasteboardType("com.geometrystudio.gsp.objects")

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
        let unlocked = selection.filter { objectByID($0)?.isLocked != true }
        guard !unlocked.isEmpty else {
            statusMessage = "Locked objects cannot be deleted"
            return
        }
        checkpoint(unlocked.count == 1 ? "Delete Object" : "Delete \(unlocked.count) Objects")
        var doomed = Set(unlocked)
        var changed = true
        while changed {
            changed = false
            for object in objects where !doomed.contains(object.id) && !object.isLocked {
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
        let editable = selection.filter { objectByID($0)?.isLocked != true }
        guard !editable.isEmpty else {
            statusMessage = "Locked objects cannot be hidden"
            return
        }
        checkpoint(editable.count == 1 ? "Hide Object" : "Hide \(editable.count) Objects")
        for id in editable {
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
            if let i = index(of: id), !objects[i].isLocked {
                objects[i].showLabel.toggle()
            }
        }
    }

    // MARK: labels

    /// The world anchor of an object's label. Free points carry their own
    /// offset so their letter can be dragged independently of the point.
    func labelAnchor(for object: SketchObject) -> Vec2? {
        switch object.kind {
        case .measurement, .calculation, .caption, .angle:
            return evaluated(object.id).anchor
        default:
            guard object.isPointLike else {
                return nil
            }
            return evaluated(object.id).point.map { $0 + object.offset }
        }
    }

    func labelBounds(for object: SketchObject) -> WorldRect? {
        guard settings.showLabels, object.visible, object.showLabel, !object.label.isEmpty,
              let anchor = labelAnchor(for: object) else {
            return nil
        }
        return textBounds(text: object.label, anchor: anchor)
    }

    /// Returns the topmost label under the pointer. Labels are separate drag
    /// targets so a letter can move without moving its point.
    func hitTestLabel(_ p: Vec2, tolerance: Double) -> UUID? {
        for object in objects.reversed() where object.visible {
            if let bounds = labelBounds(for: object),
               bounds.inset(-max(tolerance, 0.05)).contains(p) {
                return object.id
            }
        }
        return nil
    }

    func setLabelText(_ id: UUID, _ text: String) {
        guard let i = index(of: id), !objects[i].isLocked else {
            return
        }
        checkpoint("Edit Label", coalescing: "label-\(id)")
        if case .caption = objects[i].kind {
            objects[i].kind = .caption(text)
        } else {
            objects[i].label = text
        }
    }

    // MARK: locking and layers

    func toggleLockSelection() {
        guard !selection.isEmpty else {
            return
        }
        let allLocked = selectedObjects.allSatisfy(\.isLocked)
        checkpoint(allLocked ? "Unlock Objects" : "Lock Objects")
        for i in objects.indices where selection.contains(objects[i].id) {
            objects[i].isLocked = !allLocked
        }
        statusMessage = allLocked ? "Objects unlocked" : "Objects locked"
    }

    func bringSelectionToFront() {
        reorderSelection(toFront: true)
    }

    func sendSelectionToBack() {
        reorderSelection(toFront: false)
    }

    private func reorderSelection(toFront: Bool) {
        guard !selection.isEmpty else {
            return
        }
        checkpoint(toFront ? "Bring to Front" : "Send to Back")
        let selected = objects.filter { selection.contains($0.id) }
        let others = objects.filter { !selection.contains($0.id) }
        var ordered = toFront ? others + selected : selected + others
        for index in ordered.indices {
            ordered[index].order = index + 1
        }
        objects = ordered
        statusMessage = toFront ? "Selection moved to the front" : "Selection moved to the back"
    }

    // MARK: duplicate, copy and paste

    var canPasteObjects: Bool {
        NSPasteboard.general.data(forType: sketchObjectPasteboardType) != nil
    }

    func copySelection() {
        guard let payload = copyPayload() else {
            statusMessage = "Select objects to copy"
            return
        }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else {
            statusMessage = "Could not copy the selection"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: sketchObjectPasteboardType)
        statusMessage = "Copied \(payload.objects.count) object\(payload.objects.count == 1 ? "" : "s")"
    }

    func cutSelection() {
        copySelection()
        guard canPasteObjects else {
            return
        }
        deleteSelection()
    }

    @discardableResult
    func pasteObjects(inPlace: Bool = false) -> [UUID] {
        guard let data = NSPasteboard.general.data(forType: sketchObjectPasteboardType),
              let payload = try? JSONDecoder().decode(CopiedObjectPayload.self, from: data) else {
            statusMessage = "There are no copied objects"
            return []
        }
        let offset = inPlace ? Vec2.zero : Vec2(0.6, -0.6)
        let pasted = insertCopied(payload, offset: offset, action: inPlace ? "Paste in Place" : "Paste Objects")
        statusMessage = "Pasted \(pasted.count) object\(pasted.count == 1 ? "" : "s")"
        return pasted
    }

    @discardableResult
    func duplicateSelection() -> [UUID] {
        guard let payload = copyPayload() else {
            statusMessage = "Select objects to duplicate"
            return []
        }
        let duplicated = insertCopied(payload, offset: Vec2(0.6, -0.6), action: "Duplicate Objects")
        statusMessage = "Duplicated \(duplicated.count) object\(duplicated.count == 1 ? "" : "s")"
        return duplicated
    }

    private func copyPayload() -> CopiedObjectPayload? {
        guard !selection.isEmpty else {
            return nil
        }
        var included = Set<UUID>()
        var pending = selection
        while let id = pending.popLast() {
            guard !included.contains(id), let object = objectByID(id) else {
                continue
            }
            included.insert(id)
            pending.append(contentsOf: parents(of: object))
        }
        let copied = objects
            .filter { included.contains($0.id) }
            .sorted { $0.order < $1.order }
        guard !copied.isEmpty else {
            return nil
        }
        return CopiedObjectPayload(objects: copied)
    }

    private func insertCopied(_ payload: CopiedObjectPayload,
                              offset: Vec2,
                              action: String) -> [UUID] {
        guard !payload.objects.isEmpty else {
            return []
        }
        checkpoint(action)
        var identifiers: [UUID: UUID] = [:]
        for object in payload.objects {
            identifiers[object.id] = UUID()
        }
        let baseOrder = (objects.map(\.order).max() ?? 0) + 1
        var newIDs: [UUID] = []
        for (index, original) in payload.objects.enumerated() {
            var object = original
            object.id = identifiers[original.id] ?? UUID()
            object.kind = remappedKind(original.kind, using: identifiers)
            object.label = uniqueCopiedLabel(original)
            if let position = object.position {
                object.position = position + offset
            }
            object.order = baseOrder + index
            object.isLocked = false
            objects.append(object)
            newIDs.append(object.id)
        }
        selection = newIDs
        return newIDs
    }

    /// A copy keeps the original label only when it is still unique. Points
    /// get the next free letter; named measurements, parameters and angles get
    /// a numeric suffix so calculation variables do not collide.
    private func uniqueCopiedLabel(_ original: SketchObject) -> String {
        let label = original.label
        guard !label.isEmpty else {
            return label
        }
        let used = Set(objects.map(\.label))
        guard used.contains(label) else {
            return label
        }
        switch original.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return nextPointLabel()
        default:
            var index = 2
            while used.contains("\(label) \(index)") {
                index += 1
            }
            return "\(label) \(index)"
        }
    }

    private func remappedKind(_ kind: ObjectKind, using map: [UUID: UUID]) -> ObjectKind {
        func m(_ id: UUID) -> UUID {
            map[id] ?? id
        }
        switch kind {
        case .freePoint:
            return .freePoint
        case .pointOnPath(let path, let param):
            return .pointOnPath(path: m(path), param: param)
        case .midpoint(let a, let b):
            return .midpoint(a: m(a), b: m(b))
        case .intersection(let a, let b, let index):
            return .intersection(a: m(a), b: m(b), index: index)
        case .segment(let a, let b):
            return .segment(a: m(a), b: m(b))
        case .ray(let a, let b):
            return .ray(a: m(a), b: m(b))
        case .line(let a, let b):
            return .line(a: m(a), b: m(b))
        case .perpendicular(let line, let point):
            return .perpendicular(line: m(line), point: m(point))
        case .parallel(let line, let point):
            return .parallel(line: m(line), point: m(point))
        case .angleBisector(let a, let vertex, let c):
            return .angleBisector(a: m(a), vertex: m(vertex), c: m(c))
        case .circle(let center, let through):
            return .circle(center: m(center), through: m(through))
        case .circleRadius(let center, let radius):
            return .circleRadius(center: m(center), radius: radius)
        case .arcOnCircle(let circle, let start, let end):
            return .arcOnCircle(circle: m(circle), start: m(start), end: m(end))
        case .arcThroughPoints(let a, let b, let c):
            return .arcThroughPoints(a: m(a), b: m(b), c: m(c))
        case .polygon(let vertices):
            return .polygon(vertices: vertices.map { m($0) })
        case .angle(let a, let vertex, let c):
            return .angle(a: m(a), vertex: m(vertex), c: m(c))
        case .measurement(let measure, let refs):
            return .measurement(measure, refs: refs.map { m($0) })
        case .calculation(let expression):
            return .calculation(expression)
        case .caption(let text):
            return .caption(text)
        case .functionPlot(let expression):
            return .functionPlot(expression)
        case .transformed(let source, let spec):
            var copied = spec
            copied.reference = spec.reference.map { m($0) }
            copied.secondReference = spec.secondReference.map { m($0) }
            if let mark = spec.angleMark {
                copied.angleMark = AngleMark(a: m(mark.a), vertex: m(mark.vertex), c: m(mark.c))
            }
            if let mark = spec.ratioMark {
                copied.ratioMark = RatioMark(first: m(mark.first), second: m(mark.second))
            }
            return .transformed(source: m(source), spec: copied)
        case .locus(let driver, let target):
            return .locus(driver: m(driver), target: m(target))
        case .parameter(let value, let minimum, let maximum):
            return .parameter(value: value, minimum: minimum, maximum: maximum)
        case .construction(let construction):
            switch construction {
            case .perpendicularBisector(let a, let b):
                return .construction(.perpendicularBisector(a: m(a), b: m(b)))
            case .tangentPointToCircle(let point, let circle, let index):
                return .construction(.tangentPointToCircle(point: m(point),
                                                           circle: m(circle),
                                                           index: index))
            case .tangentCircleToCircle(let a, let b, let index):
                return .construction(.tangentCircleToCircle(a: m(a), b: m(b), index: index))
            case .radicalAxis(let a, let b):
                return .construction(.radicalAxis(a: m(a), b: m(b)))
            }
        case .vector(let vector):
            switch vector {
            case .fromPoints(let from, let to):
                return .vector(.fromPoints(from: m(from), to: m(to)))
            case .sum(let a, let b, let subtract):
                return .vector(.sum(a: m(a), b: m(b), subtract: subtract))
            }
        case .coordinateSystem(let coordinateKind, let origin, let step, let unit):
            return .coordinateSystem(kind: coordinateKind,
                                     origin: m(origin),
                                     step: step,
                                     unit: unit)
        case .graph(let feature):
            return .graph(feature)
        }
    }

}

extension SketchModel {

    // MARK: drag

    /// The moved object plus everything that derives from it. These are not
    /// valid snap targets while the point moves, or the point chases itself.
    func dependentIDs(of id: UUID) -> Set<UUID> {
        var included: Set<UUID> = [id]
        var changed = true
        while changed {
            changed = false
            for object in objects where !included.contains(object.id) {
                if parents(of: object).contains(where: { included.contains($0) }) {
                    included.insert(object.id)
                    changed = true
                }
            }
        }
        return included
    }

    func beginDrag(at p: Vec2, tolerance: Double) -> UUID? {
        guard let hit = hitTest(p, tolerance: tolerance), let object = objectByID(hit),
              !object.isLocked else {
            return nil
        }
        switch object.kind {
        case .freePoint, .pointOnPath:
            dragSnapExclusions = dependentIDs(of: hit)
            return hit
        default:
            return nil
        }
    }

    /// Precise placement from the inspector or the inline coordinate field.
    /// Only free points have an editable position; constructed points follow
    /// their parents.
    func moveFreePoint(_ id: UUID, to p: Vec2, coalescing key: String? = nil) {
        guard let i = index(of: id), !objects[i].isLocked,
              case .freePoint = objects[i].kind,
              p.x.isFinite, p.y.isFinite else {
            return
        }
        checkpoint("Move Point", coalescing: key)
        objects[i].position = p
        recordTraceSamples()
    }

    @discardableResult
    func dragPoint(_ id: UUID, to p: Vec2, smartTolerance: Double = 0) -> Vec2? {
        guard let i = index(of: id), !objects[i].isLocked else {
            return nil
        }
        let target: Vec2
        if smartTolerance > 0 {
            let exclusions = dragSnapExclusions.isEmpty ? Set([id]) : dragSnapExclusions
            let smart = smartSnappedPoint(p, tolerance: smartTolerance,
                                          excluding: exclusions)
            target = smart.point
            smartGuides = smart.guides
        } else {
            target = snapped(p)
            smartGuides = []
        }
        switch objects[i].kind {
        case .freePoint:
            objects[i].position = target
            recordTraceSamples()
            return target
        case .pointOnPath(let parent, let oldParam):
            var e = evaluator()
            guard let path = e.path(parent) else {
                return nil
            }
            var pointOnPath = target
            if settings.snap, case .circle(let c, _) = path {
                let a = atan2(pointOnPath.y - c.y, pointOnPath.x - c.x)
                let radius = c.distance(to: pointOnPath)
                pointOnPath = c + Vec2(cos(a), sin(a)) * radius
                // Round the drag angle to 15° buckets. When the bucket lands
                // on a horizontal or vertical direction, keep the point's
                // previous x or y so it does not jitter across a cardinal
                // point.
                let bucket = ((Int((a / (Double.pi / 12)).rounded()) % 12) + 12) % 12
                if let old = path.point(at: oldParam) {
                    if bucket == 0 {
                        let dy = old.y - c.y
                        let dx = max(radius * radius - dy * dy, 0).squareRoot()
                        pointOnPath = Vec2(c.x + (cos(a) >= 0 ? dx : -dx), old.y)
                    } else if bucket == 6 {
                        let dx = old.x - c.x
                        let dy = max(radius * radius - dx * dx, 0).squareRoot()
                        pointOnPath = Vec2(old.x, c.y + (sin(a) >= 0 ? dy : -dy))
                    }
                }
            }
            let param = path.nearestParam(to: pointOnPath)
            objects[i].kind = .pointOnPath(path: parent, param: param)
            recordTraceSamples()
            return pointOnPath
        default:
            return nil
        }
    }

    func translateObject(_ id: UUID, by delta: Vec2) {
        guard let i = index(of: id), !objects[i].isLocked else {
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
        guard let i = index(of: id), !objects[i].isLocked else {
            return
        }
        objects[i].offset = offset
    }

    func setCaptionPosition(_ id: UUID, _ position: Vec2) {
        guard let i = index(of: id), !objects[i].isLocked else {
            return
        }
        objects[i].position = position
    }

    func setCaptionText(_ id: UUID, _ text: String) {
        guard let i = index(of: id), !objects[i].isLocked else {
            return
        }
        if case .caption = objects[i].kind {
            checkpoint("Edit Text")
            objects[i].kind = .caption(text)
        }
    }

    func moveLabel(_ id: UUID, by delta: Vec2) {
        guard let i = index(of: id), !objects[i].isLocked else {
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
