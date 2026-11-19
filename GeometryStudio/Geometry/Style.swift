import SwiftUI
import AppKit

// MARK: - Style

struct RGBA: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    var color: Color {
        Color(red: r, green: g, blue: b).opacity(a)
    }
    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static let ink = RGBA(0.12, 0.13, 0.16)
    static let secondaryInk = RGBA(0.35, 0.37, 0.42)
    static let accent = RGBA(0.0, 0.48, 1.0)
    static let magenta = RGBA(0.85, 0.1, 0.55)
    static let teal = RGBA(0.0, 0.55, 0.52)
    static let orange = RGBA(0.95, 0.45, 0.1)
    static let violet = RGBA(0.45, 0.3, 0.8)

    static let palette: [(String, RGBA)] = [
        ("Ink", .ink),
        ("Blue", .accent),
        ("Teal", .teal),
        ("Violet", .violet),
        ("Orange", .orange),
        ("Magenta", .magenta),
        ("Red", RGBA(0.85, 0.18, 0.16)),
        ("Green", RGBA(0.12, 0.62, 0.25))
    ]
}

enum DashStyle: String, Codable, CaseIterable, Identifiable {
    case solid, dashed, dotted
    var id: String {
        rawValue
    }
    var name: String {
        rawValue.capitalized
    }
}

enum PointShape: String, Codable, CaseIterable, Identifiable {
    case filled, hollow, square, cross
    var id: String {
        rawValue
    }
    var name: String {
        rawValue.capitalized
    }
}

struct ObjectStyle: Codable, Hashable {
    var color: RGBA = .ink
    var lineWidth: Double = 1.5
    var dash: DashStyle = .solid
    var pointSize: Double = 5.5
    var pointShape: PointShape = .filled
    var fillOpacity: Double = 0.12

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decodeIfPresent(RGBA.self, forKey: .color) ?? .ink
        lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 1.5
        dash = try c.decodeIfPresent(DashStyle.self, forKey: .dash) ?? .solid
        pointSize = try c.decodeIfPresent(Double.self, forKey: .pointSize) ?? 5.5
        pointShape = try c.decodeIfPresent(PointShape.self, forKey: .pointShape) ?? .filled
        fillOpacity = try c.decodeIfPresent(Double.self, forKey: .fillOpacity) ?? 0.12
    }
}
