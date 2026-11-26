import Foundation

enum DocumentError: LocalizedError, Equatable {
    /// A sketch written by a newer build. Refuse it instead of dropping keys
    /// this build does not understand and then overwriting them on save.
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This sketch uses document revision \(version). This version of Geometry Studio reads revision \(SketchDocument.currentVersion)."
        }
    }
}

/// The family of grid the canvas draws and snaps to.
enum GridType: String, Codable, CaseIterable, Identifiable {
    case orthogonal
    case orthogonalDense
    case triangular
    case polar
    case isometric

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .orthogonal:
            return "Orthogonal"
        case .orthogonalDense:
            return "Orthogonal (dense)"
        case .triangular:
            return "Triangular"
        case .polar:
            return "Polar"
        case .isometric:
            return "Isometric"
        }
    }
}

struct CanvasSettings: Codable, Hashable {
    /// The angle increments the canvas can snap drawing directions to.
    static let angleSnapChoices: [Double] = [0, 5, 15, 30, 45, 90]

    var grid: Bool = true
    var gridType: GridType = .orthogonal
    var gridColor: RGBA = RGBA(hex: 0x1C1C1F)
    var gridBold: Bool = false
    var backgroundColor: RGBA = RGBA(1, 1, 1)
    var theme: CanvasTheme = .light
    var useMetalRenderer: Bool = false
    var axes: Bool = true
    var axesLabels: Bool = true
    var axesLabelStyle: AxisLabelStyle = AxisLabelStyle()
    var snap: Bool = false
    var showLabels: Bool = true
    /// Guides that align a new point with existing points, midpoints,
    /// intersections, parallels and perpendiculars.
    var smartGuides: Bool = true
    /// Degrees between snapped drawing directions; zero turns angle snapping off.
    var angleSnap: Double = 0
    // New sketches start in centimetres by product decision. The original
    // defaulted to inches; the other observed defaults remain.
    var lengthUnit: LengthUnit = .cm
    var angleUnit: AngleUnit = .degrees
    var precision: Int = 2
    var scale: Double = SketchMetrics.pixelsPerCentimetre
    var center: Vec2 = Vec2(0, 0)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grid = try c.decodeIfPresent(Bool.self, forKey: .grid) ?? true
        gridType = try c.decodeIfPresent(GridType.self, forKey: .gridType) ?? .orthogonal
        gridColor = try c.decodeIfPresent(RGBA.self, forKey: .gridColor) ?? RGBA(hex: 0x1C1C1F)
        gridBold = try c.decodeIfPresent(Bool.self, forKey: .gridBold) ?? false
        backgroundColor = try c.decodeIfPresent(RGBA.self, forKey: .backgroundColor) ?? RGBA(1, 1, 1)
        theme = try c.decodeIfPresent(CanvasTheme.self, forKey: .theme) ?? .light
        useMetalRenderer = try c.decodeIfPresent(Bool.self, forKey: .useMetalRenderer) ?? false
        axes = try c.decodeIfPresent(Bool.self, forKey: .axes) ?? true
        axesLabels = try c.decodeIfPresent(Bool.self, forKey: .axesLabels) ?? true
        axesLabelStyle = try c.decodeIfPresent(AxisLabelStyle.self, forKey: .axesLabelStyle)
            ?? AxisLabelStyle()
        snap = try c.decodeIfPresent(Bool.self, forKey: .snap) ?? false
        showLabels = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? true
        smartGuides = try c.decodeIfPresent(Bool.self, forKey: .smartGuides) ?? true
        let storedAngleSnap = try c.decodeIfPresent(Double.self, forKey: .angleSnap) ?? 0
        angleSnap = CanvasSettings.angleSnapChoices.contains(storedAngleSnap) ? storedAngleSnap : 0
        lengthUnit = try c.decodeIfPresent(LengthUnit.self, forKey: .lengthUnit) ?? .cm
        angleUnit = try c.decodeIfPresent(AngleUnit.self, forKey: .angleUnit) ?? .degrees
        precision = try c.decodeIfPresent(Int.self, forKey: .precision) ?? 2
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? SketchMetrics.pixelsPerCentimetre
        if !scale.isFinite || scale <= 0 {
            scale = SketchMetrics.pixelsPerCentimetre
        } else {
            scale = min(max(scale, 12), 420)
        }
        center = try c.decodeIfPresent(Vec2.self, forKey: .center) ?? Vec2(0, 0)
        if !center.x.isFinite || !center.y.isFinite {
            center = Vec2(0, 0)
        }
    }
}

struct SketchDocument: Codable, Equatable {
    /// The on-disk schema revision. Older builds wrote no version key at all,
    /// which decodes as revision 0. Bump this when a migration is required.
    static let currentVersion = 1

    var version: Int = SketchDocument.currentVersion
    var objects: [SketchObject] = []
    var settings: CanvasSettings = CanvasSettings()
    var marks: TransformMarks = TransformMarks()
    var title: String = "Untitled Sketch"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        guard storedVersion <= SketchDocument.currentVersion else {
            throw DocumentError.unsupportedVersion(storedVersion)
        }
        version = storedVersion
        objects = try c.decodeIfPresent([SketchObject].self, forKey: .objects) ?? []
        settings = try c.decodeIfPresent(CanvasSettings.self, forKey: .settings) ?? CanvasSettings()
        marks = try c.decodeIfPresent(TransformMarks.self, forKey: .marks) ?? TransformMarks()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Sketch"
        try migrateToCurrent()
    }

    /// One step per revision so a skipped revision still lands on the current
    /// schema. Revision 0 differs from revision 1 only by the version key.
    private mutating func migrateToCurrent() throws {
        while version < SketchDocument.currentVersion {
            switch version {
            case 0:
                version = 1
            default:
                version = SketchDocument.currentVersion
            }
        }
    }
}

struct SalvageResult {
    var document: SketchDocument
    var recovered: Int
    var total: Int
}

extension SketchDocument {
    /// Recovers whatever still decodes from a damaged sketch. Objects are
    /// decoded one at a time, so one unreadable object does not cost the rest.
    static func salvage(from data: Data) -> SalvageResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let rawObjects = root["objects"] as? [Any] ?? []
        let decoder = JSONDecoder()
        var recovered: [SketchObject] = []
        for raw in rawObjects {
            guard JSONSerialization.isValidJSONObject(raw),
                  let objectData = try? JSONSerialization.data(withJSONObject: raw),
                  let object = try? decoder.decode(SketchObject.self, from: objectData) else {
                continue
            }
            recovered.append(object)
        }
        guard !recovered.isEmpty else {
            return nil
        }

        var document = SketchDocument()
        document.objects = recovered
        if let title = root["title"] as? String {
            document.title = title
        }
        if let rawSettings = root["settings"] as? [String: Any],
           let settingsData = try? JSONSerialization.data(withJSONObject: rawSettings),
           let settings = try? decoder.decode(CanvasSettings.self, from: settingsData) {
            document.settings = settings
        }
        if let rawMarks = root["marks"] as? [String: Any],
           let marksData = try? JSONSerialization.data(withJSONObject: rawMarks),
           let marks = try? decoder.decode(TransformMarks.self, from: marksData) {
            document.marks = marks
        }
        return SalvageResult(document: document, recovered: recovered.count,
                             total: rawObjects.count)
    }
}

// MARK: - Starter sample

/// The one built-in sample offered by the welcome sheet. It is deliberately
/// not a browsable gallery; a new sketch still starts blank by default.
enum SketchTemplate {
    case triangle

    func document(settings: CanvasSettings) -> SketchDocument {
        var document = SketchDocument()
        document.settings = settings
        document.title = "Triangle Sketch"
        document.objects = SketchTemplate.triangleObjects()
        return document
    }

    private static func triangleObjects() -> [SketchObject] {
        func point(_ label: String, _ x: Double, _ y: Double, _ order: Int) -> SketchObject {
            var object = SketchObject(kind: .freePoint)
            object.label = label
            object.position = Vec2(x, y)
            object.order = order
            object.style.color = AppPreferences.appearance().color(for: .point)
            return object
        }
        func segment(_ a: SketchObject, _ b: SketchObject, _ order: Int) -> SketchObject {
            var object = SketchObject(kind: .segment(a: a.id, b: b.id))
            object.order = order
            object.style.color = AppPreferences.appearance().color(for: .line)
            return object
        }
        func midpoint(_ a: SketchObject, _ b: SketchObject, _ label: String, _ order: Int) -> SketchObject {
            var object = SketchObject(kind: .midpoint(a: a.id, b: b.id))
            object.label = label
            object.order = order
            object.style.color = AppPreferences.appearance().color(for: .point)
            return object
        }

        let a = point("A", -5, -3, 1)
        let b = point("B", 5, -3, 2)
        let c = point("C", 1, 4, 3)
        var polygon = SketchObject(kind: .polygon(vertices: [a.id, b.id, c.id]))
        polygon.order = 4
        polygon.style.color = .accent
        polygon.style.fillOpacity = 0.07
        let ab = segment(a, b, 5)
        let bc = segment(b, c, 6)
        let ca = segment(c, a, 7)
        let d = midpoint(a, b, "D", 8)
        let e = midpoint(b, c, "E", 9)
        let f = midpoint(c, a, "F", 10)
        var de = segment(d, e, 11)
        de.style.dash = .dashed
        de.style.color = .secondaryInk
        let caption = SketchObject(kind: .caption("Drag A, B or C — the midsegment follows."))
        var note = caption
        note.position = Vec2(-9, 7)
        note.order = 12
        note.style.color = .secondaryInk
        return [a, b, c, polygon, ab, bc, ca, d, e, f, de, note]
    }
}

/// A one-shot carrier for the starter sample chosen in the welcome sheet.
/// `DocumentGroup` builds the new document synchronously after the sheet calls
/// `newDocument`, so the choice only has to survive that call.
enum TemplateLibrary {
    static var pending: SketchTemplate?
}

extension CanvasSettings {
    /// Display tokens for the canvas. The background decides light or dark;
    /// the theme supplies the paper tint. A dark custom background flips the
    /// light tokens, and an unreadable grid colour is replaced by a neutral
    /// with the same alpha.
    var palette: CanvasPalette {
        let dark = backgroundColor.luminance < 0.45
        let warm = theme == .paper
        let ink = dark ? RGBA(0.92, 0.93, 0.95)
            : (warm ? RGBA(0.24, 0.20, 0.15) : RGBA.ink)
        let secondary = dark ? RGBA(0.68, 0.70, 0.76)
            : (warm ? RGBA(0.42, 0.36, 0.28) : RGBA.secondaryInk)
        var effectiveGrid = gridColor
        if dark, gridColor.luminance < 0.45 {
            effectiveGrid = RGBA(0.82, 0.84, 0.88, gridColor.a)
        } else if !dark, gridColor.luminance > 0.82 {
            effectiveGrid = RGBA(0.35, 0.36, 0.40, gridColor.a)
        }
        return CanvasPalette(
            isDark: dark,
            ink: ink,
            secondaryInk: secondary,
            halo: dark ? RGBA(0.10, 0.11, 0.14, 0.9) : RGBA(1, 1, 1, 0.9),
            card: dark ? RGBA(0.14, 0.15, 0.18, 0.94) : RGBA(1, 1, 1, 0.92),
            cardBorder: RGBA(ink.r, ink.g, ink.b, 0.14),
            axisLabel: dark ? RGBA(0.80, 0.82, 0.86, 0.85) : secondary,
            grid: effectiveGrid
        )
    }

    /// The white-page token set used by print and export. It keeps the
    /// document's grid colour unless that colour would vanish on paper.
    var paperPalette: CanvasPalette {
        var result = palette
        result.isDark = false
        result.ink = .ink
        result.secondaryInk = .secondaryInk
        result.halo = RGBA(1, 1, 1, 0.9)
        result.card = RGBA(1, 1, 1, 0.92)
        result.cardBorder = RGBA(0.12, 0.13, 0.16, 0.14)
        result.axisLabel = .secondaryInk
        result.grid = gridColor.luminance > 0.82
            ? RGBA(0.35, 0.36, 0.40, gridColor.a)
            : gridColor
        return result
    }
}
