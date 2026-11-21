import CoreGraphics
import Foundation

let svgFontFamily = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif"

/// Rendering constants shared by the object and grid writers.
enum SVGMetrics {
    static let maximumCircleRadius = 200_000.0
    static let circleFillOpacity = 0.7
    static let angleRadius = 0.62
    static let angleSamples = 30
    static let angleLineWidth = 1.3
    static let pointHaloPadding = 1.5
    static let scaleBarMinimum = 46.0
    static let scaleBarMaximum = 140.0
}

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

    // MARK: - Geometry

    var width: Double {
        Double(size.width)
    }

    var height: Double {
        Double(size.height)
    }

    var visibleRect: WorldRect {
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

    func screen(_ p: Vec2) -> (x: Double, y: Double) {
        (width / 2 + (p.x - settings.center.x) * settings.scale,
         height / 2 - (p.y - settings.center.y) * settings.scale)
    }

    func pointList(_ points: [Vec2]) -> String {
        points.map { p in
            let s = screen(p)
            return "\(num(s.x)),\(num(s.y))"
        }.joined(separator: " ")
    }

    // MARK: - Markup helpers

    func element(_ name: String, _ attributes: [(String, String)],
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

    func strokeAttributes(_ style: ObjectStyle,
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

    func num(_ value: Double) -> String {
        guard value.isFinite else {
            return "0"
        }
        return String(format: "%.2f", value)
    }

    func opacity(_ value: Double) -> String {
        guard value.isFinite else {
            return "0"
        }
        return String(format: "%.3f", min(max(value, 0), 1))
    }

    func hex(_ color: RGBA) -> String {
        String(format: "#%02x%02x%02x", channel(color.r), channel(color.g), channel(color.b))
    }

    private func channel(_ value: Double) -> Int {
        guard value.isFinite else {
            return 0
        }
        return Int((min(max(value, 0), 1) * 255).rounded())
    }

    func escape(_ text: String) -> String {
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
