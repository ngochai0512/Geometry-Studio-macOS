import AppKit
import Foundation

extension SVGExporter {
    // MARK: - Object elements

    func fillElement(_ path: EvalPath, style: ObjectStyle) -> String? {
        switch path {
        case .polygon(let points):
            guard points.count >= 3 else {
                return nil
            }
            return element("polygon", [("points", pointList(points)),
                                       ("fill", hex(style.color)),
                                       ("fill-opacity", opacity(style.fillOpacity))])
        case .circle(let center, let radius):
            return worldCircleElement(center: center, radius: radius, attributes: [
                ("fill", hex(style.color)),
                ("fill-opacity", opacity(style.fillOpacity * SVGMetrics.circleFillOpacity))
            ])
        default:
            return nil
        }
    }

    func strokeElement(_ path: EvalPath, style: ObjectStyle) -> String? {
        let stroke = strokeAttributes(style)
        switch path {
        case .segment(let a, let b):
            return lineElement(a, b, attributes: stroke)
        case .ray(let a, let b):
            let direction = (b - a).normalized()
            let end = a + direction * max(visibleRect.width, visibleRect.height) * 3
            guard let (ca, cb) = clipLine(a, end, to: visibleRect) else {
                return nil
            }
            return lineElement(ca, cb, attributes: stroke)
        case .line(let a, let b):
            let direction = (b - a).normalized()
            let far = max(visibleRect.width, visibleRect.height) * 4
            guard let (ca, cb) = clipLine(a - direction * far, b + direction * far,
                                          to: visibleRect) else {
                return nil
            }
            return lineElement(ca, cb, attributes: stroke)
        case .circle(let center, let radius):
            return worldCircleElement(center: center, radius: radius,
                                      attributes: [("fill", "none")] + stroke)
        case .arc(let center, let radius, let start, let sweep):
            let r = radius * settings.scale
            guard r.isFinite, r > 0 else {
                return nil
            }
            let startPoint = screen(center + Vec2(cos(start), sin(start)) * radius)
            let endPoint = screen(center + Vec2(cos(start + sweep), sin(start + sweep)) * radius)
            let largeArc = abs(sweep) > .pi ? 1 : 0
            // Screen y is flipped, so a positive world sweep is SVG sweep 0.
            let sweepFlag = sweep >= 0 ? 0 : 1
            let d = "M \(num(startPoint.x)) \(num(startPoint.y)) "
                + "A \(num(r)) \(num(r)) 0 \(largeArc) \(sweepFlag) "
                + "\(num(endPoint.x)) \(num(endPoint.y))"
            return element("path", [("d", d), ("fill", "none")] + stroke)
        case .polygon(let points):
            guard points.count >= 2 else {
                return nil
            }
            return element("polygon", [("points", pointList(points)), ("fill", "none")] + stroke)
        case .polyline(let points):
            guard points.count > 1 else {
                return nil
            }
            return element("polyline", [("points", pointList(points)), ("fill", "none")] + stroke)
        case .functionPlot(let expression):
            guard let d = functionPath(expression) else {
                return nil
            }
            return element("path", [("d", d), ("fill", "none")] + stroke)
        }
    }

    private func lineElement(_ a: Vec2, _ b: Vec2,
                             attributes: [(String, String)]) -> String {
        let p = screen(a)
        let q = screen(b)
        return element("line", [("x1", num(p.x)), ("y1", num(p.y)),
                                ("x2", num(q.x)), ("y2", num(q.y))] + attributes)
    }

    /// A scaled world circle, capped so a damaged document cannot emit an
    /// enormous radius into the SVG.
    private func worldCircleElement(center: Vec2, radius: Double,
                                    attributes: [(String, String)]) -> String? {
        let p = screen(center)
        let r = radius * settings.scale
        guard r.isFinite, r < SVGMetrics.maximumCircleRadius else {
            return nil
        }
        return element("circle", [("cx", num(p.x)), ("cy", num(p.y)), ("r", num(r))] + attributes)
    }

    func angleElement(_ object: SketchObject, result: EvalResult) -> String? {
        guard let (a, vertex, c) = result.anglePoints else {
            return nil
        }
        let start = atan2(a.y - vertex.y, a.x - vertex.x)
        var delta = atan2(c.y - vertex.y, c.x - vertex.x) - start
        while delta > .pi {
            delta -= .pi * 2
        }
        while delta < -.pi {
            delta += .pi * 2
        }
        let radius = SVGMetrics.angleRadius
        var points: [Vec2] = []
        for i in 0...SVGMetrics.angleSamples {
            let t = Double(i) / Double(SVGMetrics.angleSamples)
            let angle = start + delta * t
            points.append(vertex + Vec2(cos(angle), sin(angle)) * radius)
        }
        return element("polyline", [("points", pointList(points)), ("fill", "none"),
                                    ("stroke-opacity", "0.9")]
                       + strokeAttributes(object.style, width: SVGMetrics.angleLineWidth))
    }

    func pointElements(_ object: SketchObject, at position: Vec2) -> [String] {
        let p = screen(position)
        let r = object.style.pointSize
        let color = hex(object.style.color)
        var parts: [String] = [pointHaloElement(at: p, radius: r)]
        parts.append(pointShapeElement(object.style.pointShape, at: p, radius: r, color: color))

        if object.showLabel && settings.showLabels && !object.label.isEmpty {
            parts.append(element("text", [("x", num(p.x + 7)), ("y", num(p.y - 10)),
                                          ("font-family", svgFontFamily), ("font-size", "12.5"),
                                          ("font-weight", "600"), ("fill", color),
                                          ("fill-opacity", "0.95")],
                                 text: object.label))
        }
        return parts
    }

    private func pointHaloElement(at p: (x: Double, y: Double), radius: Double) -> String {
        screenCircleElement(at: p, radius: radius + SVGMetrics.pointHaloPadding, attributes: [
            ("fill", "#ffffff"),
            ("fill-opacity", "0.9")
        ])
    }

    private func pointShapeElement(_ shape: PointShape, at p: (x: Double, y: Double),
                                   radius: Double, color: String) -> String {
        switch shape {
        case .filled:
            return screenCircleElement(at: p, radius: radius / 2, attributes: [("fill", color)])
        case .hollow:
            return screenCircleElement(at: p, radius: radius / 2, attributes: [
                ("fill", "#ffffff"),
                ("stroke", color),
                ("stroke-width", "1.5")
            ])
        case .square:
            return element("rect", [("x", num(p.x - radius / 2)),
                                    ("y", num(p.y - radius / 2)),
                                    ("width", num(radius)),
                                    ("height", num(radius)),
                                    ("rx", "0.8"),
                                    ("fill", color)])
        case .cross:
            let half = radius / 2
            let d = "M \(num(p.x - half)) \(num(p.y - half)) "
                + "L \(num(p.x + half)) \(num(p.y + half)) "
                + "M \(num(p.x + half)) \(num(p.y - half)) "
                + "L \(num(p.x - half)) \(num(p.y + half))"
            return element("path", [("d", d), ("fill", "none"), ("stroke", color),
                                    ("stroke-width", "1.5"), ("stroke-linecap", "round")])
        }
    }

    private func screenCircleElement(at p: (x: Double, y: Double), radius: Double,
                                     attributes: [(String, String)]) -> String {
        element("circle", [("cx", num(p.x)), ("cy", num(p.y)), ("r", num(radius))] + attributes)
    }

    func textElement(_ object: SketchObject, result: EvalResult) -> String? {
        guard let text = result.text, !text.isEmpty, let anchor = result.anchor else {
            return nil
        }
        let isCaption: Bool
        if case .caption = object.kind {
            isCaption = true
        } else {
            isCaption = false
        }

        let fontSize = isCaption ? 13.0 : 12.0
        let metrics = textMetrics(text, size: fontSize, italic: isCaption)
        let padX = 7.0
        let padY = 4.0
        let boxWidth = metrics.width + padX * 2
        let boxHeight = metrics.height + padY * 2
        let origin = screen(anchor)
        let minX = origin.x
        let minY = origin.y - boxHeight
        let background = textBackgroundElement(isCaption: isCaption, minX: minX, minY: minY,
                                               width: boxWidth, height: boxHeight)
        let attributes = textAttributes(isCaption: isCaption, object: object, minX: minX,
                                        minY: minY, padX: padX, padY: padY,
                                        fontSize: fontSize, metrics: metrics)
        return [background, element("text", attributes, text: text)].joined(separator: "\n")
    }

    private func textBackgroundElement(isCaption: Bool, minX: Double, minY: Double,
                                       width: Double, height: Double) -> String {
        if isCaption {
            return element("rect", [("x", num(minX - 2)), ("y", num(minY)),
                                    ("width", num(width + 4)),
                                    ("height", num(height)),
                                    ("rx", "5"), ("fill", "#ffffff"),
                                    ("fill-opacity", "0.55")])
        }
        return element("rect", [("x", num(minX)), ("y", num(minY)),
                                ("width", num(width)),
                                ("height", num(height)),
                                ("rx", "6"), ("fill", "#ffffff"),
                                ("fill-opacity", "0.92"),
                                ("stroke", hex(RGBA.ink)),
                                ("stroke-opacity", "0.10"),
                                ("stroke-width", "0.8")])
    }

    private func textAttributes(isCaption: Bool, object: SketchObject, minX: Double,
                                minY: Double, padX: Double, padY: Double, fontSize: Double,
                                metrics: (width: Double, height: Double, ascent: Double))
        -> [(String, String)] {
        var attributes: [(String, String)] = [
            ("x", num(minX + padX)),
            ("y", num(minY + padY + metrics.ascent)),
            ("font-family", svgFontFamily),
            ("font-size", num(fontSize)),
            ("font-weight", "500"),
            ("fill", isCaption ? hex(RGBA.secondaryInk) : hex(object.style.color))
        ]
        if isCaption {
            attributes.append(("font-style", "italic"))
        }
        return attributes
    }

    // MARK: - Function plots

    private func functionPath(_ expression: String) -> String? {
        guard var parser = Expression(expression) else {
            return nil
        }
        parser.setAngleUnit(settings.angleUnit)
        let rect = visibleRect
        let dx = 2.0 / settings.scale
        var x = rect.minX
        var began = false
        var d = ""
        while x <= rect.maxX {
            if let y = parser.evaluate(x: x), y.isFinite, abs(y) < 1e7 {
                let p = screen(Vec2(x, y))
                if p.y > -height * 2 && p.y < height * 3 {
                    d += began ? " L \(num(p.x)) \(num(p.y))" : "M \(num(p.x)) \(num(p.y))"
                    began = true
                } else {
                    began = false
                }
            } else {
                began = false
            }
            x += dx
        }
        return d.isEmpty ? nil : d
    }

    // MARK: - Text metrics

    private func textMetrics(_ text: String, size: Double,
                             italic: Bool) -> (width: Double, height: Double, ascent: Double) {
        var font = NSFont.systemFont(ofSize: size, weight: .medium)
        if italic {
            let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
            font = NSFont(descriptor: descriptor, size: size) ?? font
        }
        let measured = (text as NSString).size(withAttributes: [.font: font])
        return (Double(measured.width.rounded(.up)),
                Double(measured.height.rounded(.up)),
                Double(font.ascender))
    }
}
