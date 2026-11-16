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
        document.title = "Round Trip"

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(SketchDocument.self, from: data)

        #expect(decoded.title == "Round Trip")
        #expect(decoded.objects.count == 1)
        #expect(decoded.objects.first?.position == Vec2(1.5, -2))
        #expect(decoded.settings.precision == 4)
        #expect(decoded.settings.lengthUnit == .cm)
    }
}
