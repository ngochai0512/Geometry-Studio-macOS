import SwiftUI
import Foundation

// MARK: - Small vector type

struct Vec2: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ x: Double = 0, _ y: Double = 0) {
        self.x = x
        self.y = y
    }

    static let zero = Vec2(0, 0)

    var cg: CGPoint { CGPoint(x: x, y: y) }
    var length: Double { (x * x + y * y).squareRoot() }
    var angle: Double { atan2(y, x) }

    func distance(to other: Vec2) -> Double { (self - other).length }
    func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }
    func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }
    func normalized() -> Vec2 {
        let l = length
        return l < 1e-12 ? Vec2(0, 0) : Vec2(x / l, y / l)
    }
    func perpendicular() -> Vec2 { Vec2(-y, x) }
    func rotated(by radians: Double) -> Vec2 {
        let c = cos(radians), s = sin(radians)
        return Vec2(x * c - y * s, x * s + y * c)
    }
    func scaled(_ k: Double) -> Vec2 { Vec2(x * k, y * k) }
    func lerp(to other: Vec2, _ t: Double) -> Vec2 {
        Vec2(x + (other.x - x) * t, y + (other.y - y) * t)
    }

    static func + (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x + r.x, l.y + r.y) }
    static func - (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x - r.x, l.y - r.y) }
    static func * (l: Vec2, r: Double) -> Vec2 { Vec2(l.x * r, l.y * r) }
    static func / (l: Vec2, r: Double) -> Vec2 { Vec2(l.x / r, l.y / r) }
    static prefix func - (v: Vec2) -> Vec2 { Vec2(-v.x, -v.y) }
}

struct WorldRect: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var center: Vec2 { Vec2((minX + maxX) / 2, (minY + maxY) / 2) }
    func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }
    func inset(_ d: Double) -> WorldRect {
        WorldRect(minX: minX + d, minY: minY + d, maxX: maxX - d, maxY: maxY - d)
    }
}

// MARK: - Evaluated path

enum EvalPath {
    case segment(Vec2, Vec2)
    case ray(Vec2, Vec2)
    case line(Vec2, Vec2)
    case circle(Vec2, Double)
    case polygon([Vec2])
    case polyline([Vec2])
    case functionPlot(String)

    var isStraight: Bool {
        switch self {
        case .segment, .ray, .line: return true
        default: return false
        }
    }

    var straight: (a: Vec2, b: Vec2, kind: Int)? {
        switch self {
        case .segment(let a, let b): return (a, b, 0)
        case .ray(let a, let b): return (a, b, 1)
        case .line(let a, let b): return (a, b, 2)
        default: return nil
        }
    }

    func point(at param: Double) -> Vec2? {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            return a.lerp(to: b, param)
        case .circle(let c, let r):
            return c + Vec2(cos(param), sin(param)) * r
        case .polygon(let pts):
            guard pts.count > 1 else { return pts.first }
            let total = polygonLength(pts)
            guard total > 1e-12 else { return pts.first }
            var remaining = param.truncatingRemainder(dividingBy: 1)
            if remaining < 0 { remaining += 1 }
            var target = remaining * total
            for i in 0..<pts.count {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                let l = a.distance(to: b)
                if target <= l {
                    return a.lerp(to: b, target / max(l, 1e-12))
                }
                target -= l
            }
            return pts.first
        case .polyline(let pts):
            guard pts.count > 1 else { return pts.first }
            let total = polygonLength(pts)
            guard total > 1e-12 else { return pts.first }
            let target = min(max(param, 0), 1) * total
            var walked = 0.0
            for i in 0..<(pts.count - 1) {
                let a = pts[i]
                let b = pts[i + 1]
                let l = a.distance(to: b)
                if target <= walked + l {
                    return a.lerp(to: b, (target - walked) / max(l, 1e-12))
                }
                walked += l
            }
            return pts.last
        case .functionPlot:
            return nil
        }
    }

    func nearestParam(to p: Vec2) -> Double {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            let d = b - a
            let denom = d.dot(d)
            guard denom > 1e-12 else { return 0 }
            var t = (p - a).dot(d) / denom
            switch self {
            case .segment: t = min(max(t, 0), 1)
            case .ray: t = max(t, 0)
            default: break
            }
            return t
        case .circle(let c, _):
            var a = (p - c).angle
            if a < 0 { a += .pi * 2 }
            return a
        case .polygon(let pts):
            guard pts.count > 1 else { return 0 }
            let total = polygonLength(pts)
            guard total > 1e-12 else { return 0 }
            var best = 0.0
            var bestDist = Double.greatestFiniteMagnitude
            var walked = 0.0
            for i in 0..<pts.count {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                let l = a.distance(to: b)
                let d = b - a
                let denom = d.dot(d)
                var t = denom > 1e-12 ? (p - a).dot(d) / denom : 0
                t = min(max(t, 0), 1)
                let q = a.lerp(to: b, t)
                let dist = q.distance(to: p)
                if dist < bestDist {
                    bestDist = dist
                    best = (walked + l * t) / total
                }
                walked += l
            }
            return best
        case .polyline(let pts):
            guard pts.count > 1 else { return 0 }
            let total = polygonLength(pts)
            guard total > 1e-12 else { return 0 }
            var best = 0.0
            var bestDist = Double.greatestFiniteMagnitude
            var walked = 0.0
            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i + 1]
                let l = a.distance(to: b)
                let d = b - a
                let denom = d.dot(d)
                var t = denom > 1e-12 ? (p - a).dot(d) / denom : 0
                t = min(max(t, 0), 1)
                let q = a.lerp(to: b, t)
                let dist = q.distance(to: p)
                if dist < bestDist {
                    bestDist = dist
                    best = (walked + l * t) / total
                }
                walked += l
            }
            return best
        case .functionPlot:
            return 0
        }
    }

    func distance(to p: Vec2) -> Double {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            let d = b - a
            let denom = d.dot(d)
            if denom < 1e-12 { return p.distance(to: a) }
            var t = (p - a).dot(d) / denom
            switch self {
            case .segment: t = min(max(t, 0), 1)
            case .ray: t = max(t, 0)
            default: break
            }
            return p.distance(to: a.lerp(to: b, t))
        case .circle(let c, let r):
            return abs(p.distance(to: c) - r)
        case .polygon(let pts):
            guard pts.count > 1 else { return pts.first?.distance(to: p) ?? .infinity }
            var best = Double.greatestFiniteMagnitude
            for i in 0..<pts.count {
                let seg = EvalPath.segment(pts[i], pts[(i + 1) % pts.count])
                best = min(best, seg.distance(to: p))
            }
            return best
        case .polyline(let pts):
            guard pts.count > 1 else { return pts.first?.distance(to: p) ?? .infinity }
            var best = Double.greatestFiniteMagnitude
            for i in 0..<(pts.count - 1) {
                best = min(best, EvalPath.segment(pts[i], pts[i + 1]).distance(to: p))
            }
            return best
        case .functionPlot:
            return .infinity
        }
    }

    var boundingBox: WorldRect? {
        switch self {
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            return WorldRect(minX: min(a.x, b.x), minY: min(a.y, b.y),
                             maxX: max(a.x, b.x), maxY: max(a.y, b.y))
        case .circle(let c, let r):
            return WorldRect(minX: c.x - r, minY: c.y - r, maxX: c.x + r, maxY: c.y + r)
        case .polygon(let pts):
            guard let first = pts.first else { return nil }
            var box = WorldRect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
            for p in pts {
                box.minX = min(box.minX, p.x); box.maxX = max(box.maxX, p.x)
                box.minY = min(box.minY, p.y); box.maxY = max(box.maxY, p.y)
            }
            return box
        case .polyline(let pts):
            guard let first = pts.first else { return nil }
            var box = WorldRect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
            for p in pts {
                box.minX = min(box.minX, p.x); box.maxX = max(box.maxX, p.x)
                box.minY = min(box.minY, p.y); box.maxY = max(box.maxY, p.y)
            }
            return box
        case .functionPlot:
            return nil
        }
    }

    func length(settings: CanvasSettings) -> Double? {
        switch self {
        case .segment(let a, let b): return a.distance(to: b)
        case .circle(let _, let r): return 2 * .pi * r
        case .polygon(let pts): return polygonLength(pts)
        case .polyline(let pts): return polygonLength(pts)
        case .ray, .line, .functionPlot: return nil
        }
    }

    /// Whether a point lies inside a closed polygon. The original
    /// (`routine`) walks the vertices, sums `atan2(cross, dot)` for the
    /// vectors seen from the point, divides by 2π and tests the fractional
    /// part against 0 within 1e-12. That is the winding-number test; a
    /// non-zero winding count means inside.
    func contains(_ p: Vec2) -> Bool {
        guard case .polygon(let pts) = self, pts.count >= 3 else { return false }
        var sum = 0.0
        for i in 0..<pts.count {
            let a = pts[i] - p
            let b = pts[(i + 1) % pts.count] - p
            sum += atan2(a.cross(b), a.dot(b))
        }
        return abs(sum) > .pi
    }

    func intersections(with other: EvalPath) -> [Vec2] {
        if let s1 = straight, let s2 = other.straight {
            return straightIntersections(s1, s2)
        }
        if let s = straight, case .circle(let c, let r) = other {
            return lineCircle(s, c, r)
        }
        if case .circle(let c, let r) = self, let s = other.straight {
            return lineCircle(s, c, r)
        }
        if case .circle(let c1, let r1) = self, case .circle(let c2, let r2) = other {
            return circleCircle(c1, r1, c2, r2)
        }
        if case .polygon(let pts) = self {
            var out: [Vec2] = []
            for i in 0..<max(pts.count, 1) {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                out.append(contentsOf: EvalPath.segment(a, b).intersections(with: other))
            }
            return dedupe(out)
        }
        if case .polygon(let pts) = other {
            var out: [Vec2] = []
            for i in 0..<max(pts.count, 1) {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                out.append(contentsOf: self.intersections(with: .segment(a, b)))
            }
            return dedupe(out)
        }
        if case .polyline(let pts) = self {
            var out: [Vec2] = []
            for i in 0..<max(pts.count - 1, 0) {
                out.append(contentsOf: EvalPath.segment(pts[i], pts[i + 1]).intersections(with: other))
            }
            return dedupe(out)
        }
        if case .polyline(let pts) = other {
            var out: [Vec2] = []
            for i in 0..<max(pts.count - 1, 0) {
                out.append(contentsOf: self.intersections(with: .segment(pts[i], pts[i + 1])))
            }
            return dedupe(out)
        }
        return []
    }
}

private func polygonLength(_ pts: [Vec2]) -> Double {
    guard pts.count > 1 else { return 0 }
    var total = 0.0
    for i in 0..<pts.count {
        total += pts[i].distance(to: pts[(i + 1) % pts.count])
    }
    return total
}

private func dedupe(_ pts: [Vec2]) -> [Vec2] {
    var out: [Vec2] = []
    for p in pts where !out.contains(where: { $0.distance(to: p) < 1e-7 }) {
        out.append(p)
    }
    return out
}

private func straightIntersections(_ s1: (a: Vec2, b: Vec2, kind: Int),
                                   _ s2: (a: Vec2, b: Vec2, kind: Int)) -> [Vec2] {
    let r = s1.b - s1.a
    let s = s2.b - s2.a
    let denom = r.cross(s)
    if abs(denom) < 1e-12 { return [] }
    let qp = s2.a - s1.a
    let t = qp.cross(s) / denom
    let u = qp.cross(r) / denom
    if s1.kind == 0 && (t < -1e-9 || t > 1 + 1e-9) { return [] }
    if s1.kind == 1 && t < -1e-9 { return [] }
    if s2.kind == 0 && (u < -1e-9 || u > 1 + 1e-9) { return [] }
    if s2.kind == 1 && u < -1e-9 { return [] }
    return [s1.a.lerp(to: s1.b, t)]
}

private func lineCircle(_ s: (a: Vec2, b: Vec2, kind: Int), _ c: Vec2, _ r: Double) -> [Vec2] {
    let d = s.b - s.a
    let f = s.a - c
    let a = d.dot(d)
    guard a > 1e-12 else { return [] }
    let b = 2 * f.dot(d)
    let cc = f.dot(f) - r * r
    let disc = b * b - 4 * a * cc
    if disc < -1e-9 { return [] }
    let sq = sqrt(max(disc, 0))
    var ts = [(-b - sq) / (2 * a), (-b + sq) / (2 * a)]
    ts.sort()
    var out: [Vec2] = []
    for t in ts {
        if s.kind == 0 && (t < -1e-9 || t > 1 + 1e-9) { continue }
        if s.kind == 1 && t < -1e-9 { continue }
        let p = s.a.lerp(to: s.b, t)
        if !out.contains(where: { $0.distance(to: p) < 1e-7 }) { out.append(p) }
    }
    return out
}

private func circleCircle(_ c1: Vec2, _ r1: Double, _ c2: Vec2, _ r2: Double) -> [Vec2] {
    let d = c1.distance(to: c2)
    if d < 1e-12 || d > r1 + r2 + 1e-9 || d < abs(r1 - r2) - 1e-9 { return [] }
    let a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
    let h2 = r1 * r1 - a * a
    let h = sqrt(max(h2, 0))
    let mid = c1 + (c2 - c1).normalized() * a
    let perp = (c2 - c1).normalized().perpendicular()
    if h < 1e-9 { return [mid] }
    return [mid + perp * h, mid - perp * h]
}

func clipLine(_ a: Vec2, _ b: Vec2, to rect: WorldRect) -> (Vec2, Vec2)? {
    // Liang–Barsky, used to draw infinite lines and rays inside the viewport.
    var t0 = 0.0
    var t1 = 1.0
    let dx = b.x - a.x
    let dy = b.y - a.y
    let p = [-dx, dx, -dy, dy]
    let q = [a.x - rect.minX, rect.maxX - a.x, a.y - rect.minY, rect.maxY - a.y]
    for i in 0..<4 {
        if abs(p[i]) < 1e-12 {
            if q[i] < 0 { return nil }
        } else {
            let r = q[i] / p[i]
            if p[i] < 0 {
                if r > t1 { return nil }
                if r > t0 { t0 = r }
            } else {
                if r < t0 { return nil }
                if r < t1 { t1 = r }
            }
        }
    }
    return (a.lerp(to: b, t0), a.lerp(to: b, t1))
}

// MARK: - Expression parser

struct Expression {
    private let tokens: [Token]
    private var index = 0
    private var angleUnit: AngleUnit = .radians

    private enum Token: Equatable {
        case number(Double)
        case name(String)
        case op(Character)
        case lparen
        case rparen
        case comma
    }

    init?(_ source: String) {
        var out: [Token] = []
        let chars = Array(source.lowercased())
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber || c == "." {
                var s = String(c)
                i += 1
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    s.append(chars[i]); i += 1
                }
                guard let d = Double(s) else { return nil }
                out.append(.number(d))
                continue
            }
            if c.isLetter || c == "_" || c == "π" {
                var s = String(c)
                i += 1
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                    s.append(chars[i]); i += 1
                }
                out.append(.name(s))
                continue
            }
            switch c {
            case "+", "-", "*", "/", "^": out.append(.op(c))
            case "(": out.append(.lparen)
            case ")": out.append(.rparen)
            case ",": out.append(.comma)
            default: return nil
            }
            i += 1
        }
        if out.isEmpty { return nil }
        tokens = out
    }

    mutating func setAngleUnit(_ unit: AngleUnit) { angleUnit = unit }

    mutating func evaluate(x: Double = 0, variables: [String: Double] = [:]) -> Double? {
        index = 0
        var vars = variables
        vars["x"] = x
        return parseExpression(vars)
    }

    private mutating func peek() -> Token? {
        index < tokens.count ? tokens[index] : nil
    }
    private mutating func take() -> Token? {
        guard index < tokens.count else { return nil }
        defer { index += 1 }
        return tokens[index]
    }
    private mutating func match(_ t: Token) -> Bool {
        if peek() == t { index += 1; return true }
        return false
    }

    private mutating func parseExpression(_ vars: [String: Double]) -> Double? {
        var value = parseTerm(vars)
        while let tok = peek(), case .op(let op) = tok, op == "+" || op == "-" {
            _ = take()
            guard let rhs = parseTerm(vars), let lhs = value else { return nil }
            value = op == "+" ? lhs + rhs : lhs - rhs
        }
        return value
    }

    private mutating func parseTerm(_ vars: [String: Double]) -> Double? {
        var value = parseUnary(vars)
        while let tok = peek(), case .op(let op) = tok, op == "*" || op == "/" {
            _ = take()
            guard let rhs = parseUnary(vars), let lhs = value else { return nil }
            value = op == "*" ? lhs * rhs : (abs(rhs) < 1e-15 ? nil : lhs / rhs)
        }
        return value
    }

    private mutating func parseUnary(_ vars: [String: Double]) -> Double? {
        if let tok = peek(), case .op(let op) = tok, op == "-" {
            _ = take()
            return parseUnary(vars).map { -$0 }
        }
        if let tok = peek(), case .op(let op) = tok, op == "+" {
            _ = take()
            return parseUnary(vars)
        }
        return parsePower(vars)
    }

    private mutating func parsePower(_ vars: [String: Double]) -> Double? {
        guard let base = parseAtom(vars) else { return nil }
        if let tok = peek(), case .op(let op) = tok, op == "^" {
            _ = take()
            guard let exp = parseUnary(vars) else { return nil }
            return pow(base, exp)
        }
        return base
    }

    private mutating func parseAtom(_ vars: [String: Double]) -> Double? {
        guard let tok = take() else { return nil }
        switch tok {
        case .number(let d): return d
        case .lparen:
            let v = parseExpression(vars)
            guard match(.rparen) else { return nil }
            return v
        case .name(let name):
            if let v = vars[name] { return v }
            switch name {
            case "pi", "π": return .pi
            case "e": return M_E
            case "sin", "cos", "tan", "asin", "acos", "atan", "sqrt", "abs", "ln", "log", "exp", "floor", "ceil", "round":
                guard match(.lparen), let arg = parseExpression(vars), match(.rparen) else { return nil }
                switch name {
                case "sin": return sin(trigInput(arg))
                case "cos": return cos(trigInput(arg))
                case "tan":
                    let t = tan(trigInput(arg))
                    return abs(t) > 1e12 ? nil : t
                case "asin": return asin(arg)
                case "acos": return acos(arg)
                case "atan": return atan(arg)
                case "sqrt": return arg < 0 ? nil : sqrt(arg)
                case "abs": return abs(arg)
                case "ln", "log": return arg <= 0 ? nil : log(arg)
                case "exp": return exp(arg)
                case "floor": return floor(arg)
                case "ceil": return ceil(arg)
                case "round": return arg.rounded()
                default: return nil
                }
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func trigInput(_ x: Double) -> Double {
        angleUnit == .radians ? x : x * .pi / 180
    }
}

// MARK: - Style

struct RGBA: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    var color: Color { Color(red: r, green: g, blue: b).opacity(a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

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
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

enum PointShape: String, Codable, CaseIterable, Identifiable {
    case filled, hollow, square, cross
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

struct ObjectStyle: Codable, Hashable {
    var color: RGBA = .ink
    var lineWidth: Double = 1.5
    var dash: DashStyle = .solid
    var pointSize: Double = 5.5
    var pointShape: PointShape = .filled
    var fillOpacity: Double = 0.12
}

enum LengthUnit: String, Codable, CaseIterable, Identifiable {
    case cm, inches, pixels
    var id: String { rawValue }
    var name: String { self == .cm ? "Centimeters" : self == .inches ? "Inches" : "Pixels" }
    var short: String { self == .cm ? "cm" : self == .inches ? "in" : "px" }

    /// The original keeps canvases in screen points and converts for display:
    /// `routine` builds the factor table `[1, 72 / 2.54, 72]` for the three
    /// distance units, and `routine` divides the stored value by the selected
    /// factor. Read that as pixels, centimetres, inches. This rebuild stores
    /// world coordinates in centimetres, so these are centimetres per one
    /// display unit. (Pixels is the original's 72-ppi point, not a 96-dpi CSS
    /// pixel.)
    var perUnit: Double {
        switch self {
        case .cm: return 1
        case .inches: return 2.54
        case .pixels: return SketchMetrics.centimetresPerInch / SketchMetrics.pointsPerInch
        }
    }
}

enum SketchMetrics {
    /// Classic Mac screen resolution used by the original: 72 points per inch.
    static let pointsPerInch = 72.0
    static let centimetresPerInch = 2.54
    /// 100% zoom: 72 points per inch ÷ 2.54 cm per inch.
    static let pixelsPerCentimetre = pointsPerInch / centimetresPerInch
}

enum AngleUnit: String, Codable, CaseIterable, Identifiable {
    case degrees, directedDegrees, radians
    var id: String { rawValue }
    var name: String {
        switch self {
        case .degrees: return "Degrees"
        case .directedDegrees: return "Directed degrees"
        case .radians: return "Radians"
        }
    }
    var short: String { self == .radians ? "rad" : "°" }
}
