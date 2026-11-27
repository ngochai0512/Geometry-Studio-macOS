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

    /// Perceptual luminance of the RGB channels, ignoring alpha. Used to pick
    /// a light or dark set of canvas tokens from the background colour.
    var luminance: Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
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

/// Canvas colour scheme. Selecting a theme proposes its background; a custom
/// background still wins, and the palette flips to the opposite ink set when
/// that custom background is dark.
enum CanvasTheme: String, Codable, CaseIterable, Identifiable {
    case automatic
    case light
    case dark
    case paper
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .paper:
            return "Paper"
        case .custom:
            return "Custom"
        }
    }

    var background: RGBA {
        switch self {
        case .automatic, .light, .custom:
            return RGBA(1, 1, 1)
        case .dark:
            return RGBA(0.07, 0.08, 0.10)
        case .paper:
            return RGBA(0.97, 0.95, 0.90)
        }
    }

    /// Automatic follows the system appearance; every other preset is fixed.
    func resolved(systemDark: Bool) -> CanvasTheme {
        guard self == .automatic else {
            return self
        }
        return systemDark ? .dark : .light
    }
}

/// Screen tokens derived from the theme and the actual background. Ink, label,
/// card, axis and halo colours change together, so a dark canvas never leaves
/// black text on black or white chips on white.
struct CanvasPalette {
    var isDark: Bool
    var ink: RGBA
    var secondaryInk: RGBA
    var halo: RGBA
    var card: RGBA
    var cardBorder: RGBA
    var axisLabel: RGBA
    var grid: RGBA

    /// Near-black strokes on a dark canvas (and near-white on a light one)
    /// follow the ink token; coloured objects keep their own colour.
    func resolve(_ color: RGBA) -> RGBA {
        if isDark, color.luminance < 0.32 {
            return ink
        }
        if !isDark, color.luminance > 0.92 {
            return ink
        }
        return color
    }
}

/// One run of a canvas label after lightweight math markup is expanded.
struct MathLabelRun: Equatable {
    enum Script: Equatable {
        case normal
        case superscript
        case sub
    }

    var text: String
    var script: Script
}

/// Canvas label markup: `^{…}` superscript, `_{…}` subscript, `\alpha`-style
/// Greek names, `\overline{…}` and `\widehat{…}`. Everything else passes
/// through, so plain labels keep working unchanged.
enum MathLabel {
    private static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο",
        "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ",
        "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Epsilon": "Ε",
        "Zeta": "Ζ", "Eta": "Η", "Theta": "Θ", "Iota": "Ι", "Kappa": "Κ",
        "Lambda": "Λ", "Mu": "Μ", "Nu": "Ν", "Xi": "Ξ", "Omicron": "Ο",
        "Pi": "Π", "Rho": "Ρ", "Sigma": "Σ", "Tau": "Τ", "Upsilon": "Υ",
        "Phi": "Φ", "Chi": "Χ", "Psi": "Ψ", "Omega": "Ω"
    ]

    private static let symbols: [String: String] = [
        "degree": "°", "times": "×", "cdot": "·", "pm": "±", "mp": "∓",
        "infty": "∞", "angle": "∠", "triangle": "△", "perp": "⊥",
        "parallel": "∥", "prime": "′", "approx": "≈", "neq": "≠",
        "leq": "≤", "geq": "≥"
    ]

    private static let combiningOverline = "\u{0305}"
    private static let combiningArc = "\u{0311}"
    private static let combiningWideArc = "\u{0361}"

    static func parse(_ source: String) -> [MathLabelRun] {
        var runs: [MathLabelRun] = []
        var plain = ""
        func flushPlain() {
            guard !plain.isEmpty else {
                return
            }
            runs.append(MathLabelRun(text: plain, script: .normal))
            plain.removeAll()
        }

        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]

            if character == "\\" {
                let afterSlash = source.index(after: index)
                guard afterSlash < source.endIndex else {
                    plain.append(character)
                    break
                }
                let (name, nameEnd) = readName(source, from: afterSlash)
                if name == "overline" || name == "widehat" {
                    let group = readGroup(source, from: nameEnd)
                    plain += decorate(group.text, arc: name == "widehat")
                    index = group.end
                } else if let symbol = symbol(for: name) {
                    plain += symbol
                    index = nameEnd
                } else if !name.isEmpty {
                    plain += name
                    index = nameEnd
                } else {
                    plain.append(source[afterSlash])
                    index = source.index(after: afterSlash)
                }
                continue
            }

            if character == "^" || character == "_" {
                flushPlain()
                let group = readScript(source, from: index)
                if !group.text.isEmpty {
                    runs.append(MathLabelRun(text: group.text,
                                             script: character == "^" ? .superscript : .sub))
                }
                index = group.end
                continue
            }

            plain.append(character)
            index = source.index(after: index)
        }
        flushPlain()
        return runs
    }

    /// The spoken/exported form: markup removed, symbols kept as characters.
    static func plainText(_ source: String) -> String {
        parse(source).map(\.text).joined()
    }

    /// The canvas form, with scripts sized and raised/lowered per run.
    static func attributed(_ source: String,
                           base: Font = .body,
                           script: Font = .caption2,
                           superscriptOffset: CGFloat = 5,
                           subscriptOffset: CGFloat = -2) -> AttributedString {
        var attributed = AttributedString()
        for run in parse(source) {
            var piece = AttributedString(run.text)
            switch run.script {
            case .normal:
                piece.font = base
            case .superscript:
                piece.font = script
                piece.baselineOffset = superscriptOffset
            case .sub:
                piece.font = script
                piece.baselineOffset = subscriptOffset
            }
            attributed.append(piece)
        }
        return attributed
    }

    private static func symbol(for name: String) -> String? {
        greek[name] ?? symbols[name]
    }

    private static func readName(_ source: String, from index: String.Index)
        -> (name: String, end: String.Index) {
        var cursor = index
        var name = ""
        while cursor < source.endIndex, source[cursor].isLetter {
            name.append(source[cursor])
            cursor = source.index(after: cursor)
        }
        return (name, cursor)
    }

    private static func readGroup(_ source: String, from index: String.Index)
        -> (text: String, end: String.Index) {
        guard index < source.endIndex, source[index] == "{" else {
            return ("", index)
        }
        var cursor = source.index(after: index)
        var depth = 1
        var text = ""
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" {
                depth += 1
                text.append(character)
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return (text, source.index(after: cursor))
                }
                text.append(character)
            } else {
                text.append(character)
            }
            cursor = source.index(after: cursor)
        }
        return (text, cursor)
    }

    private static func readScript(_ source: String, from index: String.Index)
        -> (text: String, end: String.Index) {
        let after = source.index(after: index)
        guard after < source.endIndex else {
            return ("", after)
        }
        if source[after] == "{" {
            return readGroup(source, from: after)
        }
        if source[after] == "\\" {
            let nameStart = source.index(after: after)
            let (name, end) = readName(source, from: nameStart)
            return (symbol(for: name) ?? "", end)
        }
        return (String(source[after]), source.index(after: after))
    }

    private static func decorate(_ text: String, arc: Bool) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else {
            return text
        }
        if arc {
            if characters.count == 2 {
                return String(characters[0]) + combiningWideArc + String(characters[1])
            }
            return characters.map {
                $0 == " " ? " " : String($0) + combiningArc
            }.joined()
        }
        return characters.map {
            $0 == " " ? " " : String($0) + combiningOverline
        }.joined()
    }
}
