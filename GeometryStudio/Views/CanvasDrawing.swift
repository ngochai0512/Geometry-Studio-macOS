import SwiftUI
import AppKit

extension SketchCanvas {

    // MARK: drawing

    func draw(context: inout GraphicsContext, size: CGSize) {
        let rect = model.visibleRect(size: size)
        drawGrid(context: &context, size: size, rect: rect)
        drawCoordinateSystems(context: &context, size: size)
        drawTraces(context: &context, size: size)

        var e = model.evaluator()
        let ordered = model.objects.sorted { $0.order < $1.order }

        // Fills first: polygons, circles and filled arcs sit under the lines.
        for object in ordered where object.visible {
            let result = e.evaluate(object.id)
            if let fill = result.fill {
                drawFill(fill, style: object.style, context: &context, size: size)
                continue
            }
            guard let path = result.path else {
                continue
            }
            drawFill(path, style: object.style, context: &context, size: size)
        }

        // Paths.
        for object in ordered where object.visible {
            guard let path = e.evaluate(object.id).path else {
                continue
            }
            let selected = model.isSelected(object.id)
            if selected {
                stroke(path: path, style: object.style, selected: false, glow: true,
                       context: &context, size: size, rect: rect)
            }
            stroke(path: path, style: object.style, selected: selected, glow: false,
                   context: &context, size: size, rect: rect)
        }

        drawDraft(context: &context, size: size)
        drawVectors(context: &context, size: size, evaluator: &e)
        drawAngles(context: &context, size: size, evaluator: &e)
        drawPoints(context: &context, size: size, evaluator: &e)
        drawTexts(context: &context, size: size, evaluator: &e)
        drawParameters(context: &context, size: size)
        drawScaleBar(context: &context, size: size)

        if let ms = marqueeStart, let mc = marqueeCurrent {
            let r = CGRect(x: min(ms.x, mc.x), y: min(ms.y, mc.y),
                           width: abs(mc.x - ms.x), height: abs(mc.y - ms.y))
            context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(accent.opacity(0.08)))
            context.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(accent.opacity(0.7)), lineWidth: 1)
        }
    }

    private func drawFill(_ path: EvalPath, style: ObjectStyle,
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
            context.fill(fill, with: .color(style.color.color.opacity(style.fillOpacity)))
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
                         with: .color(style.color.color.opacity(style.fillOpacity * 0.7)))
        default:
            break
        }
    }

    private func drawTraces(context: inout GraphicsContext, size: CGSize) {
        for (id, points) in model.tracePaths where points.count > 1 {
            guard let object = model.objectByID(id), object.visible else {
                continue
            }
            var p = Path()
            p.move(to: model.screenPoint(points[0], size: size))
            for pt in points.dropFirst() {
                p.addLine(to: model.screenPoint(pt, size: size))
            }
            context.stroke(p, with: .color(object.style.color.color.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize, rect: WorldRect) {
        guard model.settings.grid || model.settings.axes else {
            return
        }
        guard rect.minX.isFinite, rect.maxX.isFinite,
              rect.minY.isFinite, rect.maxY.isFinite,
              rect.maxX > rect.minX, rect.maxY > rect.minY else {
            return
        }
        let settings = model.settings
        let step = GridMetrics.step(
            scale: settings.scale,
            perUnit: settings.lengthUnit.perUnit,
            minimumSpacing: settings.gridType == .orthogonalDense ? 24 : 50
        )
        guard step > 0, step.isFinite else {
            return
        }

        if settings.grid {
            switch settings.gridType {
            case .orthogonal, .orthogonalDense:
                drawOrthogonalGrid(context: &context, size: size, rect: rect, step: step)
            case .triangular:
                drawTriangularGrid(context: &context, size: size, rect: rect, step: step)
            case .polar:
                drawPolarGrid(context: &context, size: size, rect: rect, step: step)
            }
        }

        if settings.axes {
            let labelStep: Double? = settings.gridType == .orthogonal || settings.gridType == .orthogonalDense
                ? step
                : nil
            drawAxes(context: &context, size: size, rect: rect, step: labelStep)
        }
    }

    private func drawOrthogonalGrid(context: inout GraphicsContext, size: CGSize,
                                    rect: WorldRect, step: Double) {
        let startX = floor(rect.minX / step) * step
        let startY = floor(rect.minY / step) * step
        var minor = Path()
        var x = startX
        while x <= rect.maxX + step {
            let sx = model.screenPoint(Vec2(x, 0), size: size).x
            minor.move(to: CGPoint(x: sx, y: 0))
            minor.addLine(to: CGPoint(x: sx, y: size.height))
            x += step
        }
        var y = startY
        while y <= rect.maxY + step {
            let sy = model.screenPoint(Vec2(0, y), size: size).y
            minor.move(to: CGPoint(x: 0, y: sy))
            minor.addLine(to: CGPoint(x: size.width, y: sy))
            y += step
        }
        let gridColor = model.settings.gridColor.color
        let bold = model.settings.gridBold
        context.stroke(minor, with: .color(gridColor.opacity(bold ? 0.16 : 0.08)),
                       lineWidth: bold ? 1.0 : 0.7)

        var major = Path()
        let majorStep = step * 5
        var mx = floor(rect.minX / majorStep) * majorStep
        while mx <= rect.maxX + majorStep {
            let sx = model.screenPoint(Vec2(mx, 0), size: size).x
            major.move(to: CGPoint(x: sx, y: 0))
            major.addLine(to: CGPoint(x: sx, y: size.height))
            mx += majorStep
        }
        var my = floor(rect.minY / majorStep) * majorStep
        while my <= rect.maxY + majorStep {
            let sy = model.screenPoint(Vec2(0, my), size: size).y
            major.move(to: CGPoint(x: 0, y: sy))
            major.addLine(to: CGPoint(x: size.width, y: sy))
            my += majorStep
        }
        context.stroke(major, with: .color(gridColor.opacity(bold ? 0.28 : 0.14)),
                       lineWidth: bold ? 1.4 : 0.8)
    }

    private func drawTriangularGrid(context: inout GraphicsContext, size: CGSize,
                                    rect: WorldRect, step: Double) {
        let height = step * sqrt(3) / 2
        guard height > 0, height.isFinite else {
            return
        }
        var path = Path()
        let firstRow = Int(floor(rect.minY / height)) - 1
        let lastRow = Int(ceil(rect.maxY / height)) + 1
        for row in firstRow...lastRow {
            let y = Double(row) * height
            let a = model.screenPoint(Vec2(rect.minX, y), size: size)
            let b = model.screenPoint(Vec2(rect.maxX, y), size: size)
            path.move(to: a)
            path.addLine(to: b)
        }

        let slope = sqrt(3.0)
        let corners = [
            Vec2(rect.minX, rect.minY),
            Vec2(rect.minX, rect.maxY),
            Vec2(rect.maxX, rect.minY),
            Vec2(rect.maxX, rect.maxY)
        ]
        for family in [slope, -slope] {
            let offsets = corners.map { $0.y - family * $0.x }
            guard let minOffset = offsets.min(), let maxOffset = offsets.max() else {
                continue
            }
            let rootStep = 2 * height
            var offset = floor(minOffset / rootStep) * rootStep
            while offset <= maxOffset + rootStep {
                let a = model.screenPoint(Vec2(rect.minX, family * rect.minX + offset), size: size)
                let b = model.screenPoint(Vec2(rect.maxX, family * rect.maxX + offset), size: size)
                path.move(to: a)
                path.addLine(to: b)
                offset += rootStep
            }
        }
        context.stroke(path, with: .color(model.settings.gridColor.color.opacity(model.settings.gridBold ? 0.16 : 0.08)),
                       lineWidth: model.settings.gridBold ? 1.0 : 0.7)
    }

    private func drawPolarGrid(context: inout GraphicsContext, size: CGSize,
                               rect: WorldRect, step: Double) {
        let center = model.screenPoint(Vec2(0, 0), size: size)
        let corners = [
            Vec2(rect.minX, rect.minY),
            Vec2(rect.minX, rect.maxY),
            Vec2(rect.maxX, rect.minY),
            Vec2(rect.maxX, rect.maxY)
        ]
        let maxRadius = corners.map(\.length).max() ?? 0
        let minRadius = corners.map(\.length).min() ?? 0
        guard maxRadius > 0, maxRadius.isFinite else {
            return
        }
        let firstRing = max(1, Int(floor(minRadius / step)))
        let lastRing = max(firstRing, Int(ceil(maxRadius / step)))
        let span = lastRing - firstRing + 1
        let ringStride = max(1, Int(ceil(Double(span) / 240.0)))
        var path = Path()
        var ring = firstRing
        while ring <= lastRing {
            let radius = Double(ring) * step * model.settings.scale
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
            ring += ringStride
        }
        let spokeLength = maxRadius * model.settings.scale + 24
        for index in 0..<24 {
            let angle = Double(index) * .pi / 12
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + cos(angle) * spokeLength,
                                     y: center.y - sin(angle) * spokeLength))
        }
        context.stroke(path, with: .color(model.settings.gridColor.color.opacity(model.settings.gridBold ? 0.16 : 0.08)),
                       lineWidth: model.settings.gridBold ? 1.0 : 0.7)
    }

    private func drawAxes(context: inout GraphicsContext, size: CGSize,
                          rect: WorldRect, step: Double?) {
        let origin = model.screenPoint(Vec2(0, 0), size: size)
        var axes = Path()
        if origin.y >= 0 && origin.y <= size.height {
            axes.move(to: CGPoint(x: 0, y: origin.y))
            axes.addLine(to: CGPoint(x: size.width, y: origin.y))
        }
        if origin.x >= 0 && origin.x <= size.width {
            axes.move(to: CGPoint(x: origin.x, y: 0))
            axes.addLine(to: CGPoint(x: origin.x, y: size.height))
        }
        context.stroke(axes, with: .color(ink.opacity(0.3)), lineWidth: 1)

        guard let step, model.settings.axesLabels else {
            return
        }
        let labelStyle = model.settings.axesLabelStyle
        let font = axisLabelFont(labelStyle)
        let scale = model.settings.scale
        let unit = max(model.settings.lengthUnit.perUnit, 1e-6)
        let labelEvery = GridMetrics.labelEvery(step: step, scale: scale)
        var x = floor(rect.minX / step) * step
        while x <= rect.maxX + step {
            let index = Int((x / step).rounded())
            if index % labelEvery == 0 {
                let p = model.screenPoint(Vec2(x, 0), size: size)
                if abs(x) > 1e-9 && p.y >= 0 && p.y <= size.height {
                    let label = Text(GridMetrics.cleanNumber(x / unit))
                        .font(font)
                        .foregroundStyle(secondaryInk.opacity(0.8))
                    context.draw(label, at: CGPoint(x: p.x, y: min(max(p.y + 13, 12), size.height - 10)),
                                 anchor: .top)
                }
            }
            x += step
        }
        var y = floor(rect.minY / step) * step
        while y <= rect.maxY + step {
            let index = Int((y / step).rounded())
            if index % labelEvery == 0 {
                let p = model.screenPoint(Vec2(0, y), size: size)
                if abs(y) > 1e-9 && p.x >= 0 && p.x <= size.width {
                    let label = Text(GridMetrics.cleanNumber(y / unit))
                        .font(font)
                        .foregroundStyle(secondaryInk.opacity(0.8))
                    context.draw(label, at: CGPoint(x: min(max(p.x - 8, 10), size.width - 10), y: p.y),
                                 anchor: .trailing)
                }
            }
            y += step
        }
        if origin.x > 8 && origin.x < size.width - 8 && origin.y > 8 && origin.y < size.height - 8 {
            context.draw(Text("0")
                .font(font)
                .foregroundStyle(secondaryInk.opacity(0.75)),
                         at: CGPoint(x: origin.x - 7, y: origin.y + 7), anchor: .topTrailing)
        }
    }

    private func stroke(path: EvalPath, style: ObjectStyle, selected: Bool, glow: Bool,
                        context: inout GraphicsContext, size: CGSize, rect: WorldRect) {
        let color = glow ? accent : (selected ? accent : style.color.color)
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

    private func drawFunction(expression: String, style: ObjectStyle, selected: Bool, glow: Bool,
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
        let color = glow ? accent : (selected ? accent : style.color.color)
        context.stroke(final, with: .color(color.opacity(glow ? 0.2 : 1)),
                       style: StrokeStyle(lineWidth: glow ? style.lineWidth + 4 : style.lineWidth,
                                          lineCap: .round, lineJoin: .round))
    }

    private func drawCoordinateSystems(context: inout GraphicsContext, size: CGSize) {
        var e = model.evaluator()
        for object in model.objects where object.visible {
            guard case .coordinateSystem(let kind, let originID, let step, let unit) = object.kind,
                  let origin = e.point(originID), step > 0, step.isFinite else {
                continue
            }
            let stepPixels = step * model.settings.scale
            guard stepPixels >= 8, stepPixels < 4_000 else {
                continue
            }
            let color = object.style.color.color
            let center = model.screenPoint(origin, size: size)
            var path = Path()

            switch kind {
            case .cartesian:
                let horizontal = Int(size.width / CGFloat(stepPixels)) + 2
                let vertical = Int(size.height / CGFloat(stepPixels)) + 2
                for index in -horizontal...horizontal {
                    let x = center.x + CGFloat(index) * CGFloat(stepPixels)
                    guard x >= 0, x <= size.width else {
                        continue
                    }
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for index in -vertical...vertical {
                    let y = center.y + CGFloat(index) * CGFloat(stepPixels)
                    guard y >= 0, y <= size.height else {
                        continue
                    }
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }

            case .polar:
                let maxRadius = hypot(size.width, size.height)
                let rings = min(60, Int(maxRadius / CGFloat(stepPixels)) + 1)
                if rings > 0 {
                    for ring in 1...rings {
                        let radius = CGFloat(ring) * CGFloat(stepPixels)
                        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                                   width: radius * 2, height: radius * 2))
                    }
                }
                for index in 0..<24 {
                    let angle = Double(index) * .pi / 12
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * maxRadius,
                                             y: center.y - CGFloat(sin(angle)) * maxRadius))
                }
            }

            context.stroke(path, with: .color(color.opacity(0.08)), lineWidth: 0.7)

            var axes = Path()
            axes.move(to: CGPoint(x: 0, y: center.y))
            axes.addLine(to: CGPoint(x: size.width, y: center.y))
            axes.move(to: CGPoint(x: center.x, y: 0))
            axes.addLine(to: CGPoint(x: center.x, y: size.height))
            context.stroke(axes, with: .color(color.opacity(0.45)), lineWidth: 1)

            guard kind == .cartesian else {
                continue
            }
            let perUnit = max(unit.perUnit, 1e-6)
            let every = max(1, Int((55 / stepPixels).rounded(.up)))
            let horizontal = Int(size.width / CGFloat(stepPixels)) + 2
            let vertical = Int(size.height / CGFloat(stepPixels)) + 2
            let labelFont = Font.system(.caption2, design: .rounded)
            for index in stride(from: -horizontal, through: horizontal, by: every) where index != 0 {
                let x = center.x + CGFloat(index) * CGFloat(stepPixels)
                guard x >= 10, x <= size.width - 10 else {
                    continue
                }
                let text = Text(GridMetrics.cleanNumber(Double(index) * step / perUnit))
                    .font(labelFont)
                    .foregroundStyle(color.opacity(0.7))
                context.draw(text, at: CGPoint(x: x, y: min(max(center.y + 12, 10), size.height - 10)),
                             anchor: .top)
            }
            for index in stride(from: -vertical, through: vertical, by: every) where index != 0 {
                let y = center.y + CGFloat(index) * CGFloat(stepPixels)
                guard y >= 10, y <= size.height - 10 else {
                    continue
                }
                let text = Text(GridMetrics.cleanNumber(Double(index) * step / perUnit))
                    .font(labelFont)
                    .foregroundStyle(color.opacity(0.7))
                context.draw(text, at: CGPoint(x: min(max(center.x - 8, 10), size.width - 10), y: y),
                             anchor: .trailing)
            }
        }
    }

    private func drawVectors(context: inout GraphicsContext, size: CGSize,
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
            let head = 8.0
            var path = Path()
            path.move(to: to)
            path.addLine(to: CGPoint(x: to.x - CGFloat(cos(angle - 0.4) * head),
                                     y: to.y - CGFloat(sin(angle - 0.4) * head)))
            path.addLine(to: CGPoint(x: to.x - CGFloat(cos(angle + 0.4) * head),
                                     y: to.y - CGFloat(sin(angle + 0.4) * head)))
            path.closeSubpath()
            context.fill(path, with: .color(object.style.color.color))
        }
    }

    private func drawParameters(context: inout GraphicsContext, size: CGSize) {
        let precision = max(0, min(model.settings.precision, 6))
        for object in model.objects where object.visible {
            guard case .parameter(let value, let minimum, let maximum) = object.kind else {
                continue
            }
            let position = model.screenPoint(object.position ?? .zero, size: size)
            let name = object.label.isEmpty ? "x" : object.label
            let valueText = String(format: "%.\(precision)f", value)
            let text = Text("\(name) = \(valueText)")
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(object.style.color.color)
            let width: CGFloat = 128
            let height: CGFloat = 38
            let rect = CGRect(x: position.x - width / 2, y: position.y - height / 2,
                              width: width, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: 7),
                         with: .color(Color.white.opacity(0.92)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 7),
                           with: .color(model.isSelected(object.id) ? accent : ink.opacity(0.15)),
                           lineWidth: model.isSelected(object.id) ? 1.5 : 0.8)
            context.draw(text, at: CGPoint(x: rect.minX + 9, y: rect.minY + 7), anchor: .topLeading)

            let track = CGRect(x: rect.minX + 9, y: rect.maxY - 10,
                               width: rect.width - 18, height: 3)
            context.fill(Path(roundedRect: track, cornerRadius: 1.5),
                         with: .color(ink.opacity(0.15)))
            let span = max(maximum - minimum, 1e-9)
            let fraction = min(max((value - minimum) / span, 0), 1)
            let knob = track.minX + track.width * CGFloat(fraction)
            context.fill(Path(ellipseIn: CGRect(x: knob - 4, y: track.midY - 4,
                                                width: 8, height: 8)),
                         with: .color(accent))
        }
    }

    private func axisLabelFont(_ style: AxisLabelStyle) -> Font {
        var font = Font.system(.caption2,
                               design: style.serif ? .serif : .rounded,
                               weight: style.bold ? .bold : .regular)
        if style.italic {
            font = font.italic()
        }
        return font
    }

    private func drawTickMarks(_ a: Vec2, _ b: Vec2, count: Int, color: Color,
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

    private func drawAngles(context: inout GraphicsContext, size: CGSize, evaluator: inout GeometryEval) {
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
            let color = selected ? accent : object.style.color.color
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

    private func drawPoints(context: inout GraphicsContext, size: CGSize, evaluator: inout GeometryEval) {
        let ordered = model.objects.sorted { $0.order < $1.order }
        for object in ordered where object.visible {
            guard let p = evaluator.evaluate(object.id).point else {
                continue
            }
            let s = model.screenPoint(p, size: size)
            let selected = model.isSelected(object.id)
            let r = object.style.pointSize
            let color = selected ? accent : object.style.color.color

            if selected {
                let ring = CGRect(x: s.x - r - 4.5, y: s.y - r - 4.5,
                                  width: (r + 4.5) * 2, height: (r + 4.5) * 2)
                context.fill(Path(ellipseIn: ring), with: .color(accent.opacity(0.18)))
                context.stroke(Path(ellipseIn: ring), with: .color(accent.opacity(0.85)), lineWidth: 1.2)
            }

            // A small white halo keeps points legible where many objects meet.
            let halo = CGRect(x: s.x - r - 1.5, y: s.y - r - 1.5,
                              width: (r + 1.5) * 2, height: (r + 1.5) * 2)
            context.fill(Path(ellipseIn: halo), with: .color(Color.white.opacity(0.9)))

            switch object.style.pointShape {
            case .filled:
                let box = CGRect(x: s.x - r / 2, y: s.y - r / 2, width: r, height: r)
                context.fill(Path(ellipseIn: box), with: .color(color))
            case .hollow:
                let box = CGRect(x: s.x - r / 2, y: s.y - r / 2, width: r, height: r)
                context.fill(Path(ellipseIn: box), with: .color(Color.white))
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
                let text = Text(object.label)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(object.style.color.color.opacity(0.95))
                context.draw(text, at: CGPoint(x: s.x + 7, y: s.y - 7), anchor: .bottomLeading)
            }
        }
    }

    private func drawTexts(context: inout GraphicsContext, size: CGSize, evaluator: inout GeometryEval) {
        let ordered = model.objects.sorted { $0.order < $1.order }
        var occupied: [CGRect] = []
        for object in ordered where object.visible {
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
            if case .caption = object.kind {
                font = font.italic()
            }
            let fg = selected ? accent : (isCaption ? secondaryInk : object.style.color.color)
            let resolved = context.resolve(
                Text(text)
                    .font(font)
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
                             with: .color(Color.white.opacity(0.92)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 6),
                               with: .color(selected ? accent.opacity(0.75) : ink.opacity(0.10)),
                               lineWidth: selected ? 1.2 : 0.8)
            } else {
                context.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: 0), cornerRadius: 5),
                             with: .color(Color.white.opacity(0.55)))
            }
            context.draw(resolved, at: CGPoint(x: rect.minX + padX, y: rect.minY + padY),
                         anchor: .topLeading)
        }
    }

    private func drawDraft(context: inout GraphicsContext, size: CGSize) {
        guard !model.draft.isEmpty else {
            return
        }
        var e = model.evaluator()
        let pts = model.draft.compactMap { e.evaluate($0).point }
        guard !pts.isEmpty else {
            return
        }
        var p = Path()
        p.move(to: model.screenPoint(pts[0], size: size))
        for pt in pts.dropFirst() {
            p.addLine(to: model.screenPoint(pt, size: size))
        }
        if let hover = model.hoverWorld {
            p.addLine(to: model.screenPoint(hover, size: size))
        }
        context.stroke(p, with: .color(accent.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [6, 4]))

        if model.tool == .circle, let center = pts.first {
            let c = model.screenPoint(center, size: size)
            let edge = model.screenPoint(model.hoverWorld ?? center, size: size)
            let r = hypot(edge.x - c.x, edge.y - c.y)
            let box = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: box), with: .color(accent.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }

        if pts.count >= 3 && model.tool == .polygon {
            var fill = Path()
            fill.move(to: model.screenPoint(pts[0], size: size))
            for pt in pts.dropFirst() {
                fill.addLine(to: model.screenPoint(pt, size: size))
            }
            fill.closeSubpath()
            context.fill(fill, with: .color(accent.opacity(0.07)))
        }
    }

    private func drawScaleBar(context: inout GraphicsContext, size: CGSize) {
        // A quiet scale reference in the lower-left corner.
        let scale = model.settings.scale
        let unit = model.settings.lengthUnit
        let oneUnit = scale * unit.perUnit
        guard oneUnit > 0, oneUnit.isFinite else {
            return
        }
        let target = oneUnit
        var length = target
        while length < 46 {
            length *= 2
        }
        while length > 140 {
            length /= 2
        }
        let x: CGFloat = 18
        let y = size.height - 20
        var p = Path()
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x + length, y: y))
        p.move(to: CGPoint(x: x, y: y - 3))
        p.addLine(to: CGPoint(x: x, y: y + 3))
        p.move(to: CGPoint(x: x + length, y: y - 3))
        p.addLine(to: CGPoint(x: x + length, y: y + 3))
        context.stroke(p, with: .color(secondaryInk.opacity(0.5)), lineWidth: 1)
        let value = length / scale / unit.perUnit
        let label = Text("\(GridMetrics.cleanNumber(value)) \(unit.short)")
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(secondaryInk.opacity(0.65))
        context.draw(label, at: CGPoint(x: x, y: y - 6), anchor: .bottomLeading)
    }
}
