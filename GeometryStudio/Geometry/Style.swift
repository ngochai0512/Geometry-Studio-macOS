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

    init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255,
                  Double((hex >> 8) & 0xFF) / 255,
                  Double(hex & 0xFF) / 255,
                  alpha)
    }

    init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let hex = UInt32(value, radix: 16) else {
            return nil
        }
        self.init(hex: hex)
    }

    var hex: String {
        String(format: "%02X%02X%02X",
               Int((r * 255).rounded()),
               Int((g * 255).rounded()),
               Int((b * 255).rounded()))
    }

    var color: Color {
        Color(red: r, green: g, blue: b).opacity(a)
    }
    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static let ink = RGBA(0.12, 0.13, 0.16)
    static let black = RGBA(0, 0, 0)
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

    /// Neutral shades offered for the grid, darkest first.
    static let gridPalette: [(String, RGBA)] = [
        ("Charcoal", RGBA(hex: 0x1C1C1F)),
        ("Graphite", RGBA(hex: 0x2F2F33)),
        ("Slate", RGBA(hex: 0x6E6D73)),
        ("Ash", RGBA(hex: 0x85848A)),
        ("Silver", RGBA(hex: 0xB4B3BA)),
        ("Mist", RGBA(hex: 0xD1D0D6)),
        ("Cloud", RGBA(hex: 0xE6E6EB)),
        ("Paper", RGBA(hex: 0xF3F2F7))
    ]
}

enum DashStyle: String, Codable, CaseIterable, Identifiable {
    case solid
    case dashed
    case dotted
    var id: String {
        rawValue
    }
    var name: String {
        rawValue.capitalized
    }
}

enum PointShape: String, Codable, CaseIterable, Identifiable {
    case filled
    case hollow
    case square
    case cross
    case diamond
    case triangle
    var id: String {
        rawValue
    }
    var name: String {
        rawValue.capitalized
    }
}

enum AngleMarkerStyle: String, Codable, CaseIterable, Identifiable {
    case arc
    case doubleArc
    case rightAngle
    case none

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .arc:
            return "Arc"
        case .doubleArc:
            return "Double arc"
        case .rightAngle:
            return "Right angle"
        case .none:
            return "None"
        }
    }
}

struct AxisLabelStyle: Codable, Hashable {
    var bold = false
    var serif = false

    init() {}

    init(bold: Bool, serif: Bool = false) {
        self.bold = bold
        self.serif = serif
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        serif = try c.decodeIfPresent(Bool.self, forKey: .serif) ?? false
    }

    var title: String {
        switch (bold, serif) {
        case (false, false):
            return "Regular"
        case (true, false):
            return "Bold"
        case (false, true):
            return "Serif"
        default:
            return "Custom"
        }
    }

    static var presets: [AxisLabelStyle] {
        [
            AxisLabelStyle(),
            AxisLabelStyle(bold: true),
            AxisLabelStyle(bold: false, serif: true)
        ]
    }
}

struct ObjectStyle: Codable, Hashable {
    var color: RGBA = .black
    var lineWidth: Double = 1.5
    var dash: DashStyle = .solid
    var pointSize: Double = 5.5
    var pointShape: PointShape = .filled
    var fillOpacity: Double = 0.12
    /// Tick marks on a segment: 0 means none, up to three.
    var tickCount: Int = 0
    var angleMarker: AngleMarkerStyle = .arc

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decodeIfPresent(RGBA.self, forKey: .color) ?? .black
        lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 1.5
        dash = try c.decodeIfPresent(DashStyle.self, forKey: .dash) ?? .solid
        pointSize = try c.decodeIfPresent(Double.self, forKey: .pointSize) ?? 5.5
        pointShape = try c.decodeIfPresent(PointShape.self, forKey: .pointShape) ?? .filled
        fillOpacity = try c.decodeIfPresent(Double.self, forKey: .fillOpacity) ?? 0.12
        tickCount = try c.decodeIfPresent(Int.self, forKey: .tickCount) ?? 0
        angleMarker = try c.decodeIfPresent(AngleMarkerStyle.self, forKey: .angleMarker) ?? .arc
    }
}
