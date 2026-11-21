import Foundation

extension SVGExporter {
    // MARK: - Grid and scale bar

    func gridParts() -> [String] {
        guard settings.grid || settings.axes else {
            return []
        }
        let step = GridMetrics.step(scale: settings.scale,
                                    perUnit: settings.lengthUnit.perUnit)
        guard step > 0, step.isFinite else {
            return []
        }
        var parts: [String] = []

        if settings.grid {
            parts.append(element("path", [("d", gridLines(step: step)),
                                          ("fill", "none"),
                                          ("stroke", hex(RGBA.ink)),
                                          ("stroke-opacity", "0.055"),
                                          ("stroke-width", "0.7")]))
            parts.append(element("path", [("d", gridLines(step: step * 5)),
                                          ("fill", "none"),
                                          ("stroke", hex(RGBA.ink)),
                                          ("stroke-opacity", "0.09"),
                                          ("stroke-width", "0.8")]))
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
            parts.append(contentsOf: axisLabelParts(step: step, origin: origin))
        }
        return parts
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
            ("font-family", svgFontFamily),
            ("font-size", "10"),
            ("font-weight", "400"),
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
