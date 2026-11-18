import CoreGraphics
import Foundation
import Testing
@testable import GeometryStudio

@Suite("SVG export")
struct SVGExportTests {
    private func settings() -> CanvasSettings {
        var settings = CanvasSettings()
        settings.grid = false
        settings.axes = false
        settings.scale = SketchMetrics.pixelsPerCentimetre
        return settings
    }

    @Test("writes a well-formed SVG with paths, points and escaped text")
    func wellFormed() {
        var a = SketchObject(kind: .freePoint)
        a.position = Vec2(0, 0)
        a.label = "A"
        var b = SketchObject(kind: .freePoint)
        b.position = Vec2(2, 1)
        b.label = "B"
        let segment = SketchObject(kind: .segment(a: a.id, b: b.id))
        var caption = SketchObject(kind: .caption("x < y & z"))
        caption.position = Vec2(0.5, 0.5)

        let exporter = SVGExporter(objects: [a, b, segment, caption],
                                   settings: settings(),
                                   size: CGSize(width: 400, height: 300),
                                   title: "A & B")
        let svg = exporter.svg()

        #expect(svg.hasPrefix("<?xml"))
        #expect(svg.contains("<title>A &amp; B</title>"))
        #expect(svg.contains("x &lt; y &amp; z"))
        #expect(svg.contains("<line "))
        #expect(svg.contains("<circle "))

        let parser = XMLParser(data: Data(svg.utf8))
        #expect(parser.parse())
    }

    @Test("carries dash style and fill opacity into the markup")
    func style() {
        var a = SketchObject(kind: .freePoint)
        a.position = Vec2(-1, -1)
        var b = SketchObject(kind: .freePoint)
        b.position = Vec2(1, -1)
        var c = SketchObject(kind: .freePoint)
        c.position = Vec2(0, 1)
        var polygon = SketchObject(kind: .polygon(vertices: [a.id, b.id, c.id]))
        polygon.style.dash = .dashed
        polygon.style.fillOpacity = 0.2

        let svg = SVGExporter(objects: [a, b, c, polygon],
                              settings: settings(),
                              size: CGSize(width: 400, height: 300)).svg()

        #expect(svg.contains("stroke-dasharray=\"7 4\""))
        #expect(svg.contains("fill-opacity=\"0.200\""))
    }
}
