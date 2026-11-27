import SwiftUI
import AppKit

extension SketchCanvas {

    func drawGrid(context: inout GraphicsContext, size: CGSize, rect: WorldRect) {
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
            case .isometric:
                drawIsometricGrid(context: &context, size: size, rect: rect, step: step)
            }
        }

        if settings.axes {
            let labelStep: Double? = settings.gridType == .orthogonal || settings.gridType == .orthogonalDense
                ? step
                : nil
            drawAxes(context: &context, size: size, rect: rect, step: labelStep)
        }
    }

    func drawOrthogonalGrid(context: inout GraphicsContext, size: CGSize,
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
        let gridColor = palette.grid.color
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

    func drawTriangularGrid(context: inout GraphicsContext, size: CGSize,
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
        context.stroke(path, with: .color(palette.grid.color.opacity(model.settings.gridBold ? 0.16 : 0.08)),
                       lineWidth: model.settings.gridBold ? 1.0 : 0.7)
    }

    func drawIsometricGrid(context: inout GraphicsContext, size: CGSize,
                                   rect: WorldRect, step: Double) {
        let height = step * sqrt(3) / 2
        guard height > 0, height.isFinite else {
            return
        }
        var path = Path()
        let firstColumn = Int(floor(rect.minX / height)) - 1
        let lastColumn = Int(ceil(rect.maxX / height)) + 1
        for column in firstColumn...lastColumn {
            let x = Double(column) * height
            let a = model.screenPoint(Vec2(x, rect.minY), size: size)
            let b = model.screenPoint(Vec2(x, rect.maxY), size: size)
            path.move(to: a)
            path.addLine(to: b)
        }

        let slope = 1 / sqrt(3.0)
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
            var offset = floor(minOffset / step) * step
            while offset <= maxOffset + step {
                let a = model.screenPoint(Vec2(rect.minX, family * rect.minX + offset), size: size)
                let b = model.screenPoint(Vec2(rect.maxX, family * rect.maxX + offset), size: size)
                path.move(to: a)
                path.addLine(to: b)
                offset += step
            }
        }
        context.stroke(path, with: .color(palette.grid.color.opacity(model.settings.gridBold ? 0.16 : 0.08)),
                       lineWidth: model.settings.gridBold ? 1.0 : 0.7)
    }

    func drawPolarGrid(context: inout GraphicsContext, size: CGSize,
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
        context.stroke(path, with: .color(palette.grid.color.opacity(model.settings.gridBold ? 0.16 : 0.08)),
                       lineWidth: model.settings.gridBold ? 1.0 : 0.7)
    }

    func drawAxes(context: inout GraphicsContext, size: CGSize,
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
                        .foregroundStyle(palette.axisLabel.color)
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
                        .foregroundStyle(palette.axisLabel.color)
                    context.draw(label, at: CGPoint(x: min(max(p.x - 8, 10), size.width - 10), y: p.y),
                                 anchor: .trailing)
                }
            }
            y += step
        }
        if origin.x > 8 && origin.x < size.width - 8 && origin.y > 8 && origin.y < size.height - 8 {
            context.draw(Text("0")
                .font(font)
                .foregroundStyle(palette.axisLabel.color.opacity(0.9)),
                         at: CGPoint(x: origin.x - 7, y: origin.y + 7), anchor: .topTrailing)
        }
    }

    func axisLabelFont(_ style: AxisLabelStyle) -> Font {
        Font.system(.caption2,
                    design: style.serif ? .serif : .rounded,
                    weight: style.bold ? .bold : .regular)
    }

    func drawCoordinateSystems(context: inout GraphicsContext, size: CGSize) {
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
            let color = palette.resolve(object.style.color).color
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
}
