import SwiftUI
import AppKit

struct SketchCanvas: View {
    @ObservedObject var model: SketchModel
    var onTextAt: (Vec2) -> Void

    @State private var canvasSize: CGSize = .zero
    @State private var dragStartWorld: Vec2?
    @State private var dragStartScreen: CGPoint?
    @State private var dragPointID: UUID?
    @State private var dragLabelID: UUID?
    @State private var dragLabelBaseOffset: Vec2 = .zero
    @State private var dragLabelBasePosition: Vec2 = .zero
    @State private var dragLabelIsCaption = false
    @State private var didMove = false
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var magnifyBase: Double?
    @State private var lastClickAt: Date = .distantPast

    private var ink: Color { RGBA.ink.color }
    private var secondaryInk: Color { RGBA.secondaryInk.color }
    private var accent: Color { Color.accentColor }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                draw(context: &context, size: size)
            }
            .background(
                LinearGradient(colors: [Color(red: 0.995, green: 0.995, blue: 0.998),
                                        Color(red: 0.975, green: 0.977, blue: 0.985)],
                               startPoint: .top, endPoint: .bottom)
            )
            .contentShape(Rectangle())
            .gesture(dragGesture(size: geo.size))
            .simultaneousGesture(magnification(size: geo.size))
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    model.isPointerOverCanvas = true
                    model.hoverWorld = model.worldPoint(point, size: geo.size)
                case .ended:
                    model.isPointerOverCanvas = false
                    model.hoverWorld = nil
                }
            }
            .onAppear {
                canvasSize = geo.size
                if model.objects.isEmpty && model.settings.scale == SketchMetrics.pixelsPerCentimetre {
                    model.setZoom(SketchMetrics.pixelsPerCentimetre)
                }
            }
            .onChange(of: geo.size) { newValue in
                canvasSize = newValue
            }
            .accessibilityLabel("Geometry canvas")
        }
    }

    // MARK: gestures

    private func dragGesture(size: CGSize) -> some Gesture {
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

    private func magnification(size: CGSize) -> some Gesture {
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

    // MARK: drawing

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let rect = model.visibleRect(size: size)
        drawGrid(context: &context, size: size, rect: rect)
        drawTraces(context: &context, size: size)

        var e = model.evaluator()
        let ordered = model.objects.sorted { $0.order < $1.order }

        // Fills first: polygons and circles sit under the lines.
        for object in ordered where object.visible {
            guard let path = e.evaluate(object.id).path else { continue }
            switch path {
            case .polygon(let pts):
                guard pts.count >= 3 else { continue }
                var p = Path()
                p.move(to: model.screenPoint(pts[0], size: size))
                for pt in pts.dropFirst() { p.addLine(to: model.screenPoint(pt, size: size)) }
                p.closeSubpath()
                context.fill(p, with: .color(object.style.color.color.opacity(object.style.fillOpacity)))
            case .circle(let c, let r):
                let center = model.screenPoint(c, size: size)
                let rr = r * model.settings.scale
                let box = CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)
                context.fill(Path(ellipseIn: box),
                             with: .color(object.style.color.color.opacity(object.style.fillOpacity * 0.7)))
            default: break
            }
        }

        // Paths.
        for object in ordered where object.visible {
            guard let path = e.evaluate(object.id).path else { continue }
            let selected = model.isSelected(object.id)
            if selected {
                stroke(path: path, style: object.style, selected: false, glow: true,
                       context: &context, size: size, rect: rect)
            }
            stroke(path: path, style: object.style, selected: selected, glow: false,
                   context: &context, size: size, rect: rect)
        }

        drawDraft(context: &context, size: size)
        drawAngles(context: &context, size: size, evaluator: &e)
        drawPoints(context: &context, size: size, evaluator: &e)
        drawTexts(context: &context, size: size, evaluator: &e)
        drawScaleBar(context: &context, size: size)

        if let ms = marqueeStart, let mc = marqueeCurrent {
            let r = CGRect(x: min(ms.x, mc.x), y: min(ms.y, mc.y),
                           width: abs(mc.x - ms.x), height: abs(mc.y - ms.y))
            context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(accent.opacity(0.08)))
            context.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(accent.opacity(0.7)), lineWidth: 1)
        }
    }

    private func drawTraces(context: inout GraphicsContext, size: CGSize) {
        for (id, points) in model.tracePaths where points.count > 1 {
            guard let object = model.objectByID(id), object.visible else { continue }
            var p = Path()
            p.move(to: model.screenPoint(points[0], size: size))
            for pt in points.dropFirst() { p.addLine(to: model.screenPoint(pt, size: size)) }
            context.stroke(p, with: .color(object.style.color.color.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize, rect: WorldRect) {
        guard model.settings.grid || model.settings.axes else { return }
        let scale = model.settings.scale
        // The original's grid and axes are labelled in the chosen distance
        // unit, so a one-inch grid is one inch wide even though the sketch
        // stores centimetres. Convert the display-unit step to world units.
        let unit = max(model.settings.lengthUnit.perUnit, 1e-6)
        let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100]
        var displayStep = steps.last ?? 1
        for candidate in steps where candidate * unit * scale >= 50 {
            displayStep = candidate
            break
        }
        let step = displayStep * unit

        if model.settings.grid {
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
            context.stroke(minor, with: .color(ink.opacity(0.055)), lineWidth: 0.7)

            // Emphasised grid lines every five steps.
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
            context.stroke(major, with: .color(ink.opacity(0.09)), lineWidth: 0.8)
        }

        if model.settings.axes {
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

            let tickStep = step
            let labelEvery = tickStep * scale < 55 ? 5 : 1
            var x = floor(rect.minX / tickStep) * tickStep
            while x <= rect.maxX + tickStep {
                let index = Int((x / tickStep).rounded())
                if index % labelEvery == 0 {
                    let p = model.screenPoint(Vec2(x, 0), size: size)
                    if abs(x) > 1e-9 && p.y >= 0 && p.y <= size.height {
                        let label = Text(cleanNumber(x / unit))
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundColor(secondaryInk.opacity(0.8))
                        context.draw(label, at: CGPoint(x: p.x, y: min(max(p.y + 13, 12), size.height - 10)),
                                     anchor: .top)
                    }
                }
                x += tickStep
            }
            var yy = floor(rect.minY / tickStep) * tickStep
            while yy <= rect.maxY + tickStep {
                let index = Int((yy / tickStep).rounded())
                if index % labelEvery == 0 {
                    let p = model.screenPoint(Vec2(0, yy), size: size)
                    if abs(yy) > 1e-9 && p.x >= 0 && p.x <= size.width {
                        let label = Text(cleanNumber(yy / unit))
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundColor(secondaryInk.opacity(0.8))
                        context.draw(label, at: CGPoint(x: min(max(p.x - 8, 10), size.width - 10), y: p.y),
                                     anchor: .trailing)
                    }
                }
                yy += tickStep
            }
            if origin.x > 8 && origin.x < size.width - 8 && origin.y > 8 && origin.y < size.height - 8 {
                context.draw(Text("0")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(secondaryInk.opacity(0.75)),
                             at: CGPoint(x: origin.x - 7, y: origin.y + 7), anchor: .topTrailing)
            }
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
            guard rr.isFinite, rr < 200_000 else { return }
            let box = CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)
            context.stroke(Path(ellipseIn: box),
                           with: .color(color.opacity(glow ? 0.22 : 1)), style: strokeStyle)

        case .polygon(let pts):
            guard pts.count >= 2 else { return }
            var p = Path()
            p.move(to: model.screenPoint(pts[0], size: size))
            for pt in pts.dropFirst() { p.addLine(to: model.screenPoint(pt, size: size)) }
            p.closeSubpath()
            context.stroke(p, with: .color(color.opacity(glow ? 0.22 : 1)), style: strokeStyle)

        case .polyline(let pts):
            guard pts.count > 1 else { break }
            var p = Path()
            p.move(to: model.screenPoint(pts[0], size: size))
            for pt in pts.dropFirst() { p.addLine(to: model.screenPoint(pt, size: size)) }
            context.stroke(p, with: .color(color.opacity(glow ? 0.18 : 1)), style: strokeStyle)

        case .polyline(let pts):
            guard pts.count > 1 else { break }
            var p = Path()
            p.move(to: model.screenPoint(pts[0], size: size))
            for pt in pts.dropFirst() { p.addLine(to: model.screenPoint(pt, size: size)) }
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
        guard var p = parser else { return }
        let stepPx = 2.0
        let dx = stepPx / model.settings.scale
        var x = rect.minX
        var current: Path?
        var path = Path()
        var began = false
        var e = model.evaluator()
        _ = e
        while x <= rect.maxX {
            if let y = p.evaluate(x: x), y.isFinite, abs(y) < 1e7 {
                let pt = model.screenPoint(Vec2(x, y), size: size)
                if pt.y > -size.height * 2 && pt.y < size.height * 3 {
                    if !began {
                        path.move(to: pt); began = true
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
        guard let final = current else { return }
        let color = glow ? accent : (selected ? accent : style.color.color)
        context.stroke(final, with: .color(color.opacity(glow ? 0.2 : 1)),
                       style: StrokeStyle(lineWidth: glow ? style.lineWidth + 4 : style.lineWidth,
                                          lineCap: .round, lineJoin: .round))
    }

    private func drawAngles(context: inout GraphicsContext, size: CGSize, evaluator: inout GeometryEval) {
        let ordered = model.objects.sorted { $0.order < $1.order }
        for object in ordered where object.visible {
            let result = evaluator.evaluate(object.id)
            guard let (a, v, c) = result.anglePoints else { continue }
            let start = atan2(a.y - v.y, a.x - v.x)
            var delta = atan2(c.y - v.y, c.x - v.x) - start
            while delta > .pi { delta -= .pi * 2 }
            while delta < -.pi { delta += .pi * 2 }
            let radius = 0.62
            var arc = Path()
            for i in 0...30 {
                let t = Double(i) / 30.0
                let angle = start + delta * t
                let point = v + Vec2(cos(angle), sin(angle)) * radius
                let screen = model.screenPoint(point, size: size)
                if i == 0 { arc.move(to: screen) } else { arc.addLine(to: screen) }
            }
            let selected = model.isSelected(object.id)
            let color = selected ? accent : object.style.color.color
            context.stroke(arc, with: .color(color.opacity(0.9)),
                           style: StrokeStyle(lineWidth: selected ? 2 : 1.3, lineCap: .round))
        }
    }

    private func drawPoints(context: inout GraphicsContext, size: CGSize, evaluator: inout GeometryEval) {
        let ordered = model.objects.sorted { $0.order < $1.order }
        for object in ordered where object.visible {
            guard let p = evaluator.evaluate(object.id).point else { continue }
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
            }

            if object.showLabel && model.settings.showLabels && !object.label.isEmpty {
                let text = Text(object.label)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(object.style.color.color.opacity(0.95))
                context.draw(text, at: CGPoint(x: s.x + 7, y: s.y - 7), anchor: .bottomLeading)
            }
        }
    }

    private func drawTexts(context: inout GraphicsContext, size: CGSize, evaluator: inout GeometryEval) {
        let ordered = model.objects.sorted { $0.order < $1.order }
        for object in ordered where object.visible {
            let r = evaluator.evaluate(object.id)
            guard let text = r.text, let anchor = r.anchor else { continue }
            let selected = model.isSelected(object.id)
            let isCaption = {
                if case .caption = object.kind { return true }
                return false
            }()

            var font = Font.system(size: isCaption ? 13 : 12, weight: isCaption ? .medium : .medium, design: .rounded)
            if case .caption = object.kind { font = font.italic() }
            let fg = selected ? accent : (isCaption ? secondaryInk : object.style.color.color)
            let resolved = context.resolve(Text(text).font(font).foregroundColor(fg))
            let measured = resolved.measure(in: CGSize(width: 800, height: 200))
            let padX: CGFloat = isCaption ? 7 : 7
            let padY: CGFloat = isCaption ? 4 : 4
            let w = measured.width + padX * 2
            let h = measured.height + padY * 2
            let sp = model.screenPoint(anchor, size: size)
            let rect = CGRect(x: sp.x, y: sp.y - h, width: w, height: h)

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
        guard !model.draft.isEmpty else { return }
        var e = model.evaluator()
        let pts = model.draft.compactMap { e.evaluate($0).point }
        guard !pts.isEmpty else { return }
        var p = Path()
        p.move(to: model.screenPoint(pts[0], size: size))
        for pt in pts.dropFirst() { p.addLine(to: model.screenPoint(pt, size: size)) }
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
            for pt in pts.dropFirst() { fill.addLine(to: model.screenPoint(pt, size: size)) }
            fill.closeSubpath()
            context.fill(fill, with: .color(accent.opacity(0.07)))
        }
    }

    private func drawScaleBar(context: inout GraphicsContext, size: CGSize) {
        // A quiet scale reference in the lower-left corner.
        let scale = model.settings.scale
        let unit = model.settings.lengthUnit
        let oneUnit = scale * unit.perUnit
        let target = oneUnit
        var length = target
        while length < 46 { length *= 2 }
        while length > 140 { length /= 2 }
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
        let label = Text("\(cleanNumber(value)) \(unit.short)")
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundColor(secondaryInk.opacity(0.65))
        context.draw(label, at: CGPoint(x: x, y: y - 6), anchor: .bottomLeading)
    }

    private func cleanNumber(_ v: Double) -> String {
        if abs(v - v.rounded()) < 1e-9 { return String(Int(v.rounded())) }
        return String(format: "%.1f", v)
    }
}
