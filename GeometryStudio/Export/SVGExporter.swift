import AppKit
import Foundation

private let svgFontFamily = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif"

/// Writes a sketch as SVG.
///
/// The canvas draws with SwiftUI; this mirrors its order and constants so a
/// vector export matches the page the print path produces: white background,
/// no selection, draft, hover or traces.
struct SVGExporter {
    var objects: [SketchObject]
    var settings: CanvasSettings
    var size: CGSize
    var title: String = ""

    func svg() -> String {
        var parts: [String] = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
        parts.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(num(width))\" "
                     + "height=\"\(num(height))\" viewBox=\"0 0 \(num(width)) \(num(height))\">")
        if !title.isEmpty {
            parts.append("<title>\(escape(title))</title>")
        }
        parts.append(element("rect", [("width", "100%"), ("height", "100%"), ("fill", "#ffffff")]))
        // A hand-edited or damaged document can hold a zero scale; drawing the
        // grid would divide by zero, so only the page is written.
        if isRenderable {
            parts.append("<g id=\"grid\">")
            parts.append(contentsOf: gridParts())
            parts.append("</g>")
            parts.append("<g id=\"objects\">")
            parts.append(contentsOf: objectParts())
            parts.append("</g>")
        }
        parts.append("</svg>")
        return parts.joined(separator: "\n")
    }

    private var isRenderable: Bool {
        width > 1 && height > 1 && settings.scale.isFinite && settings.scale > 0
    }

    // MARK: objects

    private func objectParts() -> [String] {
        var evaluator = GeometryEval(objects: objects, settings: settings)
        let ordered = objects.sorted { $0.order < $1.order }
        var parts: [String] = []

        // Fills sit under the lines, as on the canvas.
        for object in ordered where object.visible {
            guard let path = evaluator.evaluate(object.id).path,
                  let fill = fillElement(path, style: object.style) else {
                continue
            }
            parts.append(fill)
        }
        for object in ordered where object.visible {
            guard let path = evaluator.evaluate(object.id).path,
                  let stroke = strokeElement(path, style: object.style) else {
                continue
            }
            parts.append(stroke)
        }
        for object in ordered where object.visible {
            if let arc = angleElement(object, result: evaluator.evaluate(object.id)) {
                parts.append(arc)
            }
        }
        for object in ordered where object.visible {
            if let point = evaluator.evaluate(object.id).point {
                parts.append(contentsOf: pointElements(object, at: point))
            }
        }
        for object in ordered where object.visible {
            if let text = textElement(object, result: evaluator.evaluate(object.id)) {
                parts.append(text)
            }
        }
        if let bar = scaleBarElement() {
            parts.append(bar)
        }
        return parts
    }

    private func fillElement(_ path: EvalPath, style: ObjectStyle) -> String? {
        switch path {
        case .polygon(let points):
            guard points.count >= 3 else {
                return nil
            }
            return element("polygon", [("points", pointList(points)),
                                       ("fill", hex(style.color)),
                                       ("fill-opacity", opacity(style.fillOpacity))])
        case .circle(let center, let radius):
            let p = screen(center)
            let r = radius * settings.scale
            guard r.isFinite, r < 200_000 else {
                return nil
            }
            return element("circle", [("cx", num(p.x)), ("cy", num(p.y)), ("r", num(r)),
                                      ("fill", hex(style.color)),
                                      ("fill-opacity", opacity(style.fillOpacity * 0.7))])
        default:
            return nil
        }
    }

    private func strokeElement(_ path: EvalPath, style: ObjectStyle) -> String? {
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
            let p = screen(center)
            let r = radius * settings.scale
            guard r.isFinite, r < 200_000 else {
                return nil
            }
            return element("circle", [("cx", num(p.x)), ("cy", num(p.y)), ("r", num(r)),
                                      ("fill", "none")] + stroke)
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

    private func angleElement(_ object: SketchObject, result: EvalResult) -> String? {
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
        let radius = 0.62
        var points: [Vec2] = []
        for i in 0...30 {
            let t = Double(i) / 30
            let angle = start + delta * t
            points.append(vertex + Vec2(cos(angle), sin(angle)) * radius)
        }
        return element("polyline", [("points", pointList(points)), ("fill", "none"),
                                    ("stroke-opacity", "0.9")]
                       + strokeAttributes(object.style, width: 1.3))
    }

    private func pointElements(_ object: SketchObject, at position: Vec2) -> [String] {
        let p = screen(position)
        let r = object.style.pointSize
        let color = hex(object.style.color)
        var parts: [String] = []

        // The white halo keeps points legible where many objects meet.
        parts.append(element("circle", [("cx", num(p.x)), ("cy", num(p.y)),
                                        ("r", num(r + 1.5)), ("fill", "#ffffff"),
                                        ("fill-opacity", "0.9")]))
        switch object.style.pointShape {
        case .filled:
            parts.append(element("circle", [("cx", num(p.x)), ("cy", num(p.y)),
                                            ("r", num(r / 2)), ("fill", color)]))
        case .hollow:
            parts.append(element("circle", [("cx", num(p.x)), ("cy", num(p.y)),
                                            ("r", num(r / 2)), ("fill", "#ffffff"),
                                            ("stroke", color), ("stroke-width", "1.5")]))
        case .square:
            parts.append(element("rect", [("x", num(p.x - r / 2)), ("y", num(p.y - r / 2)),
                                          ("width", num(r)), ("height", num(r)),
                                          ("rx", "0.8"), ("fill", color)]))
        case .cross:
            let half = r / 2
            let d = "M \(num(p.x - half)) \(num(p.y - half)) "
                + "L \(num(p.x + half)) \(num(p.y + half)) "
                + "M \(num(p.x + half)) \(num(p.y - half)) "
                + "L \(num(p.x - half)) \(num(p.y + half))"
            parts.append(element("path", [("d", d), ("fill", "none"), ("stroke", color),
                                          ("stroke-width", "1.5"), ("stroke-linecap", "round")]))
        }

        if object.showLabel && settings.showLabels && !object.label.isEmpty {
            parts.append(element("text", [("x", num(p.x + 7)), ("y", num(p.y - 10)),
                                          ("font-family", svgFontFamily), ("font-size", "12.5"),
                                          ("font-weight", "600"), ("fill", color),
                                          ("fill-opacity", "0.95")],
                                 text: object.label))
        }
        return parts
    }

    private func textElement(_ object: SketchObject, result: EvalResult) -> String? {
        guard let text = result.text, !text.isEmpty, let anchor = result.anchor else {
            return nil
        }
        var isCaption = false
        if case .caption = object.kind {
            isCaption = true
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

        var parts: [String] = []
        if isCaption {
            parts.append(element("rect", [("x", num(minX - 2)), ("y", num(minY)),
                                          ("width", num(boxWidth + 4)),
                                          ("height", num(boxHeight)),
                                          ("rx", "5"), ("fill", "#ffffff"),
                                          ("fill-opacity", "0.55")]))
        } else {
            parts.append(element("rect", [("x", num(minX)), ("y", num(minY)),
                                          ("width", num(boxWidth)),
                                          ("height", num(boxHeight)),
                                          ("rx", "6"), ("fill", "#ffffff"),
                                          ("fill-opacity", "0.92"),
                                          ("stroke", hex(RGBA.ink)),
                                          ("stroke-opacity", "0.10"),
                                          ("stroke-width", "0.8")]))
        }

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
        parts.append(element("text", attributes, text: text))
        return parts.joined(separator: "\n")
    }

    // MARK: grid and scale bar

    private func gridParts() -> [String] {
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

    private func scaleBarElement() -> String? {
        let unit = settings.lengthUnit
        let oneUnit = settings.scale * unit.perUnit
        guard oneUnit > 0, oneUnit.isFinite else {
            return nil
        }
        var length = oneUnit
        while length < 46 {
            length *= 2
        }
        while length > 140 {
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

    // MARK: function plots

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

    // MARK: geometry

    private var width: Double {
        Double(size.width)
    }
    private var height: Double {
        Double(size.height)
    }

    private var visibleRect: WorldRect {
        let topLeft = worldPoint(0, 0)
        let bottomRight = worldPoint(width, height)
        return WorldRect(minX: min(topLeft.x, bottomRight.x),
                         minY: min(topLeft.y, bottomRight.y),
                         maxX: max(topLeft.x, bottomRight.x),
                         maxY: max(topLeft.y, bottomRight.y))
    }

    private func worldPoint(_ x: Double, _ y: Double) -> Vec2 {
        Vec2(settings.center.x + (x - width / 2) / settings.scale,
             settings.center.y - (y - height / 2) / settings.scale)
    }

    private func screen(_ p: Vec2) -> (x: Double, y: Double) {
        (width / 2 + (p.x - settings.center.x) * settings.scale,
         height / 2 - (p.y - settings.center.y) * settings.scale)
    }

    private func pointList(_ points: [Vec2]) -> String {
        points.map { p in
            let s = screen(p)
            return "\(num(s.x)),\(num(s.y))"
        }.joined(separator: " ")
    }

    // MARK: markup helpers

    private func element(_ name: String, _ attributes: [(String, String)],
                         text: String? = nil) -> String {
        var out = "<" + name
        for (key, value) in attributes {
            out += " \(key)=\"\(value)\""
        }
        if let text {
            out += ">" + escape(text) + "</" + name + ">"
        } else {
            out += "/>"
        }
        return out
    }

    private func strokeAttributes(_ style: ObjectStyle,
                                  width: Double? = nil) -> [(String, String)] {
        var attributes: [(String, String)] = [
            ("stroke", hex(style.color)),
            ("stroke-width", num(width ?? style.lineWidth)),
            ("stroke-linecap", "round"),
            ("stroke-linejoin", "round")
        ]
        switch style.dash {
        case .solid:
            break
        case .dashed:
            attributes.append(("stroke-dasharray", "7 4"))
        case .dotted:
            attributes.append(("stroke-dasharray", "1.2 3.5"))
        }
        return attributes
    }

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

    private func num(_ value: Double) -> String {
        guard value.isFinite else {
            return "0"
        }
        return String(format: "%.2f", value)
    }

    private func opacity(_ value: Double) -> String {
        guard value.isFinite else {
            return "0"
        }
        return String(format: "%.3f", min(max(value, 0), 1))
    }

    private func hex(_ color: RGBA) -> String {
        String(format: "#%02x%02x%02x", channel(color.r), channel(color.g), channel(color.b))
    }

    private func channel(_ value: Double) -> Int {
        guard value.isFinite else {
            return 0
        }
        return Int((min(max(value, 0), 1) * 255).rounded())
    }

    private func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "&":
                out += "&amp;"
            case "<":
                out += "&lt;"
            case ">":
                out += "&gt;"
            case "\"":
                out += "&quot;"
            case "'":
                out += "&apos;"
            default:
                out.append(character)
            }
        }
        return out
    }
}
