import SwiftUI
import AppKit

extension SketchCanvas {

    // MARK: gestures

    func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if model.tool == .pan {
                    if !isPanning {
                        isPanning = true
                        NSCursor.closedHand.set()
                    }
                    if dragStartScreen == nil {
                        dragStartScreen = value.startLocation
                        panStartCenter = model.settings.center
                    }
                    let dx = value.location.x - value.startLocation.x
                    let dy = value.location.y - value.startLocation.y
                    model.settings.center = panStartCenter - Vec2(
                        dx / model.settings.scale,
                        -dy / model.settings.scale
                    )
                    return
                }

                let world = model.worldPoint(value.startLocation, size: size)
                let current = model.worldPoint(value.location, size: size)
                if dragStartScreen == nil {
                    dragStartScreen = value.startLocation
                    dragCheckpointed = false
                    didMove = false
                    holdReached = false
                    holdSelectionDone = false
                    pressStartedAt = Date()
                    lastSnapWorld = nil

                    if model.tool == .select {
                        let tol = 9 / model.settings.scale
                        if let handle = selectionHandleHit(value.startLocation, size: size) {
                            selectionHandle = handle
                            handleBasePositions = model.movableSelectionPositions()
                            handleCenter = model.movableSelectionBounds()?.center ?? .zero
                            handleStartVector = model.worldPoint(value.startLocation, size: size) - handleCenter
                            pressHitID = nil
                        } else if let labelHit = model.hitTestLabel(world, tolerance: tol),
                                  let object = model.objectByID(labelHit) {
                            pressHitID = labelHit
                            dragLabelID = labelHit
                            dragLabelBaseOffset = object.offset
                            dragLabelBasePosition = object.position ?? .zero
                            dragLabelIsCaption = isPositionCard(object)
                        } else if let hit = model.hitTest(world, tolerance: tol),
                                  let object = model.objectByID(hit) {
                            pressHitID = hit
                            if object.isPointLike || isTransformedPoint(object) {
                                dragPointID = model.beginDrag(at: world, tolerance: tol)
                            } else if isLabelLike(object) {
                                dragLabelID = hit
                                dragLabelBaseOffset = object.offset
                                dragLabelBasePosition = object.position ?? .zero
                                dragLabelIsCaption = isPositionCard(object)
                            }
                        } else {
                            pressHitID = nil
                            marqueeStart = value.startLocation
                            marqueeCurrent = value.startLocation
                        }
                    } else if isDrawingTool(model.tool) {
                        dragPreviewStart = world
                        dragPreviewCurrent = current
                    }
                }

                if isDrawingTool(model.tool), dragPreviewStart != nil {
                    dragPreviewCurrent = current
                }

                if abs(value.translation.width) + abs(value.translation.height) > 2 {
                    didMove = true
                }

                if let handle = selectionHandle, didMove {
                    if !dragCheckpointed {
                        model.checkpoint(handle == .rotate ? "Rotate Selection" : "Scale Selection")
                        dragCheckpointed = true
                    }
                    let vector = current - handleCenter
                    switch handle {
                    case .rotate:
                        model.applyMovableSelection(handleBasePositions,
                                                    around: handleCenter,
                                                    scale: 1,
                                                    rotation: vector.angle - handleStartVector.angle)
                    case .scale:
                        let factor = vector.length / max(handleStartVector.length, 1e-6)
                        model.applyMovableSelection(handleBasePositions,
                                                    around: handleCenter,
                                                    scale: factor,
                                                    rotation: 0)
                    }
                    return
                }

                if model.tool == .select, selectionHandle == nil {
                    if !holdReached, Date().timeIntervalSince(pressStartedAt) >= holdToDragDelay {
                        holdReached = true
                        if !holdSelectionDone, let id = dragPointID ?? dragLabelID ?? pressHitID {
                            model.select(id, additive: NSEvent.modifierFlags.contains(.shift))
                            holdSelectionDone = true
                        }
                        if dragPointID == nil && dragLabelID == nil {
                            marqueeStart = value.startLocation
                            marqueeCurrent = value.location
                        }
                    }
                    guard holdReached || pressHitID == nil else {
                        return
                    }
                }

                if let id = dragPointID, didMove {
                    if !dragCheckpointed {
                        let label = model.objectByID(id)?.label ?? ""
                        model.checkpoint(label.isEmpty ? "Move Point" : "Move \(label)")
                        dragCheckpointed = true
                    }
                    let tolerance = 9 / model.settings.scale
                    let applied = model.dragPoint(id, to: current, smartTolerance: tolerance)
                    hudScreen = value.location
                    if let applied, applied.distance(to: current) > 1e-6,
                       lastSnapWorld != applied {
                        lastSnapWorld = applied
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                } else if let id = dragLabelID, didMove {
                    if !dragCheckpointed {
                        model.checkpoint("Move Label")
                        dragCheckpointed = true
                    }
                    let total = Vec2((value.location.x - value.startLocation.x) / model.settings.scale,
                                     -(value.location.y - value.startLocation.y) / model.settings.scale)
                    if dragLabelIsCaption {
                        model.setCaptionPosition(id, dragLabelBasePosition + total)
                    } else {
                        model.setLabelOffset(id, dragLabelBaseOffset + total)
                    }
                } else if marqueeStart != nil, didMove {
                    marqueeCurrent = value.location
                }
            }
            .onEnded { value in
                defer {
                    if isPanning {
                        isPanning = false
                        if model.tool == .pan, model.isPointerOverCanvas {
                            NSCursor.openHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    dragStartScreen = nil
                    panStartCenter = .zero
                    dragPointID = nil
                    dragLabelID = nil
                    dragLabelIsCaption = false
                    dragCheckpointed = false
                    didMove = false
                    pressHitID = nil
                    pressStartedAt = .distantPast
                    holdReached = false
                    holdSelectionDone = false
                    lastSnapWorld = nil
                    marqueeStart = nil
                    marqueeCurrent = nil
                    hudScreen = nil
                    selectionHandle = nil
                    handleBasePositions = [:]
                    dragPreviewStart = nil
                    dragPreviewCurrent = nil
                    if model.tool != .pan {
                        model.clearSmartGuides()
                    }
                }
                if model.tool == .pan {
                    return
                }
                let start = model.worldPoint(value.startLocation, size: size)
                let end = model.worldPoint(value.location, size: size)
                let tol = 9 / model.settings.scale

                if model.tool == .select {
                    if selectionHandle != nil {
                        return
                    }
                    if holdReached, dragPointID != nil || dragLabelID != nil {
                        return
                    }
                    if didMove, let ms = marqueeStart, let mc = marqueeCurrent {
                        marqueeSelect(from: ms, to: mc, size: size)
                        return
                    }
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    if let hit = pressHitID {
                        model.select(hit, additive: shift)
                    } else {
                        model.clearSelection()
                    }
                    let clickCount = NSApp.currentEvent?.clickCount ?? 1
                    if !didMove, clickCount >= 2,
                       let id = pressHitID ?? model.hitTest(end, tolerance: tol) {
                        beginLabelEditing(id)
                    }
                    return
                }

                if model.tool != .pan,
                   [.point, .segment, .ray, .line, .circle, .polygon, .angle].contains(model.tool) {
                    let preview = model.smartSnappedPoint(start, tolerance: tol)
                    if preview.point.distance(to: start) > 1e-6 || !preview.guides.isEmpty {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                }

                if didMove {
                    if [.segment, .ray, .line].contains(model.tool) {
                        let tool = model.tool
                        model.perform("Draw \(tool.title)") {
                            model.draft = []
                            let a = model.ensurePoint(at: start, tolerance: tol)
                            var e = model.evaluator()
                            let anchor = e.evaluate(a).point
                            let b = model.ensurePoint(at: end, tolerance: tol, anchor: anchor)
                            guard a != b else {
                                return
                            }
                            let kind: ObjectKind = tool == .segment ? .segment(a: a, b: b)
                                : tool == .ray ? .ray(a: a, b: b) : .line(a: a, b: b)
                            var object = SketchObject(kind: kind)
                            object.order = (model.objects.map(\.order).max() ?? 0) + 1
                            model.objects.append(object)
                            model.selection = [object.id]
                            model.statusMessage = "\(tool.title) created"
                        }
                        return
                    }
                    if model.tool == .circle {
                        model.perform("Draw Circle") {
                            model.draft = []
                            let center = model.ensurePoint(at: start, tolerance: tol)
                            var e = model.evaluator()
                            let anchor = e.evaluate(center).point
                            let edge = model.ensurePoint(at: end, tolerance: tol, anchor: anchor)
                            guard center != edge else {
                                return
                            }
                            var object = SketchObject(kind: .circle(center: center, through: edge))
                            object.order = (model.objects.map(\.order).max() ?? 0) + 1
                            model.objects.append(object)
                            model.selection = [object.id]
                            model.statusMessage = "Circle created"
                        }
                        return
                    }
                }

                let now = Date()
                if model.tool == .polygon && now.timeIntervalSince(lastClickAt) < 0.3 && model.draft.count >= 3 {
                    model.finishPolygon()
                    lastClickAt = .distantPast
                    return
                }
                lastClickAt = now

                if model.tool == .text {
                    onTextAt(start)
                } else {
                    model.clickCanvas(at: start, tolerance: tol,
                                      additive: NSEvent.modifierFlags.contains(.shift))
                }
            }
    }

    func magnification(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if magnifyBase == nil {
                    magnifyBase = model.settings.scale
                }
                let scale = (magnifyBase ?? SketchMetrics.pixelsPerCentimetre) * value.magnification
                model.settings.scale = min(max(scale, 12), 420)
            }
            .onEnded { _ in
                magnifyBase = nil
            }
    }

    private func marqueeSelect(from: CGPoint, to: CGPoint, size: CGSize) {
        let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                          width: abs(to.x - from.x), height: abs(to.y - from.y))
        var e = model.evaluator()
        var hits: [UUID] = []
        for object in model.objects where object.visible {
            let r = e.evaluate(object.id)
            if let p = r.point {
                if rect.contains(model.screenPoint(p, size: size)) {
                    hits.append(object.id)
                    continue
                }
            }
            if let box = r.path?.boundingBox {
                let a = model.screenPoint(Vec2(box.minX, box.minY), size: size)
                let b = model.screenPoint(Vec2(box.maxX, box.maxY), size: size)
                let screenBox = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                       width: abs(a.x - b.x), height: abs(a.y - b.y))
                if rect.intersects(screenBox) {
                    hits.append(object.id)
                    continue
                }
            }
            if let anchor = r.anchor {
                if rect.contains(model.screenPoint(anchor, size: size)) {
                    hits.append(object.id)
                }
            }
        }
        if NSEvent.modifierFlags.contains(.shift) {
            for h in hits where !model.selection.contains(h) {
                model.selection.append(h)
            }
        } else {
            model.selection = hits
        }
        model.statusMessage = hits.isEmpty ? "" : "\(hits.count) selected"
    }

    private func selectionHandleHit(_ point: CGPoint, size: CGSize) -> SelectionHandleKind? {
        guard let box = model.movableSelectionBounds() else {
            return nil
        }
        let a = model.screenPoint(Vec2(box.minX, box.minY), size: size)
        let b = model.screenPoint(Vec2(box.maxX, box.maxY), size: size)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(b.x - a.x), height: abs(b.y - a.y))
        let rotate = CGPoint(x: rect.midX, y: rect.minY - 20)
        if hypot(point.x - rotate.x, point.y - rotate.y) <= 9 {
            return .rotate
        }
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        for (index, corner) in corners.enumerated()
        where hypot(point.x - corner.x, point.y - corner.y) <= 9 {
            return .scale(corner: index)
        }
        return nil
    }

    private func isLabelLike(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .caption, .angle, .parameter:
            return true
        default:
            return false
        }
    }

    private func isDrawingTool(_ tool: SketchTool) -> Bool {
        [.segment, .ray, .line, .circle, .polygon, .angle].contains(tool)
    }

    /// Captions and parameter cards move by their `position`; other cards move
    /// by their label `offset`.
    private func isPositionCard(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .caption, .parameter:
            return true
        default:
            return false
        }
    }

    private func isTransformedPoint(_ object: SketchObject) -> Bool {
        if case .transformed = object.kind {
            return model.evaluated(object.id).point != nil
        }
        return false
    }
}
