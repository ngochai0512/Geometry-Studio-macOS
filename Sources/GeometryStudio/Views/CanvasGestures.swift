import SwiftUI
import AppKit

extension SketchCanvas {

    // MARK: gestures

    func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let world = model.worldPoint(value.startLocation, size: size)
                let current = model.worldPoint(value.location, size: size)
                if dragStartScreen == nil {
                    dragStartScreen = value.startLocation
                    dragStartWorld = world
                    didMove = false

                    if model.tool == .select {
                        let tol = 9 / model.settings.scale
                        if let hit = model.hitTest(world, tolerance: tol), let object = model.objectByID(hit) {
                            if object.isPointLike || isTransformedPoint(object) {
                                if let draggable = model.beginDrag(at: world, tolerance: tol) {
                                    dragPointID = draggable
                                } else {
                                    model.select(hit, additive: NSEvent.modifierFlags.contains(.shift))
                                }
                            } else if isLabelLike(object) {
                                dragLabelID = hit
                                dragLabelBaseOffset = object.offset
                                dragLabelBasePosition = object.position ?? .zero
                                if case .caption = object.kind { dragLabelIsCaption = true } else { dragLabelIsCaption = false }
                                model.checkpoint()
                                model.select(hit, additive: NSEvent.modifierFlags.contains(.shift))
                            } else {
                                model.select(hit, additive: NSEvent.modifierFlags.contains(.shift))
                                marqueeStart = value.startLocation
                                marqueeCurrent = value.startLocation
                            }
                        } else {
                            marqueeStart = value.startLocation
                            marqueeCurrent = value.startLocation
                        }
                    }
                }

                if abs(value.translation.width) + abs(value.translation.height) > 2 {
                    didMove = true
                }

                if let id = dragPointID, didMove {
                    model.dragPoint(id, to: current)
                } else if let id = dragLabelID, didMove {
                    let total = Vec2((value.location.x - value.startLocation.x) / model.settings.scale,
                                     -(value.location.y - value.startLocation.y) / model.settings.scale)
                    if dragLabelIsCaption {
                        model.setCaptionPosition(id, dragLabelBasePosition + total)
                    } else {
                        model.setLabelOffset(id, dragLabelBaseOffset + total)
                    }
                } else if marqueeStart != nil {
                    marqueeCurrent = value.location
                }
            }
            .onEnded { value in
                defer {
                    dragStartScreen = nil
                    dragStartWorld = nil
                    dragPointID = nil
                    dragLabelID = nil
                    dragLabelIsCaption = false
                    didMove = false
                    marqueeStart = nil
                    marqueeCurrent = nil
                }
                let start = model.worldPoint(value.startLocation, size: size)
                let end = model.worldPoint(value.location, size: size)
                let tol = 9 / model.settings.scale

                if model.tool == .select {
                    if dragPointID == nil && dragLabelID == nil {
                        if didMove, let ms = marqueeStart, let mc = marqueeCurrent {
                            marqueeSelect(from: ms, to: mc, size: size)
                        } else {
                            model.clickCanvas(at: start,
                                              tolerance: tol,
                                              additive: NSEvent.modifierFlags.contains(.shift))
                        }
                    }
                    return
                }

                if didMove {
                    if [.segment, .ray, .line].contains(model.tool) {
                        model.draft = []
                        let a = model.ensurePoint(at: start, tolerance: tol)
                        let b = model.ensurePoint(at: end, tolerance: tol)
                        guard a != b else { return }
                        model.checkpoint()
                        let kind: ObjectKind = model.tool == .segment ? .segment(a: a, b: b)
                            : model.tool == .ray ? .ray(a: a, b: b) : .line(a: a, b: b)
                        var object = SketchObject(kind: kind)
                        object.order = (model.objects.map(\.order).max() ?? 0) + 1
                        model.objects.append(object)
                        model.selection = [object.id]
                        model.isDirty = true
                        model.statusMessage = "\(model.tool.title) created"
                        return
                    }
                    if model.tool == .circle {
                        model.draft = []
                        let center = model.ensurePoint(at: start, tolerance: tol)
                        let edge = model.ensurePoint(at: end, tolerance: tol)
                        guard center != edge else { return }
                        model.checkpoint()
                        var object = SketchObject(kind: .circle(center: center, through: edge))
                        object.order = (model.objects.map(\.order).max() ?? 0) + 1
                        model.objects.append(object)
                        model.selection = [object.id]
                        model.isDirty = true
                        model.statusMessage = "Circle created"
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
        MagnificationGesture()
            .onChanged { value in
                if magnifyBase == nil { magnifyBase = model.settings.scale }
                model.settings.scale = min(max((magnifyBase ?? SketchMetrics.pixelsPerCentimetre) * value, 12), 420)
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
                if rect.contains(model.screenPoint(p, size: size)) { hits.append(object.id); continue }
            }
            if let box = r.path?.boundingBox {
                let a = model.screenPoint(Vec2(box.minX, box.minY), size: size)
                let b = model.screenPoint(Vec2(box.maxX, box.maxY), size: size)
                let screenBox = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                       width: abs(a.x - b.x), height: abs(a.y - b.y))
                if rect.intersects(screenBox) { hits.append(object.id); continue }
            }
            if let anchor = r.anchor {
                if rect.contains(model.screenPoint(anchor, size: size)) { hits.append(object.id) }
            }
        }
        if NSEvent.modifierFlags.contains(.shift) {
            for h in hits where !model.selection.contains(h) { model.selection.append(h) }
        } else {
            model.selection = hits
        }
        model.statusMessage = hits.isEmpty ? "" : "\(hits.count) selected"
    }

    private func isLabelLike(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .caption, .angle: return true
        default: return false
        }
    }

    private func isTransformedPoint(_ object: SketchObject) -> Bool {
        if case .transformed = object.kind {
            return model.evaluated(object.id).point != nil
        }
        return false
    }
}
