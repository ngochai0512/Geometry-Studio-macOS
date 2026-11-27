import SwiftUI

/// A transient alignment aid drawn while a point is being placed or dragged.
struct SmartGuide: Hashable {
    enum Kind: Hashable {
        case point
        case midpoint
        case intersection
        case alignment
        case parallel
        case perpendicular
        case angle
    }

    var from: Vec2
    var to: Vec2
    var kind: Kind
}

extension SketchModel {

    // MARK: geometry access

    func evaluator() -> GeometryEval {
        GeometryEval(objects: objects, settings: settings)
    }

    func evaluated(_ id: UUID) -> EvalResult {
        var e = evaluator()
        return e.evaluate(id)
    }

    func screenPoint(_ p: Vec2, size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + (p.x - settings.center.x) * settings.scale,
                y: size.height / 2 - (p.y - settings.center.y) * settings.scale)
    }

    func worldPoint(_ p: CGPoint, size: CGSize) -> Vec2 {
        Vec2(settings.center.x + (p.x - size.width / 2) / settings.scale,
             settings.center.y - (p.y - size.height / 2) / settings.scale)
    }

    func visibleRect(size: CGSize) -> WorldRect {
        let tl = worldPoint(CGPoint(x: 0, y: 0), size: size)
        let br = worldPoint(CGPoint(x: size.width, y: size.height), size: size)
        return WorldRect(minX: min(tl.x, br.x), minY: min(tl.y, br.y),
                         maxX: max(tl.x, br.x), maxY: max(tl.y, br.y))
    }

    /// The grid family's world-space cell size at the current zoom.
    func gridStep() -> Double {
        let minimumSpacing = settings.gridType == .orthogonalDense ? 24.0 : 50.0
        return GridMetrics.step(scale: settings.scale,
                                perUnit: settings.lengthUnit.perUnit,
                                minimumSpacing: minimumSpacing)
    }

    /// The nearest lattice point for the current grid type. Returns the input
    /// unchanged when snapping is off, so callers can use it unconditionally.
    func snapped(_ point: Vec2) -> Vec2 {
        guard settings.snap else {
            return point
        }
        let step = gridStep()
        guard step > 0, step.isFinite else {
            return point
        }
        switch settings.gridType {
        case .orthogonal, .orthogonalDense:
            return Vec2((point.x / step).rounded() * step,
                        (point.y / step).rounded() * step)
        case .triangular:
            let height = step * sqrt(3) / 2
            guard height > 0, height.isFinite else {
                return point
            }
            let baseRow = Int((point.y / height).rounded())
            var best = point
            var bestDistance = Double.greatestFiniteMagnitude
            for row in (baseRow - 1)...(baseRow + 1) {
                let offset = ((row % 2) + 2) % 2 == 0 ? 0 : step / 2
                let x = ((point.x - offset) / step).rounded() * step + offset
                let candidate = Vec2(x, Double(row) * height)
                let distance = candidate.distance(to: point)
                if distance < bestDistance {
                    best = candidate
                    bestDistance = distance
                }
            }
            return best
        case .polar:
            let radius = (point.length / step).rounded() * step
            let spoke = Double.pi / 12
            let angle = (atan2(point.y, point.x) / spoke).rounded() * spoke
            return Vec2(cos(angle) * radius, sin(angle) * radius)
        case .isometric:
            // The isometric lattice is the triangular lattice turned 90°:
            // vertical columns with staggered rows.
            let height = step * sqrt(3) / 2
            guard height > 0, height.isFinite else {
                return point
            }
            let baseColumn = Int((point.x / height).rounded())
            var best = point
            var bestDistance = Double.greatestFiniteMagnitude
            for column in (baseColumn - 1)...(baseColumn + 1) {
                let offset = ((column % 2) + 2) % 2 == 0 ? 0 : step / 2
                let y = ((point.y - offset) / step).rounded() * step + offset
                let candidate = Vec2(Double(column) * height, y)
                let distance = candidate.distance(to: point)
                if distance < bestDistance {
                    best = candidate
                    bestDistance = distance
                }
            }
            return best
        }
    }

    // MARK: smart guides and angle snapping

    /// Snaps `point` to geometry worth aligning with and returns the guides to
    /// draw. Existing points win over angle snapping, which wins over guide
    /// projections, which win over the grid.
    func smartSnappedPoint(_ point: Vec2,
                           tolerance: Double,
                           anchor: Vec2? = nil,
                           excluding: Set<UUID> = [],
                           includeIntersections: Bool = true) -> (point: Vec2, guides: [SmartGuide]) {
        let tol = max(tolerance, 0.02)
        guard settings.smartGuides else {
            return (angleSnappedPoint(snapped(point), anchor: anchor), [])
        }

        var e = evaluator()
        let visible = objects.filter { $0.visible && !excluding.contains($0.id) }
        var geometry: [(point: Vec2, distance: Double, guides: [SmartGuide])] = []

        for object in visible {
            var mayBePoint = object.isPointLike
            if case .transformed = object.kind {
                mayBePoint = true
            }
            if mayBePoint, let p = e.evaluate(object.id).point {
                let d = p.distance(to: point)
                if d <= tol {
                    geometry.append((p, d, [crosshair(at: p, kind: .point)]))
                }
            }
            if case .segment(let a, let b) = object.kind,
               let pa = e.evaluate(a).point,
               let pb = e.evaluate(b).point {
                let mid = pa.lerp(to: pb, 0.5)
                let d = mid.distance(to: point)
                if d <= tol {
                    geometry.append((mid, d, [crosshair(at: mid, kind: .midpoint)]))
                }
            }
        }

        // Intersections only matter while a new point is being placed. Capping
        // the pair count keeps the drag path responsive on a dense sketch.
        if includeIntersections, anchor != nil, visible.count <= 240 {
            var paths: [EvalPath] = []
            for object in visible.prefix(18) {
                if let path = e.evaluate(object.id).path {
                    paths.append(path)
                }
            }
            for i in paths.indices {
                for j in paths.indices where j > i {
                    for hit in paths[i].intersections(with: paths[j]) {
                        let d = hit.distance(to: point)
                        if d <= tol {
                            geometry.append((hit, d, [crosshair(at: hit, kind: .intersection)]))
                        }
                    }
                }
            }
        }
        if let best = geometry.min(by: { $0.distance < $1.distance }) {
            return (best.point, best.guides)
        }

        if anchor != nil, settings.angleSnap > 0 {
            let angled = angleSnappedPoint(point, anchor: anchor)
            return (angled, [angleGuide(from: anchor, through: angled)])
        }

        if let anchor {
            let rect = visibleRect(size: canvasSize)
            let extent = max(rect.width, rect.height, 10)
            if abs(point.x - anchor.x) <= tol {
                let aligned = Vec2(anchor.x, point.y)
                let guide = SmartGuide(
                    from: Vec2(anchor.x, anchor.y - extent),
                    to: Vec2(anchor.x, anchor.y + extent),
                    kind: .alignment
                )
                return (aligned, [guide])
            }
            if abs(point.y - anchor.y) <= tol {
                let aligned = Vec2(point.x, anchor.y)
                let guide = SmartGuide(
                    from: Vec2(anchor.x - extent, anchor.y),
                    to: Vec2(anchor.x + extent, anchor.y),
                    kind: .alignment
                )
                return (aligned, [guide])
            }

            var lines = 0
            for object in visible where lines < 12 {
                guard let straight = e.evaluate(object.id).path?.straight else {
                    continue
                }
                lines += 1
                let direction = (straight.b - straight.a).normalized()
                for (kind, axis) in [(SmartGuide.Kind.parallel, direction),
                                     (SmartGuide.Kind.perpendicular, direction.perpendicular())] {
                    let projected = anchor + axis * (point - anchor).dot(axis)
                    if projected.distance(to: point) <= tol {
                        let guide = SmartGuide(
                            from: anchor - axis * extent,
                            to: anchor + axis * extent,
                            kind: kind
                        )
                        return (projected, [guide])
                    }
                }
            }
        }

        return (angleSnappedPoint(snapped(point), anchor: anchor), [])
    }

    /// Rounds the drawing direction around `anchor` to the chosen increment,
    /// keeping the pointer's distance.
    func angleSnappedPoint(_ point: Vec2, anchor: Vec2?) -> Vec2 {
        guard let anchor, settings.angleSnap > 0 else {
            return point
        }
        let delta = point - anchor
        guard delta.length > 1e-9 else {
            return point
        }
        let increment = settings.angleSnap * .pi / 180
        let angle = (delta.angle / increment).rounded() * increment
        return anchor + Vec2(cos(angle), sin(angle)) * delta.length
    }

    func clearSmartGuides() {
        if !smartGuides.isEmpty {
            smartGuides = []
        }
    }

    private func crosshair(at p: Vec2, kind: SmartGuide.Kind) -> SmartGuide {
        let arm = 0.45
        return SmartGuide(from: p - Vec2(arm, arm), to: p + Vec2(arm, arm), kind: kind)
    }

    private func angleGuide(from anchor: Vec2?, through point: Vec2) -> SmartGuide {
        let base = anchor ?? .zero
        let direction = (point - base).normalized()
        let rect = visibleRect(size: canvasSize)
        let extent = max(rect.width, rect.height, 10)
        return SmartGuide(from: base - direction * extent,
                          to: base + direction * extent,
                          kind: .angle)
    }

    // MARK: on-canvas selection transforms

    /// Free positions that can be moved for the current selection. Selecting a
    /// polygon, circle or measurement collects the free points its construction
    /// depends on, so handles transform the whole object rather than nothing.
    var canTransformSelection: Bool {
        movablePointIDs(for: selection).count >= 2
    }

    func movablePointIDs(for ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        var result: [UUID] = []
        var pending = ids
        while let id = pending.popLast() {
            guard !seen.contains(id), let object = objectByID(id) else {
                continue
            }
            seen.insert(id)
            guard !object.isLocked else {
                continue
            }
            switch object.kind {
            case .freePoint, .caption, .parameter:
                result.append(id)
            default:
                pending.append(contentsOf: parents(of: object))
            }
        }
        return result
    }

    func movablePositions(for id: UUID) -> [UUID: Vec2] {
        movablePositions(for: [id])
    }

    func movablePositions(for ids: [UUID]) -> [UUID: Vec2] {
        var positions: [UUID: Vec2] = [:]
        for pointID in movablePointIDs(for: ids) {
            if let position = objectByID(pointID)?.position {
                positions[pointID] = position
            }
        }
        return positions
    }

    /// A whole construction can be dragged by its free ancestors. Computed
    /// cards and images follow other state and are moved by their own controls.
    func canMoveObject(_ id: UUID) -> Bool {
        guard let object = objectByID(id), !object.isLocked else {
            return false
        }
        switch object.kind {
        case .transformed, .locus, .measurement, .calculation, .caption, .angle,
             .parameter, .graph, .functionPlot:
            return false
        default:
            return !movablePositions(for: id).isEmpty
        }
    }

    /// Moves free positions by a delta from a captured starting state. The
    /// caller supplies the base positions so a live drag does not accumulate.
    func translateMovablePoints(_ base: [UUID: Vec2], by delta: Vec2) {
        for (id, start) in base {
            guard let index = index(of: id), !objects[index].isLocked else {
                continue
            }
            objects[index].position = start + delta
        }
        recordTraceSamples()
    }

    /// Arrow-key nudging: move the free points under the selection by a world
    /// delta. One undo step covers a run of key presses.
    func nudgeSelection(by delta: Vec2) {
        guard !selection.isEmpty, delta.x.isFinite, delta.y.isFinite else {
            return
        }
        let positions = movablePositions(for: selection)
        guard !positions.isEmpty else {
            return
        }
        checkpoint("Nudge Selection", coalescing: "nudge-selection")
        translateMovablePoints(positions, by: delta)
    }

    func movableSelectionBounds() -> WorldRect? {
        guard canTransformSelection else {
            return nil
        }
        let points = movablePointIDs(for: selection).compactMap { id -> Vec2? in
            objectByID(id)?.position
        }
        guard var box = points.first.map({
            WorldRect(minX: $0.x, minY: $0.y, maxX: $0.x, maxY: $0.y)
        }) else {
            return nil
        }
        for p in points.dropFirst() {
            box.minX = min(box.minX, p.x)
            box.maxX = max(box.maxX, p.x)
            box.minY = min(box.minY, p.y)
            box.maxY = max(box.maxY, p.y)
        }
        let minimum = 0.6
        if box.width < minimum {
            let mid = (box.minX + box.maxX) / 2
            box.minX = mid - minimum / 2
            box.maxX = mid + minimum / 2
        }
        if box.height < minimum {
            let mid = (box.minY + box.maxY) / 2
            box.minY = mid - minimum / 2
            box.maxY = mid + minimum / 2
        }
        return box
    }

    func movableSelectionPositions() -> [UUID: Vec2] {
        var positions: [UUID: Vec2] = [:]
        for id in movablePointIDs(for: selection) {
            if let position = objectByID(id)?.position {
                positions[id] = position
            }
        }
        return positions
    }

    /// Applies a transform to an earlier snapshot of free positions, so a live
    /// handle drag can be recomputed from its start instead of compounding.
    func applyMovableSelection(_ base: [UUID: Vec2],
                               around center: Vec2,
                               scale: Double,
                               rotation: Double) {
        guard scale.isFinite, scale > 0.001 else {
            return
        }
        for i in objects.indices {
            guard let position = base[objects[i].id], !objects[i].isLocked else {
                continue
            }
            let relative = (position - center).scaled(scale)
            objects[i].position = center + (rotation == 0 ? relative : relative.rotated(by: rotation))
        }
    }

    func zoom(by factor: Double) {
        settings.scale = min(max(settings.scale * factor, 12), 420)
    }

    func setZoom(_ value: Double) {
        settings.scale = min(max(value, 12), 420)
    }

    func pan(dx: Double, dy: Double) {
        settings.center = settings.center - Vec2(dx / settings.scale, -dy / settings.scale)
    }

    /// Applies the shared canvas defaults to this sketch without touching the
    /// document's zoom or pan. Used by the Settings sheet.
    func applyCanvasDefaults(_ new: CanvasSettings) {
        var current = settings
        current.grid = new.grid
        current.gridType = new.gridType
        current.gridColor = new.gridColor
        current.gridBold = new.gridBold
        current.backgroundColor = new.backgroundColor
        current.theme = new.theme
        current.useMetalRenderer = new.useMetalRenderer
        current.axes = new.axes
        current.axesLabels = new.axesLabels
        current.axesLabelStyle = new.axesLabelStyle
        current.snap = new.snap
        current.showLabels = new.showLabels
        current.smartGuides = new.smartGuides
        current.angleSnap = new.angleSnap
        current.lengthUnit = new.lengthUnit
        current.angleUnit = new.angleUnit
        current.precision = new.precision
        settings = current
    }

    func fitCanvas(size: CGSize) {
        var e = evaluator()
        var pts: [Vec2] = []
        for object in objects where object.visible {
            let r = e.evaluate(object.id)
            if let p = r.point {
                pts.append(p)
            }
            if let b = r.path?.boundingBox {
                if b.width.isFinite && b.height.isFinite && b.width < 1_000 && b.height < 1_000 {
                    pts.append(Vec2(b.minX, b.minY))
                    pts.append(Vec2(b.maxX, b.maxY))
                }
            }
        }
        guard !pts.isEmpty, size.width > 40, size.height > 40 else {
            settings.center = Vec2(0, 0)
            settings.scale = SketchMetrics.pixelsPerCentimetre
            return
        }
        frame(points: pts, size: size)
    }

    /// Frames the current selection, leaving the zoom alone when nothing is
    /// selected.
    func zoomToSelection(size: CGSize) {
        guard !selection.isEmpty, size.width > 40, size.height > 40 else {
            return
        }
        var e = evaluator()
        var pts: [Vec2] = []
        for id in selection {
            guard let object = objectByID(id), object.visible else {
                continue
            }
            let r = e.evaluate(id)
            if let p = r.point {
                pts.append(p)
            }
            if let b = r.path?.boundingBox {
                if b.width.isFinite && b.height.isFinite && b.width < 1_000 && b.height < 1_000 {
                    pts.append(Vec2(b.minX, b.minY))
                    pts.append(Vec2(b.maxX, b.maxY))
                }
            }
        }
        frame(points: pts, size: size)
    }

    private func frame(points: [Vec2], size: CGSize) {
        guard !points.isEmpty else {
            return
        }
        var box = WorldRect(minX: points[0].x, minY: points[0].y,
                            maxX: points[0].x, maxY: points[0].y)
        for p in points {
            box.minX = min(box.minX, p.x)
            box.maxX = max(box.maxX, p.x)
            box.minY = min(box.minY, p.y)
            box.maxY = max(box.maxY, p.y)
        }
        let w = max(box.width, 2)
        let h = max(box.height, 2)
        settings.center = box.center
        settings.scale = min(max(min(size.width / (w * 1.35), size.height / (h * 1.35)), 18), 180)
    }

    // MARK: hit testing

    func hitTest(_ p: Vec2, tolerance: Double) -> UUID? {
        let tol = max(tolerance, 0.03)
        var e = evaluator()
        var best: (UUID, Double)?
        // Points first.
        for object in objects.reversed() where object.visible {
            if let pt = e.evaluate(object.id).point {
                let d = pt.distance(to: p)
                if d <= tol + 0.04 {
                    if best == nil || d < best!.1 {
                        best = (object.id, d)
                    }
                }
            }
        }
        if let best {
            return best.0
        }
        // Paths.
        for object in objects.reversed() where object.visible {
            if case .functionPlot(let expression) = object.kind {
                if var parser = Expression(expression) {
                    parser.setAngleUnit(settings.angleUnit)
                    if let y = parser.evaluate(x: p.x), abs(y - p.y) * settings.scale <= 9 {
                        return object.id
                    }
                }
                continue
            }
            if let path = e.evaluate(object.id).path {
                if path.distance(to: p) <= tol {
                    return object.id
                }
                // A polygon interior is a target too; the winding-number rule
                // decides.
                if path.contains(p) {
                    return object.id
                }
            }
            if let fill = e.evaluate(object.id).fill, fill.contains(p) {
                return object.id
            }
        }
        // Parameter cards are rectangles around a numeric value.
        for object in objects.sorted(by: { $0.order < $1.order }).reversed()
        where object.visible && object.showLabel {
            guard case .parameter = object.kind else {
                continue
            }
            let center = object.position ?? .zero
            let halfWidth = 64 / settings.scale
            let halfHeight = 19 / settings.scale
            let rect = WorldRect(minX: center.x - halfWidth, minY: center.y - halfHeight,
                                 maxX: center.x + halfWidth, maxY: center.y + halfHeight)
            if rect.contains(p) {
                return object.id
            }
        }
        // Measurement / caption boxes.
        let textOrder = objects.sorted { $0.order < $1.order }
        for object in textOrder.reversed() where object.visible && object.showLabel {
            if case .parameter = object.kind {
                continue
            }
            let r = e.evaluate(object.id)
            guard let text = r.text, let anchor = r.anchor else {
                continue
            }
            let base = textBounds(text: text, anchor: anchor)
            var isCaption = false
            if case .caption = object.kind {
                isCaption = true
            }
            if isCaption {
                if base.inset(-0.1).contains(p) {
                    return object.id
                }
                continue
            }
            // The drawing pass nudges overlapping cards downward. Check the
            // same possible positions so a visible card stays clickable.
            var rect = base
            for _ in 0...12 {
                if rect.inset(-0.05).contains(p) {
                    return object.id
                }
                let step = rect.height + 4 / settings.scale
                rect = WorldRect(minX: rect.minX, minY: rect.minY - step,
                                 maxX: rect.maxX, maxY: rect.maxY - step)
            }
        }
        return nil
    }

    func textBounds(text: String, anchor: Vec2) -> WorldRect {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let w = (size.width + 14) / settings.scale
        let h = (size.height + 8) / settings.scale
        return WorldRect(minX: anchor.x, minY: anchor.y, maxX: anchor.x + w, maxY: anchor.y + h)
    }

}
