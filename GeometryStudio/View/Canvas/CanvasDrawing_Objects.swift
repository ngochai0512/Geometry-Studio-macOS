import SwiftUI
import AppKit

extension SketchCanvas {

    func drawFill(_ path: EvalPath, style: ObjectStyle, alphaScale: Double = 1,
                          context: inout GraphicsContext, size: CGSize) {
        switch path {
        case .polygon(let points):
            guard points.count >= 3 else {
                return
            }
            var fill = Path()
            fill.move(to: model.screenPoint(points[0], size: size))
            for point in points.dropFirst() {
                fill.addLine(to: model.screenPoint(point, size: size))
            }
            fill.closeSubpath()
            context.fill(fill, with: .color(palette.resolve(style.color).color.opacity(style.fillOpacity * alphaScale)))
        case .circle(let center, let radius):
            let point = model.screenPoint(center, size: size)
            let scaledRadius = radius * model.settings.scale
            let box = CGRect(
                x: point.x - scaledRadius,
                y: point.y - scaledRadius,
                width: scaledRadius * 2,
                height: scaledRadius * 2
            )
            context.fill(Path(ellipseIn: box),
                         with: .color(palette.resolve(style.color).color.opacity(style.fillOpacity * alphaScale * 0.7)))
        default:
            break
        }
    }

    func drawTraces(context: inout GraphicsContext, size: CGSize) {
        for (id, points) in model.tracePaths where points.count > 1 {
            guard let object = model.objectByID(id), object.visible else {
                continue
            }
            var p = Path()
            p.move(to: model.screenPoint(points[0], size: size))
            for pt in points.dropFirst() {
                p.addLine(to: model.screenPoint(pt, size: size))
            }
            context.stroke(p, with: .color(palette.resolve(object.style.color).color.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        }
    }

    func stroke(path: EvalPath, style: ObjectStyle, selected: Bool, glow: Bool,
                        context: inout GraphicsContext, size: CGSize, rect: WorldRect) {
        let color = glow ? accent : (selected ? accent : palette.resolve(style.color).color)
        let width = glow ? style.lineWidth + 5 : (selected ? style.lineWidth + 1.2 : style.lineWidth)
        let dash: [CGFloat] = style.dash == .dashed ? [7, 4] : style.dash == .dotted ? [1.2, 3.5] : []
        let strokeStyle = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)

        switch path {
        case .segment(let a, let b):
            var p = Path()
            p.move(to: model.screenPoint(a, size: size))
            p.addLine(to: model.screenPoint(b, size: size))
            context.stroke(p, with: .color(color.opacity(glow ? 0.22 : 1)), style: strokeStyle)
            if !glow, style.tickCount > 0 {
                drawTickMarks(a, b, count: style.tickCount, color: color,
                              context: &context, size: size)
            }

        case .ray(let a, let b):
            let d = (b - a).normalized()
            let end = a + d * max(rect.width, rect.height) * 3
            if let (ca, cb) = clipLine(a, end, to: rect) {
                var p = Path()
                p.move(to: model.screenPoint(ca, size: size))
                p.addLine(to: model.screenPoint(cb, size: size))
                context.stroke(p, with: .color(color.opacity(glow ? 0.22 : 1)), style: strokeStyle)
            }

        case .line(let a, let b):
            let d = (b - a).normalized()
            let far = max(rect.width, rect.height) * 4
            if let (ca, cb) = clipLine(a - d * far, b + d * far, to: rect) {
                var p = Path()
                p.move(to: model.screenPoint(ca, size: size))
                p.addLine(to: model.screenPoint(cb, size: size))
                context.stroke(p, with: .color(color.opacity(glow ? 0.22 : 1)), style: strokeStyle)
            }

        case .circle(let c, let r):
            let center = model.screenPoint(c, size: size)
            let rr = r * model.settings.scale
            guard rr.isFinite, rr < 200_000 else {
                return
            }
            let box = CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)
            context.stroke(Path(ellipseIn: box),
                           with: .color(color.opacity(glow ? 0.22 : 1)), style: strokeStyle)

        case .arc(let c, let r, let start, let sweep):
            guard r.isFinite, r > 0 else {
                return
            }
            let steps = min(512, max(8, Int(abs(sweep) / (2 * Double.pi) * 180)))
            var p = Path()
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let angle = start + sweep * t
                let world = c + Vec2(cos(angle), sin(angle)) * r
                let point = model.screenPoint(world, size: size)
                if i == 0 {
                    p.move(to: point)
                } else {
                    p.addLine(to: point)
                }
            }
            context.stroke(p, with: .color(color.opacity(glow ? 0.22 : 1)), style: strokeStyle)

        case .polygon(let pts):
            guard pts.count >= 2 else {
                return
            }
            var p = Path()
            p.move(to: model.screenPoint(pts[0], size: size))
            for pt in pts.dropFirst() {
                p.addLine(to: model.screenPoint(pt, size: size))
            }
            p.closeSubpath()
            context.stroke(p, with: .color(color.opacity(glow ? 0.22 : 1)), style: strokeStyle)

        case .polyline(let pts):
            guard pts.count > 1 else {
                break
            }
            var p = Path()
            p.move(to: model.screenPoint(pts[0], size: size))
            for pt in pts.dropFirst() {
                p.addLine(to: model.screenPoint(pt, size: size))
            }
            context.stroke(p, with: .color(color.opacity(glow ? 0.18 : 1)), style: strokeStyle)

        case .functionPlot(let expression):
            drawFunction(expression: expression, style: style, selected: selected, glow: glow,
                         context: &context, size: size, rect: rect)
        }
    }

    func drawFunction(expression: String, style: ObjectStyle, selected: Bool, glow: Bool,
                              context: inout GraphicsContext, size: CGSize, rect: WorldRect) {
        var parser = Expression(expression)
        parser?.setAngleUnit(model.settings.angleUnit)
        guard var p = parser else {
            return
        }
        let stepPx = 2.0
        let dx = stepPx / model.settings.scale
        var x = rect.minX
        var current: Path?
        var path = Path()
        var began = false
        while x <= rect.maxX {
            if let y = p.evaluate(x: x), y.isFinite, abs(y) < 1e7 {
                let pt = model.screenPoint(Vec2(x, y), size: size)
                if pt.y > -size.height * 2 && pt.y < size.height * 3 {
                    if !began {
                        path.move(to: pt)
                        began = true
                    } else {
                        path.addLine(to: pt)
                    }
                } else {
                    began = false
                }
            } else {
                began = false
            }
            x += dx
        }
        current = path
        guard let final = current else {
            return
        }
        let color = glow ? accent : (selected ? accent : palette.resolve(style.color).color)
        context.stroke(final, with: .color(color.opacity(glow ? 0.2 : 1)),
                       style: StrokeStyle(lineWidth: glow ? style.lineWidth + 4 : style.lineWidth,
                                          lineCap: .round, lineJoin: .round))
    }

    func drawVectors(context: inout GraphicsContext, size: CGSize,
                             evaluator: inout GeometryEval) {
        for object in model.objects where object.visible {
            guard let arrow = evaluator.evaluate(object.id).arrow else {
                continue
            }
            let from = model.screenPoint(arrow.from, size: size)
            let to = model.screenPoint(arrow.to, size: size)
            let angle = atan2(Double(to.y - from.y), Double(to.x - from.x))
            let length = hypot(Double(to.x - from.x), Double(to.y - from.y))
            guard length > 1 else {
                continue
            }
            let head = SketchMetrics.arrowHeadLength(for: length)
            let spread = SketchMetrics.arrowHalfAngle
            var path = Path()
            path.move(to: to)
            path.addLine(to: CGPoint(x: to.x - CGFloat(cos(angle - spread) * head),
                                     y: to.y - CGFloat(sin(angle - spread) * head)))
            path.addLine(to: CGPoint(x: to.x - CGFloat(cos(angle + spread) * head),
                                     y: to.y - CGFloat(sin(angle + spread) * head)))
            path.closeSubpath()
            context.fill(path, with: .color(palette.resolve(object.style.color).color))
        }
    }

    func drawParameters(context: inout GraphicsContext, size: CGSize) {
        let precision = max(0, min(model.settings.precision, 6))
        for object in model.objects.sorted(by: { $0.order < $1.order })
        where object.visible && object.showLabel {
            guard case .parameter(let value, _, _) = object.kind else {
                continue
            }
            let position = model.screenPoint(object.position ?? .zero, size: size)
            let name = object.label.isEmpty ? "x" : object.label
            let valueText = String(format: "%.\(precision)f", value)
            let text = mathLabelText("\(name) = \(valueText)",
                                     base: .system(.callout, design: .rounded, weight: .semibold),
                                     script: .system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(palette.resolve(object.style.color).color)
            let width: CGFloat = 128
            let height: CGFloat = 38
            let rect = CGRect(x: position.x - width / 2, y: position.y - height / 2,
                              width: width, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: 7),
                         with: .color(palette.card.color))
            context.stroke(Path(roundedRect: rect, cornerRadius: 7),
                           with: .color(model.isSelected(object.id) ? accent : palette.cardBorder.color),
                           lineWidth: model.isSelected(object.id) ? 1.5 : 0.8)
            context.draw(text, at: CGPoint(x: rect.minX + 9, y: rect.minY + 7), anchor: .topLeading)
        }
    }

    func drawTickMarks(_ a: Vec2, _ b: Vec2, count: Int, color: Color,
                               context: inout GraphicsContext, size: CGSize) {
        let start = model.screenPoint(a, size: size)
        let end = model.screenPoint(b, size: size)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1 else {
            return
        }
        let ux = dx / length
        let uy = dy / length
        let half = min(5, max(3, length / 12))
        var ticks = Path()
        for index in 0..<max(0, min(count, 3)) {
            let t = Double(index + 1) / Double(count + 1)
            let center = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            ticks.move(to: CGPoint(x: center.x - uy * half, y: center.y + ux * half))
            ticks.addLine(to: CGPoint(x: center.x + uy * half, y: center.y - ux * half))
        }
        context.stroke(ticks, with: .color(color), lineWidth: 1.2)
    }

    func drawAngles(context: inout GraphicsContext, size: CGSize, evaluator: inout GeometryEval) {
        let ordered = model.objects.sorted { $0.order < $1.order }
        for object in ordered where object.visible {
            let result = evaluator.evaluate(object.id)
            guard let (a, v, c) = result.anglePoints else {
                continue
            }
            let start = atan2(a.y - v.y, a.x - v.x)
            var delta = atan2(c.y - v.y, c.x - v.x) - start
            while delta > .pi {
                delta -= .pi * 2
            }
            while delta < -.pi {
                delta += .pi * 2
            }
            let selected = model.isSelected(object.id)
            let color = selected ? accent : palette.resolve(object.style.color).color
            switch object.style.angleMarker {
            case .none:
                continue

            case .rightAngle:
                let markerSize = 0.22
                let first = v + Vec2(cos(start), sin(start)) * markerSize
                let second = v + Vec2(cos(start + delta), sin(start + delta)) * markerSize
                let corner = first + second - v
                var square = Path()
                square.move(to: model.screenPoint(v, size: size))
                square.addLine(to: model.screenPoint(first, size: size))
                square.addLine(to: model.screenPoint(corner, size: size))
                square.addLine(to: model.screenPoint(second, size: size))
                square.closeSubpath()
                context.stroke(square, with: .color(color.opacity(0.9)),
                               style: StrokeStyle(lineWidth: selected ? 2 : 1.3, lineCap: .round))

            case .arc, .doubleArc:
                let radii: [Double] = object.style.angleMarker == .doubleArc ? [0.62, 0.74] : [0.62]
                for radius in radii {
                    var arc = Path()
                    for i in 0...30 {
                        let t = Double(i) / 30.0
                        let angle = start + delta * t
                        let point = v + Vec2(cos(angle), sin(angle)) * radius
                        let screen = model.screenPoint(point, size: size)
                        if i == 0 {
                            arc.move(to: screen)
                        } else {
                            arc.addLine(to: screen)
                        }
                    }
                    context.stroke(arc, with: .color(color.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: selected ? 2 : 1.3, lineCap: .round))
                }
            }
        }
    }

    func drawPoints(context: inout GraphicsContext, size: CGSize, evaluator: inout GeometryEval) {
        let ordered = model.objects.sorted { $0.order < $1.order }
        for object in ordered where object.visible {
            guard let p = evaluator.evaluate(object.id).point else {
                continue
            }
            let s = model.screenPoint(p, size: size)
            let selected = model.isSelected(object.id)
            let r = object.style.pointSize
            let color = selected ? accent : palette.resolve(object.style.color).color

            if selected {
                let ring = CGRect(x: s.x - r - 4.5, y: s.y - r - 4.5,
                                  width: (r + 4.5) * 2, height: (r + 4.5) * 2)
                context.fill(Path(ellipseIn: ring), with: .color(accent.opacity(0.18)))
                context.stroke(Path(ellipseIn: ring), with: .color(accent.opacity(0.85)), lineWidth: 1.2)
            } else if object.id == hoveredObjectID {
                let ring = CGRect(x: s.x - r - 3, y: s.y - r - 3,
                                  width: (r + 3) * 2, height: (r + 3) * 2)
                context.stroke(Path(ellipseIn: ring),
                               with: .color(accent.opacity(0.4)),
                               lineWidth: 1)
            }

            // A small white halo keeps points legible where many objects meet.
            let halo = CGRect(x: s.x - r - 1.5, y: s.y - r - 1.5,
                              width: (r + 1.5) * 2, height: (r + 1.5) * 2)
            context.fill(Path(ellipseIn: halo), with: .color(palette.halo.color))

            switch object.style.pointShape {
            case .filled:
                let box = CGRect(x: s.x - r / 2, y: s.y - r / 2, width: r, height: r)
                context.fill(Path(ellipseIn: box), with: .color(color))
            case .hollow:
                let box = CGRect(x: s.x - r / 2, y: s.y - r / 2, width: r, height: r)
                context.fill(Path(ellipseIn: box), with: .color(palette.halo.color))
                context.stroke(Path(ellipseIn: box), with: .color(color), lineWidth: 1.5)
            case .square:
                let box = CGRect(x: s.x - r / 2, y: s.y - r / 2, width: r, height: r)
                context.fill(Path(roundedRect: box, cornerRadius: 0.8), with: .color(color))
            case .cross:
                var cross = Path()
                cross.move(to: CGPoint(x: s.x - r / 2, y: s.y - r / 2))
                cross.addLine(to: CGPoint(x: s.x + r / 2, y: s.y + r / 2))
                cross.move(to: CGPoint(x: s.x + r / 2, y: s.y - r / 2))
                cross.addLine(to: CGPoint(x: s.x - r / 2, y: s.y + r / 2))
                context.stroke(cross, with: .color(color), lineWidth: 1.5)
            case .diamond:
                var diamond = Path()
                diamond.move(to: CGPoint(x: s.x, y: s.y - r * 0.7))
                diamond.addLine(to: CGPoint(x: s.x + r * 0.7, y: s.y))
                diamond.addLine(to: CGPoint(x: s.x, y: s.y + r * 0.7))
                diamond.addLine(to: CGPoint(x: s.x - r * 0.7, y: s.y))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(color))
            case .triangle:
                var triangle = Path()
                triangle.move(to: CGPoint(x: s.x, y: s.y - r * 0.75))
                triangle.addLine(to: CGPoint(x: s.x + r * 0.7, y: s.y + r * 0.55))
                triangle.addLine(to: CGPoint(x: s.x - r * 0.7, y: s.y + r * 0.55))
                triangle.closeSubpath()
                context.fill(triangle, with: .color(color))
            }

            if object.showLabel && model.settings.showLabels && !object.label.isEmpty {
                let labelPoint = model.screenPoint(p + object.offset, size: size)
                // Selection is shown on the letter, not with a grip dot: a dot
                // at the point size reads as a second point once the label is
                // dragged away from its point.
                let text = mathLabelText(object.label,
                                         base: .system(.callout, design: .rounded, weight: .semibold),
                                         script: .system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(selected ? accent : palette.resolve(object.style.color).color.opacity(0.95))
                context.draw(text, at: CGPoint(x: labelPoint.x + 7, y: labelPoint.y - 7),
                             anchor: .bottomLeading)
            }
        }
    }

    func drawTexts(context: inout GraphicsContext, size: CGSize, evaluator: inout GeometryEval) {
        let ordered = model.objects.sorted { $0.order < $1.order }
        var occupied = pointLabelRects(context: &context, size: size)
        for object in ordered where object.visible && object.showLabel {
            if case .parameter = object.kind {
                continue
            }
            let r = evaluator.evaluate(object.id)
            guard let text = r.text, let anchor = r.anchor else {
                continue
            }
            let selected = model.isSelected(object.id)
            let isCaption = {
                if case .caption = object.kind {
                    return true
                }
                return false
            }()

            let style: Font.TextStyle = isCaption ? .body : .callout
            var font = Font.system(style, design: .rounded, weight: .medium)
            var scriptFont = Font.system(.caption2, design: .rounded, weight: .medium)
            if case .caption = object.kind {
                font = font.italic()
                scriptFont = scriptFont.italic()
            }
            let fg = selected ? accent : (isCaption ? secondaryInk : palette.resolve(object.style.color).color)
            let resolved = context.resolve(
                mathLabelText(text, base: font, script: scriptFont)
                    .foregroundStyle(fg)
            )
            let measured = resolved.measure(in: CGSize(width: 800, height: 200))
            let padX: CGFloat = isCaption ? 7 : 7
            let padY: CGFloat = isCaption ? 4 : 4
            let w = measured.width + padX * 2
            let h = measured.height + padY * 2
            let sp = model.screenPoint(anchor, size: size)
            var rect = CGRect(x: sp.x, y: sp.y - h, width: w, height: h)

            // Keep measure cards from covering each other. Twelve nudges is
            // enough for a dense sketch and keeps the loop bounded.
            var attempts = 0
            while attempts < 12, occupied.contains(where: {
                $0.insetBy(dx: -4, dy: -2).intersects(rect)
            }) {
                rect.origin.y += h + 4
                attempts += 1
            }
            occupied.append(rect)

            if !isCaption {
                context.fill(Path(roundedRect: rect, cornerRadius: 6),
                             with: .color(palette.card.color))
                let border = selected ? accent.opacity(0.75)
                    : (object.id == hoveredObjectID ? accent.opacity(0.45)
                       : palette.cardBorder.color)
                context.stroke(Path(roundedRect: rect, cornerRadius: 6),
                               with: .color(border),
                               lineWidth: selected || object.id == hoveredObjectID ? 1.2 : 0.8)
            } else {
                context.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: 0), cornerRadius: 5),
                             with: .color(palette.card.color.opacity(0.7)))
            }
            context.draw(resolved, at: CGPoint(x: rect.minX + padX, y: rect.minY + padY),
                         anchor: .topLeading)
            if selected {
                let grip = CGRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 5, height: 5)
                context.fill(Path(ellipseIn: grip), with: .color(accent.opacity(0.8)))
            }
        }
    }

    /// Renders label markup with math scripts at the requested fonts.
    func mathLabelText(_ source: String, base: Font, script: Font) -> Text {
        Text(MathLabel.attributed(source,
                                  base: base,
                                  script: script,
                                  superscriptOffset: 5,
                                  subscriptOffset: -2))
    }

    /// The point labels already drawn, so measure cards can step around them
    /// instead of covering a letter.
    func pointLabelRects(context: inout GraphicsContext,
                                 size: CGSize) -> [CGRect] {
        guard model.settings.showLabels else {
            return []
        }
        var rects: [CGRect] = []
        var evaluator = model.evaluator()
        for object in model.objects where object.visible && object.showLabel {
            guard !object.label.isEmpty,
                  let p = evaluator.evaluate(object.id).point else {
                continue
            }
            let labelPoint = model.screenPoint(p + object.offset, size: size)
            let resolved = context.resolve(
                mathLabelText(object.label,
                              base: .system(.callout, design: .rounded, weight: .semibold),
                              script: .system(.caption2, design: .rounded, weight: .semibold))
            )
            let measured = resolved.measure(in: CGSize(width: 400, height: 80))
            rects.append(CGRect(x: labelPoint.x + 7 - 2,
                                y: labelPoint.y - 7 - measured.height - 2,
                                width: measured.width + 4,
                                height: measured.height + 4))
        }
        return rects
    }
}
