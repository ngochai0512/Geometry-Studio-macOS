import Foundation
import Testing
@testable import GeometryStudio

@Suite("Document and units")
struct DocumentTests {
    @Test("observed defaults stay inches, hundredths and degrees")
    func observedDefaults() {
        let settings = CanvasSettings()
        #expect(settings.lengthUnit == .inches)
        #expect(settings.precision == 2)
        #expect(settings.angleUnit == .degrees)
    }

    @Test("unit factors follow the original's 72-point inch")
    func unitFactors() {
        #expect(LengthUnit.cm.perUnit == 1)
        #expect(abs(LengthUnit.inches.perUnit - 2.54) < 1e-12)
        #expect(abs(LengthUnit.pixels.perUnit - 2.54 / 72) < 1e-12)
        #expect(abs(SketchMetrics.pixelsPerCentimetre - 72 / 2.54) < 1e-12)
    }

    @Test("a document round-trips through JSON")
    func roundTrip() throws {
        var document = SketchDocument()
        var object = SketchObject(kind: .freePoint)
        object.position = Vec2(1.5, -2)
        document.objects = [object]
        document.settings.precision = 4
        document.settings.lengthUnit = .cm
        document.settings.gridType = .triangular
        document.settings.gridColor = RGBA(hex: 0xE6E6EB)
        document.settings.gridBold = true
        document.settings.backgroundColor = RGBA(0.1, 0.2, 0.3, 0.5)
        document.settings.axesLabels = false
        let labelStyle = AxisLabelStyle(bold: false, serif: true)
        document.settings.axesLabelStyle = labelStyle
        document.title = "Round Trip"

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(SketchDocument.self, from: data)

        #expect(decoded.title == "Round Trip")
        #expect(decoded.objects.count == 1)
        #expect(decoded.objects.first?.position == Vec2(1.5, -2))
        #expect(decoded.settings.precision == 4)
        #expect(decoded.settings.lengthUnit == .cm)
        #expect(decoded.settings.gridType == .triangular)
        #expect(decoded.settings.gridColor == RGBA(hex: 0xE6E6EB))
        #expect(decoded.settings.gridBold)
        #expect(decoded.settings.backgroundColor == RGBA(0.1, 0.2, 0.3, 0.5))
        #expect(!decoded.settings.axesLabels)
        #expect(decoded.settings.axesLabelStyle == labelStyle)
        #expect(decoded.version == SketchDocument.currentVersion)
    }

    @Test("transform marks round-trip and older files default to none")
    func transformMarksRoundTrip() throws {
        var document = SketchDocument()
        let a = SketchObject(kind: .freePoint)
        let b = SketchObject(kind: .freePoint)
        let c = SketchObject(kind: .freePoint)
        document.objects = [a, b, c]
        document.marks.mirror = a.id
        document.marks.center = b.id
        document.marks.angle = AngleMark(a: a.id, vertex: b.id, c: c.id)
        document.marks.ratio = RatioMark(first: a.id, second: b.id)
        document.marks.vector = VectorMark(from: a.id, to: c.id)

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(SketchDocument.self, from: data)

        #expect(decoded.marks == document.marks)

        var root = try #require(jsonObject(from: data))
        root.removeValue(forKey: "marks")
        let legacy = try JSONSerialization.data(withJSONObject: root)
        let old = try JSONDecoder().decode(SketchDocument.self, from: legacy)

        #expect(old.marks.isEmpty)
    }

    @Test("new Tier 2 object kinds round-trip")
    func tierTwoKindsRoundTrip() throws {
        var document = SketchDocument()
        let a = SketchObject(kind: .freePoint)
        let b = SketchObject(kind: .freePoint)
        let parameter = SketchObject(kind: .parameter(value: 2.5, minimum: 0, maximum: 10))
        let bisector = SketchObject(kind: .construction(.perpendicularBisector(a: a.id, b: b.id)))
        let vector = SketchObject(kind: .vector(.fromPoints(from: a.id, to: b.id)))
        let system = SketchObject(kind: .coordinateSystem(kind: .polar, origin: a.id,
                                                           step: 2.54, unit: .inches))
        let graph = SketchObject(kind: .graph(.derivative("x^2")))
        document.objects = [a, b, parameter, bisector, vector, system, graph]

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(SketchDocument.self, from: data)

        #expect(decoded.objects == document.objects)
    }

    @Test("new object kinds preserve their added data")
    func newObjectKindsRoundTrip() throws {
        var document = SketchDocument()
        let center = SketchObject(kind: .freePoint)
        var circle = SketchObject(kind: .circleRadius(center: center.id, radius: 4))
        circle.arcFill = .sector
        document.objects = [center, circle]

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(SketchDocument.self, from: data)

        #expect(decoded.objects.count == 2)
        guard case .circleRadius(_, let radius)? = decoded.objects.last?.kind else {
            Issue.record("expected a radius circle")
            return
        }
        #expect(abs(radius - 4) < 1e-12)
        #expect(decoded.objects.last?.arcFill == .sector)
    }

    @Test("a sketch snapshot round-trips through its file codec")
    func fileDocumentRoundTrip() throws {        var document = SketchDocument()
        document.title = "Saved"
        var object = SketchObject(kind: .freePoint)
        object.position = Vec2(-1, 3)
        document.objects = [object]
        let file = SketchSnapshot(sketch: document)

        let data = try file.encodedData()
        let read = try SketchSnapshot.decode(from: data)

        #expect(read.sketch == document)
        #expect(read.recoveryNote == nil)
    }

    @Test("a new document starts blank")
    func newDocumentIsBlank() {
        let document = SketchModel.blankDocument()

        #expect(document.objects.isEmpty)
        #expect(document.title == "Untitled Sketch")
    }

    @Test("a damaged file loads what still decodes and leaves a note")
    func fileDocumentSalvage() throws {
        var document = SketchDocument()
        document.title = "Damaged"
        document.objects = [
            SketchObject(kind: .freePoint),
            SketchObject(kind: .freePoint)
        ]
        var root = try #require(jsonObject(from: JSONEncoder().encode(document)))
        var objects = try #require(root["objects"] as? [[String: Any]])
        objects[1]["kind"] = "not a kind"
        root["objects"] = objects
        let data = try JSONSerialization.data(withJSONObject: root)

        let read = try SketchSnapshot.decode(from: data)

        #expect(read.sketch.objects.count == 1)
        #expect(read.sketch.title == "Damaged")
        #expect(read.recoveryNote != nil)
    }

    @Test("an unversioned sketch is revision 0 and migrates")
    func unversionedMigrates() throws {
        var document = SketchDocument()
        document.title = "Legacy"
        var root = try #require(jsonObject(from: JSONEncoder().encode(document)))
        root.removeValue(forKey: "version")
        let legacy = try JSONSerialization.data(withJSONObject: root)

        let decoded = try JSONDecoder().decode(SketchDocument.self, from: legacy)

        #expect(decoded.version == SketchDocument.currentVersion)
        #expect(decoded.title == "Legacy")
    }

    @Test("a sketch missing newer keys uses defaults")
    func missingKeysUseDefaults() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "title": "Old Sketch",
            "objects": [],
            "settings": ["precision": 4, "lengthUnit": "cm"]
        ])

        let decoded = try JSONDecoder().decode(SketchDocument.self, from: data)

        #expect(decoded.title == "Old Sketch")
        #expect(decoded.settings.precision == 4)
        #expect(decoded.settings.lengthUnit == .cm)
        #expect(decoded.settings.grid)
        #expect(decoded.settings.axes)
        #expect(decoded.settings.showLabels)
        #expect(decoded.settings.angleUnit == .degrees)
        #expect(decoded.settings.gridType == .orthogonal)
        #expect(decoded.settings.gridColor == RGBA(hex: 0x1C1C1F))
        #expect(!decoded.settings.gridBold)
        #expect(decoded.settings.backgroundColor == RGBA(1, 1, 1))
        #expect(decoded.settings.axesLabels)
        #expect(decoded.settings.axesLabelStyle == AxisLabelStyle())
        #expect(decoded.settings.scale == SketchMetrics.pixelsPerCentimetre)
    }

    @Test("an object missing newer keys uses defaults")
    func objectMissingKeysUsesDefaults() throws {
        var object = SketchObject(kind: .freePoint)
        object.label = "A"
        var raw = try #require(jsonObject(from: JSONEncoder().encode(object)))
        raw.removeValue(forKey: "style")
        raw.removeValue(forKey: "showLabel")
        raw.removeValue(forKey: "isLocked")
        let data = try JSONSerialization.data(withJSONObject: raw)

        let decoded = try JSONDecoder().decode(SketchObject.self, from: data)

        #expect(decoded.label == "A")
        #expect(decoded.showLabel)
        #expect(!decoded.isLocked)
        #expect(decoded.style.lineWidth == 1.5)
        #expect(decoded.style.pointShape == .filled)
    }

    @Test("a newer document revision is refused, not silently truncated")
    func futureVersionRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 99,
            "title": "From The Future",
            "objects": []
        ])

        #expect(throws: DocumentError.unsupportedVersion(99)) {
            _ = try JSONDecoder().decode(SketchDocument.self, from: data)
        }
    }

    @Test("salvage keeps the objects that still decode")
    func salvageReadableObjects() throws {
        var document = SketchDocument()
        document.title = "Damaged"
        let a = SketchObject(kind: .freePoint)
        let b = SketchObject(kind: .midpoint(a: a.id, b: a.id))
        document.objects = [a, b]
        var root = try #require(jsonObject(from: JSONEncoder().encode(document)))
        var objects = try #require(root["objects"] as? [[String: Any]])
        objects[1]["kind"] = "not a kind"
        root["objects"] = objects
        let damaged = try JSONSerialization.data(withJSONObject: root)

        let result = try #require(SketchDocument.salvage(from: damaged))

        #expect(result.recovered == 1)
        #expect(result.total == 2)
        #expect(result.document.objects.first?.id == a.id)
        #expect(result.document.title == "Damaged")
    }

    private func jsonObject(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
