import SwiftUI

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

    func zoom(by factor: Double) {
        settings.scale = min(max(settings.scale * factor, 12), 420)
    }

    func setZoom(_ value: Double) {
        settings.scale = min(max(value, 12), 420)
    }

    func pan(dx: Double, dy: Double) {
        settings.center = settings.center - Vec2(dx / settings.scale, -dy / settings.scale)
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
        var box = WorldRect(minX: pts[0].x, minY: pts[0].y, maxX: pts[0].x, maxY: pts[0].y)
        for p in pts {
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
                // A polygon interior is a target too. routine uses the
                // winding-number rule for polygon hit testing.
                if path.contains(p) {
                    return object.id
                }
            }
            if let fill = e.evaluate(object.id).fill, fill.contains(p) {
                return object.id
            }
        }
        // Measurement / caption boxes.
        for object in objects.reversed() where object.visible {
            let r = e.evaluate(object.id)
            guard let text = r.text, let anchor = r.anchor else {
                continue
            }
            if textBounds(text: text, anchor: anchor).inset(-0.1).contains(p) {
                return object.id
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
