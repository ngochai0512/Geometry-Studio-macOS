import Foundation

extension SVGExporter {
    // MARK: - Grid and scale bar

    func gridParts() -> [String] {
        guard settings.grid || settings.axes else {
            return []
        }
        let spacing = settings.gridType == .orthogonalDense ? 24.0 : 50.0
        let step = GridMetrics.step(scale: settings.scale,
                                    perUnit: settings.lengthUnit.perUnit,
                                    minimumSpacing: spacing)
        guard step > 0, step.isFinite else {
            return []
        }
        var parts: [String] = []

        if settings.grid {
            let gridColor = hex(settings.gridColor)
            let bold = settings.gridBold
            switch settings.gridType {
            case .orthogonal, .orthogonalDense:
                parts.append(element("path", [("d", gridLines(step: step)),
                                              ("fill", "none"),
                                              ("stroke", gridColor),
                                              ("stroke-opacity", bold ? "0.16" : "0.08"),
                                              ("stroke-width", bold ? "1" : "0.7")]))
                parts.append(element("path", [("d", gridLines(step: step * 5)),
                                              ("fill", "none"),
                                              ("stroke", gridColor),
                                              ("stroke-opacity", bold ? "0.28" : "0.14"),
                                              ("stroke-width", bold ? "1.4" : "0.8")]))
            case .triangular:
                parts.append(element("path", [("d", triangularGridPath(step: step)),
                                              ("fill", "none"),
                                              ("stroke", gridColor),
                                              ("stroke-opacity", bold ? "0.16" : "0.08"),
                                              ("stroke-width", bold ? "1" : "0.7")]))
            case .polar:
                parts.append(element("path", [("d", polarGridPath(step: step)),
                                              ("fill", "none"),
                                              ("stroke", gridColor),
                                              ("stroke-opacity", bold ? "0.16" : "0.08"),
                                              ("stroke-width", bold ? "1" : "0.7")]))
            case .isometric:
                parts.append(element("path", [("d", isometricGridPath(step: step)),
                                              ("fill", "none"),
                                              ("stroke", gridColor),
                                              ("stroke-opacity", bold ? "0.16" : "0.08"),
                                              ("stroke-width", bold ? "1" : "0.7")]))
            }
        }

        if settings.axes {
            let origin = screen(.zero)
            var d = ""
            if origin.y >= 0 && origin.y <= height {
                d += "M 0 \(num(origin.y)) L \(num(width)) \(num(origin.y)) "
            }
            if origin.x >= 0 && origin.x <= width {
                d += "M \(num(origin.x)) 0 L \(num(origin.x)) \(num(height)) "
            }
            if !d.isEmpty {
                parts.append(element("path", [("d", d), ("fill", "none"),
                                              ("stroke", hex(RGBA.ink)),
                                              ("stroke-opacity", "0.3"),
                                              ("stroke-width", "1")]))
            }
            if settings.axesLabels,
               settings.gridType == .orthogonal || settings.gridType == .orthogonalDense {
                parts.append(contentsOf: axisLabelParts(step: step, origin: origin))
            }
        }
        return parts
    }

    private func triangularGridPath(step: Double) -> String {
        let rect = visibleRect
        let height = step * sqrt(3) / 2
        guard height > 0, height.isFinite else {
            return ""
        }
        var d = ""
        let firstRow = Int(floor(rect.minY / height)) - 1
        let lastRow = Int(ceil(rect.maxY / height)) + 1
        for row in firstRow...lastRow {
            let y = Double(row) * height
            let a = screen(Vec2(rect.minX, y))
            let b = screen(Vec2(rect.maxX, y))
            d += "M \(num(a.x)) \(num(a.y)) L \(num(b.x)) \(num(b.y)) "
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
                let a = screen(Vec2(rect.minX, family * rect.minX + offset))
                let b = screen(Vec2(rect.maxX, family * rect.maxX + offset))
                d += "M \(num(a.x)) \(num(a.y)) L \(num(b.x)) \(num(b.y)) "
                offset += rootStep
            }
        }
        return d
    }

    private func isometricGridPath(step: Double) -> String {
        let rect = visibleRect
        let height = step * sqrt(3) / 2
        guard height > 0, height.isFinite else {
            return ""
        }
        var d = ""
        let firstColumn = Int(floor(rect.minX / height)) - 1
        let lastColumn = Int(ceil(rect.maxX / height)) + 1
        for column in firstColumn...lastColumn {
            let x = Double(column) * height
            let a = screen(Vec2(x, rect.minY))
            let b = screen(Vec2(x, rect.maxY))
            d += "M \(num(a.x)) \(num(a.y)) L \(num(b.x)) \(num(b.y)) "
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
                let a = screen(Vec2(rect.minX, family * rect.minX + offset))
                let b = screen(Vec2(rect.maxX, family * rect.maxX + offset))
                d += "M \(num(a.x)) \(num(a.y)) L \(num(b.x)) \(num(b.y)) "
                offset += step
            }
        }
        return d
    }

    private func polarGridPath(step: Double) -> String {
        let rect = visibleRect
        let center = screen(.zero)
        let corners = [
            Vec2(rect.minX, rect.minY),
            Vec2(rect.minX, rect.maxY),
            Vec2(rect.maxX, rect.minY),
            Vec2(rect.maxX, rect.maxY)
        ]
        let maxRadius = corners.map(\.length).max() ?? 0
        let minRadius = corners.map(\.length).min() ?? 0
        guard maxRadius > 0, maxRadius.isFinite else {
            return ""
        }
        let firstRing = max(1, Int(floor(minRadius / step)))
        let lastRing = max(firstRing, Int(ceil(maxRadius / step)))
        let span = lastRing - firstRing + 1
        let ringStride = max(1, Int(ceil(Double(span) / 240.0)))
        var d = ""
        var ring = firstRing
        while ring <= lastRing {
            let radius = Double(ring) * step * settings.scale
            d += "M \(num(center.x - radius)) \(num(center.y)) "
            d += "A \(num(radius)) \(num(radius)) 0 1 0 \(num(center.x + radius)) \(num(center.y)) "
            d += "A \(num(radius)) \(num(radius)) 0 1 0 \(num(center.x - radius)) \(num(center.y)) "
            ring += ringStride
        }
        let spokeLength = maxRadius * settings.scale + 24
        for index in 0..<24 {
            let angle = Double(index) * .pi / 12
            d += "M \(num(center.x)) \(num(center.y)) L "
            d += "\(num(center.x + cos(angle) * spokeLength)) \(num(center.y - sin(angle) * spokeLength)) "
        }
        return d
    }

    private func gridLines(step: Double) -> String {
        let rect = visibleRect
        var d = ""
        var x = floor(rect.minX / step) * step
        while x <= rect.maxX + step {
            let sx = screen(Vec2(x, 0)).x
            d += "M \(num(sx)) 0 L \(num(sx)) \(num(height)) "
            x += step
        }
        var y = floor(rect.minY / step) * step
        while y <= rect.maxY + step {
            let sy = screen(Vec2(0, y)).y
            d += "M 0 \(num(sy)) L \(num(width)) \(num(sy)) "
            y += step
        }
        return d
    }

    private func axisLabelParts(step: Double, origin: (x: Double, y: Double)) -> [String] {
        let unit = max(settings.lengthUnit.perUnit, 1e-6)
        let labelEvery = GridMetrics.labelEvery(step: step, scale: settings.scale)
        let attributes: [(String, String)] = [
            ("font-family", settings.axesLabelStyle.serif
                ? "Georgia, 'Times New Roman', serif"
                : svgFontFamily),
            ("font-size", "10"),
            ("font-weight", settings.axesLabelStyle.bold ? "700" : "400"),
            ("fill", hex(RGBA.secondaryInk)),
            ("fill-opacity", "0.8")
        ]
        let rect = visibleRect
        var parts: [String] = []

        var x = floor(rect.minX / step) * step
        while x <= rect.maxX + step {
            let index = Int((x / step).rounded())
            if index % labelEvery == 0 && abs(x) > 1e-9 {
                let p = screen(Vec2(x, 0))
                if p.y >= 0 && p.y <= height {
                    let top = min(max(p.y + 13, 12), height - 10)
                    parts.append(element("text", [("x", num(p.x)), ("y", num(top + 10)),
                                                  ("text-anchor", "middle")] + attributes,
                                         text: GridMetrics.cleanNumber(x / unit)))
                }
            }
            x += step
        }

        var y = floor(rect.minY / step) * step
        while y <= rect.maxY + step {
            let index = Int((y / step).rounded())
            if index % labelEvery == 0 && abs(y) > 1e-9 {
                let p = screen(Vec2(0, y))
                if p.x >= 0 && p.x <= width {
                    let right = min(max(p.x - 8, 10), width - 10)
                    parts.append(element("text", [("x", num(right)), ("y", num(p.y + 3.5)),
                                                  ("text-anchor", "end")] + attributes,
                                         text: GridMetrics.cleanNumber(y / unit)))
                }
            }
            y += step
        }

        let clamp = 8.0
        if origin.x > clamp && origin.x < width - clamp
            && origin.y > clamp && origin.y < height - clamp {
            parts.append(element("text", [("x", num(origin.x - 7)), ("y", num(origin.y + 17)),
                                          ("text-anchor", "end")] + attributes, text: "0"))
        }
        return parts
    }

    func scaleBarElement() -> String? {
        let unit = settings.lengthUnit
        let oneUnit = settings.scale * unit.perUnit
        guard oneUnit > 0, oneUnit.isFinite else {
            return nil
        }
        var length = oneUnit
        while length < SVGMetrics.scaleBarMinimum {
            length *= 2
        }
        while length > SVGMetrics.scaleBarMaximum {
            length /= 2
        }
        let x = 18.0
        let y = height - 20
        let d = "M \(num(x)) \(num(y)) L \(num(x + length)) \(num(y)) "
            + "M \(num(x)) \(num(y - 3)) L \(num(x)) \(num(y + 3)) "
            + "M \(num(x + length)) \(num(y - 3)) L \(num(x + length)) \(num(y + 3))"
        let value = length / settings.scale / unit.perUnit
        let label = element("text", [("x", num(x)), ("y", num(y - 8.5)),
                                     ("font-family", svgFontFamily),
                                     ("font-size", "9.5"),
                                     ("font-weight", "500"),
                                     ("fill", hex(RGBA.secondaryInk)),
                                     ("fill-opacity", "0.65")],
                            text: "\(GridMetrics.cleanNumber(value)) \(unit.short)")
        return element("path", [("d", d), ("fill", "none"),
                                ("stroke", hex(RGBA.secondaryInk)),
                                ("stroke-opacity", "0.5"),
                                ("stroke-width", "1")]) + "\n" + label
    }
}
