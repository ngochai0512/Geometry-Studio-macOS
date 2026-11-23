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

struct CanvasSettings: Codable, Hashable {
    var grid: Bool = true
    var axes: Bool = true
    var snap: Bool = false
    var showLabels: Bool = true
    // Defaults read from the original's preference initialiser (routine):
    // distance unit index 2 (inches), precision 2 (hundredths). The distance
    // factor table there is [1, 72/2.54, 72], so index 2 is inches.
    var lengthUnit: LengthUnit = .inches
    var angleUnit: AngleUnit = .degrees
    var precision: Int = 2
    var scale: Double = SketchMetrics.pixelsPerCentimetre
    var center: Vec2 = Vec2(0, 0)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grid = try c.decodeIfPresent(Bool.self, forKey: .grid) ?? true
        axes = try c.decodeIfPresent(Bool.self, forKey: .axes) ?? true
        snap = try c.decodeIfPresent(Bool.self, forKey: .snap) ?? false
        showLabels = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? true
        lengthUnit = try c.decodeIfPresent(LengthUnit.self, forKey: .lengthUnit) ?? .inches
        angleUnit = try c.decodeIfPresent(AngleUnit.self, forKey: .angleUnit) ?? .degrees
        precision = try c.decodeIfPresent(Int.self, forKey: .precision) ?? 2
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? SketchMetrics.pixelsPerCentimetre
        center = try c.decodeIfPresent(Vec2.self, forKey: .center) ?? Vec2(0, 0)
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
        return SalvageResult(document: document, recovered: recovered.count,
                             total: rawObjects.count)
    }
}
