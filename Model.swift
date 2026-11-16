import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Object model

enum MeasureKind: String, Codable, CaseIterable, Identifiable {
    case distance, length, perimeter, circumference, angle, area, radius, ratio,
         coordinates, equation, slope
    var id: String { rawValue }
    var title: String {
        switch self {
        case .distance: return "Distance"
        case .length: return "Length"
        case .perimeter: return "Perimeter"
        case .circumference: return "Circumference"
        case .angle: return "Angle"
        case .area: return "Area"
        case .radius: return "Radius"
        case .ratio: return "Ratio"
        case .coordinates: return "Coordinates"
        case .equation: return "Equation"
        case .slope: return "Slope"
        }
    }
}

enum TransformKind: String, Codable, CaseIterable, Identifiable {
    case reflect, rotate, translate, dilate
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct TransformSpec: Codable, Hashable {
    var kind: TransformKind
    var reference: UUID?
    var secondReference: UUID?
    var angle: Double = 90
    var factor: Double = 2
    var dx: Double = 1
    var dy: Double = 0
}

enum ObjectKind: Codable, Hashable {
    case freePoint
    case pointOnPath(path: UUID, param: Double)
    case midpoint(a: UUID, b: UUID)
    case intersection(a: UUID, b: UUID, index: Int)
    case segment(a: UUID, b: UUID)
    case ray(a: UUID, b: UUID)
    case line(a: UUID, b: UUID)
    case perpendicular(line: UUID, point: UUID)
    case parallel(line: UUID, point: UUID)
    case angleBisector(a: UUID, vertex: UUID, c: UUID)
    case circle(center: UUID, through: UUID)
    case polygon(vertices: [UUID])
    case angle(a: UUID, vertex: UUID, c: UUID)
    case measurement(MeasureKind, refs: [UUID])
    case calculation(String)
    case caption(String)
    case functionPlot(String)
    case transformed(source: UUID, spec: TransformSpec)
    /// The sampled path of `target` as `driver` (a point on a path) sweeps
    /// through its domain, as in the original's Locus command.
    case locus(driver: UUID, target: UUID)
}

struct SketchObject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: ObjectKind
    var label: String = ""
    var showLabel: Bool = true
    var visible: Bool = true
    var style: ObjectStyle = ObjectStyle()
    var offset: Vec2 = .zero
    var position: Vec2? = nil
    var order: Int = 0
    var isLocked: Bool = false

    var isPointLike: Bool {
        switch kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return true
        case .transformed(_, _):
            return false
        default:
            return false
        }
    }

    var isPathLike: Bool {
        switch kind {
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector,
             .circle, .polygon, .functionPlot, .transformed, .locus:
            return true
        default:
            return false
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
}

struct SketchDocument: Codable {
    var objects: [SketchObject] = []
    var settings: CanvasSettings = CanvasSettings()
    var title: String = "Untitled Sketch"
}

struct EvalResult {
    var point: Vec2?
    var path: EvalPath?
    var text: String?
    var anchor: Vec2?
    var value: Double?
    var anglePoints: (Vec2, Vec2, Vec2)?
    var angleValue: Double?
}

struct GeometryEval {
    let objects: [UUID: SketchObject]
    let settings: CanvasSettings
    private var cache: [UUID: EvalResult] = [:]
    private var visiting: Set<UUID> = []

    init(objects: [SketchObject], settings: CanvasSettings) {
        self.objects = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        self.settings = settings
    }

    mutating func evaluate(_ id: UUID) -> EvalResult {
        if let cached = cache[id] { return cached }
        guard let object = objects[id] else { return EvalResult() }
        if visiting.contains(id) { return EvalResult() }
        visiting.insert(id)
        defer { visiting.remove(id) }

        var result = EvalResult()
        switch object.kind {
        case .freePoint:
            result.point = object.position ?? .zero

        case .pointOnPath(let parent, let param):
            if let path = path(parent) {
                result.point = path.point(at: param)
            }

        case .midpoint(let a, let b):
            if let pa = point(a), let pb = point(b) {
                result.point = pa.lerp(to: pb, 0.5)
            }

        case .intersection(let a, let b, let index):
            if let pa = path(a), let pb = path(b) {
                let hits = pa.intersections(with: pb)
                if index >= 0 && index < hits.count { result.point = hits[index] }
            }

        case .segment(let a, let b):
            if let pa = point(a), let pb = point(b) { result.path = .segment(pa, pb) }

        case .ray(let a, let b):
            if let pa = point(a), let pb = point(b) { result.path = .ray(pa, pb) }

        case .line(let a, let b):
            if let pa = point(a), let pb = point(b) { result.path = .line(pa, pb) }

        case .perpendicular(let lineID, let pointID):
            if let s = path(lineID)?.straight, let p = point(pointID) {
                let direction = (s.b - s.a).perpendicular().normalized()
                result.path = .line(p, p + direction)
            }

        case .parallel(let lineID, let pointID):
            if let s = path(lineID)?.straight, let p = point(pointID) {
                let direction = (s.b - s.a).normalized()
                result.path = .line(p, p + direction)
            }

        case .angleBisector(let a, let vertex, let c):
            if let pa = point(a), let pv = point(vertex), let pc = point(c) {
                let u = (pa - pv).normalized()
                let v = (pc - pv).normalized()
                var d = (u + v).normalized()
                if d.length < 1e-9 { d = u.perpendicular() }
                result.path = .line(pv, pv + d)
            }

        case .circle(let center, let through):
            if let pc = point(center), let pt = point(through) {
                result.path = .circle(pc, pc.distance(to: pt))
            }

        case .polygon(let vertices):
            let pts = vertices.compactMap { point($0) }
            if pts.count == vertices.count, pts.count >= 2 {
                result.path = .polygon(pts)
            }

        case .angle(let a, let vertex, let c):
            if let pa = point(a), let pv = point(vertex), let pc = point(c) {
                let u = (pa - pv).normalized()
                let v = (pc - pv).normalized()
                let unsigned = acos(min(max(u.dot(v), -1), 1))
                // Plain degrees are undirected (0–180°); directed degrees and
                // radians keep the sign, as in the original's preferences.
                let raw = settings.angleUnit == .degrees ? unsigned : atan2(u.cross(v), u.dot(v))
                var bis = (u + v).normalized()
                if bis.length < 1e-9 { bis = u.perpendicular() }
                result.value = raw
                result.angleValue = raw
                result.anglePoints = (pa, pv, pc)
                result.anchor = pv + bis * 0.72
                let angleText = formatAngle(raw)
                result.text = object.label.isEmpty ? angleText : "\(object.label) = \(angleText)"
            }

        case .measurement(let kind, let refs):
            result = measurement(kind: kind, refs: refs)

        case .calculation(let expression):
            var parser = Expression(expression)
            parser?.setAngleUnit(settings.angleUnit)
            let vars = calculationVariables()
            if var p = parser, let value = p.evaluate(variables: vars) {
                let text = "\(expression) = \(formatNumber(value, precision: settings.precision))"
                result.text = text
                result.value = value
                result.anchor = objects.values.first(where: {
                    if case .measurement = $0.kind { return true }
                    return false
                })?.position ?? Vec2(0, 0)
            } else {
                result.text = "\(expression) = undefined"
            }

        case .caption(let text):
            result.text = text
            result.anchor = object.position ?? .zero

        case .functionPlot(let expression):
            result.path = .functionPlot(expression)

        case .transformed(let source, let spec):
            if let src = objects[source] {
                let sourceResult = evaluate(source)
                if let p = sourceResult.point, let mapped = map(p, spec) {
                    result.point = mapped
                } else if let p = sourceResult.path, let mapped = map(p, spec) {
                    result.path = mapped
                }
                _ = src
            }

        case .locus(let driver, let target):
            if let curve = locusCurve(driver: driver, target: target) {
                result.path = .polyline(curve)
            }
        }

        if result.anchor != nil {
            result.anchor = result.anchor! + object.offset
        }
        cache[id] = result
        return result
    }

    /// Samples a driven object while its driver sweeps the driver's whole
    /// path. reference application calls this a locus; a point on an open path uses the
    /// path parameter from 0 to 1, a point on a circle a full counter-clockwise
    /// turn, matching the original's animation direction rule.
    private mutating func locusCurve(driver: UUID, target: UUID) -> [Vec2]? {
        guard let driverObject = objects[driver],
              case .pointOnPath(let pathID, _) = driverObject.kind,
              let driverPath = path(pathID),
              objects[target] != nil else { return nil }
        if case .locus = objects[target]?.kind { return nil }
        let closed: Bool
        if case .circle = driverPath { closed = true } else { closed = false }
        let steps = 96
        var base = Array(objects.values)
        guard let i = base.firstIndex(where: { $0.id == driver }) else { return nil }
        var points: [Vec2] = []
        for step in 0...steps {
            let unit = Double(step) / Double(steps)
            let param = closed ? unit * 2 * .pi : unit
            base[i].kind = .pointOnPath(path: pathID, param: param)
            var sample = GeometryEval(objects: base, settings: settings)
            if let p = sample.evaluate(target).point,
               points.last?.distance(to: p) ?? 1 > 1e-6 {
                points.append(p)
            }
        }
        return points.count > 1 ? points : nil
    }

    mutating func point(_ id: UUID) -> Vec2? { evaluate(id).point }
    mutating func path(_ id: UUID) -> EvalPath? { evaluate(id).path }

    // MARK: measurement

    private mutating func measurement(kind: MeasureKind, refs: [UUID]) -> EvalResult {
        var result = EvalResult()
        func labels(_ ids: [UUID]) -> String {
            ids.map { name(of: $0) }.joined()
        }
        switch kind {
        case .distance:
            if refs.count >= 2, let a = point(refs[0]), let b = point(refs[1]) {
                let v = a.distance(to: b)
                result.value = v
                result.text = "m \(labels(Array(refs.prefix(2)))) = \(formatLength(v))"
                result.anchor = a.lerp(to: b, 0.5) + Vec2(0, 0.28)
            }
        case .length:
            if let first = refs.first, let p = path(first), let v = p.length(settings: settings) {
                result.value = v
                result.text = "m \(name(of: first)) = \(formatLength(v))"
                result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, 0.28)
            }
        case .perimeter:
            if let first = refs.first, let p = path(first), case .polygon(let pts) = p {
                let v = zip(pts, pts.dropFirst() + [pts[0]]).map { $0.distance(to: $1) }.reduce(0, +)
                result.value = v
                result.text = "Perimeter \(name(of: first)) = \(formatLength(v))"
                result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, 0.3)
            }
        case .circumference:
            if let first = refs.first, let p = path(first), case .circle(let c, let r) = p {
                let v = 2 * Double.pi * r
                result.value = v
                result.text = "Circumference \(name(of: first)) = \(formatLength(v))"
                result.anchor = c + Vec2(0, r + 0.3)
            }
        case .angle:
            if refs.count >= 3, let a = point(refs[0]), let v = point(refs[1]), let c = point(refs[2]) {
                let u = (a - v).normalized()
                let w = (c - v).normalized()
                let unsigned = acos(min(max(u.dot(w), -1), 1))
                let angle = settings.angleUnit == .degrees ? unsigned : atan2(u.cross(w), u.dot(w))
                result.value = angle
                result.anglePoints = (a, v, c)
                result.angleValue = angle
                var bis = (u + w).normalized()
                if bis.length < 1e-9 { bis = u.perpendicular() }
                result.text = "m∠\(labels(Array(refs.prefix(3)))) = \(formatAngle(angle))"
                result.anchor = v + bis * 0.95
            }
        case .area:
            if let first = refs.first, let p = path(first) {
                if case .polygon(let pts) = p, pts.count >= 3 {
                    let v = abs(zip(pts, pts.dropFirst() + [pts[0]]).map { $0.x * $1.y - $1.x * $0.y }.reduce(0, +)) / 2
                    result.value = v
                    result.text = "Area \(name(of: first)) = \(formatArea(v))"
                    result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, -0.3)
                } else if case .circle(_, let r) = p {
                    let v = Double.pi * r * r
                    result.value = v
                    result.text = "Area \(name(of: first)) = \(formatArea(v))"
                    result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, -0.3)
                }
            }
        case .radius:
            if let first = refs.first, let p = path(first), case .circle(let c, let r) = p {
                result.value = r
                result.text = "r \(name(of: first)) = \(formatLength(r))"
                result.anchor = c + Vec2(r * 0.55, 0.3)
            }
        case .ratio:
            if refs.count >= 2, let p1 = path(refs[0]), let p2 = path(refs[1]),
               let l1 = p1.length(settings: settings), let l2 = p2.length(settings: settings), l2 > 1e-12 {
                let v = l1 / l2
                result.value = v
                result.text = "\(name(of: refs[0]))/\(name(of: refs[1])) = \(formatNumber(v, precision: settings.precision))"
                result.anchor = (p1.boundingBox?.center ?? .zero) + Vec2(0, 0.3)
            }
        case .coordinates:
            if let first = refs.first, let p = point(first) {
                let name = name(of: first)
                let x = p.x / settings.lengthUnit.perUnit
                let y = p.y / settings.lengthUnit.perUnit
                result.value = p.x
                result.text = "\(name) = (\(formatNumber(x, precision: settings.precision)), \(formatNumber(y, precision: settings.precision))) \(settings.lengthUnit.short)"
                result.anchor = p + Vec2(0.55, 0.5)
            }
        case .equation:
            if let first = refs.first, let p = path(first) {
                let prefix = name(of: first)
                if let s = p.straight {
                    let d = s.b - s.a
                    if abs(d.x) < 1e-9 {
                        result.text = "\(prefix): x = \(formatNumber(s.a.x / settings.lengthUnit.perUnit, precision: settings.precision))"
                    } else {
                        let m = d.y / d.x
                        let b = s.a.y - m * s.a.x
                        result.text = "\(prefix): y = \(formatNumber(m, precision: settings.precision))x \(b >= 0 ? "+" : "−") \(formatNumber(abs(b), precision: settings.precision))"
                    }
                } else if case .circle(let c, let r) = p {
                    let x = c.x / settings.lengthUnit.perUnit
                    let y = c.y / settings.lengthUnit.perUnit
                    let rr = r / settings.lengthUnit.perUnit
                    result.text = "\(prefix): (x \(x >= 0 ? "−" : "+") \(formatNumber(abs(x), precision: settings.precision)))² + (y \(y >= 0 ? "−" : "+") \(formatNumber(abs(y), precision: settings.precision)))² = \(formatNumber(rr * rr, precision: settings.precision))"
                }
                result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, 0.3)
            }
        case .slope:
            if let first = refs.first, let p = path(first), let s = p.straight {
                let d = s.b - s.a
                if abs(d.x) < 1e-9 {
                    result.text = "Slope \(name(of: first)) = undefined"
                } else {
                    let m = d.y / d.x
                    result.value = m
                    result.text = "Slope \(name(of: first)) = \(formatNumber(m, precision: settings.precision))"
                }
                result.anchor = (p.boundingBox?.center ?? .zero) + Vec2(0, 0.28)
            }
        }
        return result
    }

    func name(of id: UUID) -> String {
        guard let object = objects[id] else { return "?" }
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return object.label.isEmpty ? "P" : object.label
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b):
            return (objects[a]?.label ?? "") + (objects[b]?.label ?? "")
        case .circle(let c, _):
            return object.label.isEmpty ? "circle \((objects[c]?.label ?? ""))" : object.label
        case .polygon(let vertices):
            return vertices.compactMap { objects[$0]?.label }.joined()
        default:
            return object.label
        }
    }

    private mutating func calculationVariables() -> [String: Double] {
        var out: [String: Double] = [:]
        for object in objects.values {
            if case .measurement(let kind, let refs) = object.kind {
                let r = measurement(kind: kind, refs: refs)
                if let v = r.value, !object.label.isEmpty {
                    out[object.label.replacingOccurrences(of: " ", with: "_")] = v
                }
            }
        }
        return out
    }

    // MARK: transform

    private mutating func map(_ p: Vec2, _ spec: TransformSpec) -> Vec2? {
        switch spec.kind {
        case .reflect:
            guard let ref = spec.reference, let s = path(ref)?.straight else { return nil }
            let a = s.a
            let d = (s.b - s.a).normalized()
            let t = (p - a).dot(d)
            let foot = a + d * t
            return foot * 2 - p
        case .rotate:
            guard let ref = spec.reference, let c = point(ref) else { return nil }
            return c + (p - c).rotated(by: spec.angle * .pi / 180)
        case .translate:
            if let a = spec.reference, let b = spec.secondReference,
               let pa = point(a), let pb = point(b) {
                return p + (pb - pa)
            }
            return p + Vec2(spec.dx, spec.dy)
        case .dilate:
            guard let ref = spec.reference, let c = point(ref) else { return nil }
            return c + (p - c) * spec.factor
        }
    }

    private mutating func map(_ path: EvalPath, _ spec: TransformSpec) -> EvalPath? {
        switch path {
        case .segment(let a, let b):
            guard let ma = map(a, spec), let mb = map(b, spec) else { return nil }
            return .segment(ma, mb)
        case .ray(let a, let b):
            guard let ma = map(a, spec), let mb = map(b, spec) else { return nil }
            return .ray(ma, mb)
        case .line(let a, let b):
            guard let ma = map(a, spec), let mb = map(b, spec) else { return nil }
            return .line(ma, mb)
        case .circle(let c, let r):
            guard let mc = map(c, spec), let edge = map(c + Vec2(r, 0), spec) else { return nil }
            return .circle(mc, mc.distance(to: edge))
        case .polygon(let pts):
            let mapped = pts.compactMap { map($0, spec) }
            return mapped.count == pts.count ? .polygon(mapped) : nil
        case .polyline(let pts):
            let mapped = pts.compactMap { map($0, spec) }
            return mapped.count == pts.count ? .polyline(mapped) : nil
        case .functionPlot:
            return nil
        }
    }

    // MARK: formatting

    func formatNumber(_ value: Double, precision: Int) -> String {
        if !value.isFinite { return "undefined" }
        if abs(value) >= 1_000_000 { return String(format: "%.3g", value) }
        return String(format: "%.\(max(0, min(precision, 6)))f", value)
    }

    func formatLength(_ cm: Double) -> String {
        let v = cm / settings.lengthUnit.perUnit
        return "\(formatNumber(v, precision: settings.precision)) \(settings.lengthUnit.short)"
    }

    func formatArea(_ cm2: Double) -> String {
        let v = cm2 / (settings.lengthUnit.perUnit * settings.lengthUnit.perUnit)
        return "\(formatNumber(v, precision: settings.precision)) \(settings.lengthUnit.short)²"
    }

    func formatAngle(_ radians: Double) -> String {
        if settings.angleUnit != .radians {
            return "\(formatNumber(radians * 180 / .pi, precision: settings.precision))°"
        }
        return "\(formatNumber(radians, precision: settings.precision)) rad"
    }
}

// MARK: - Tools

enum SketchTool: String, CaseIterable, Identifiable {
    case select, point, segment, ray, line, circle, polygon, angle, text
    var id: String { rawValue }
    var title: String {
        switch self {
        case .select: return "Select"
        case .point: return "Point"
        case .segment: return "Segment"
        case .ray: return "Ray"
        case .line: return "Line"
        case .circle: return "Circle"
        case .polygon: return "Polygon"
        case .angle: return "Angle"
        case .text: return "Text"
        }
    }
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .point: return "smallcircle.filled.circle"
        case .segment: return "line.diagonal"
        case .ray: return "arrow.up.right"
        case .line: return "line.diagonal.arrow"
        case .circle: return "circle"
        case .polygon: return "pentagon"
        case .angle: return "angle"
        case .text: return "textformat"
        }
    }
    var shortcut: KeyEquivalent {
        switch self {
        case .select: return "v"
        case .point: return "p"
        case .segment: return "s"
        case .ray: return "r"
        case .line: return "l"
        case .circle: return "c"
        case .polygon: return "g"
        case .angle: return "a"
        case .text: return "t"
        }
    }
    var hint: String {
        switch self {
        case .select: return "Click to select. Drag a point to move it. Shift-click adds to the selection."
        case .point: return "Click empty space for a free point, or click a line or circle to attach a point to it."
        case .segment: return "Click two points to draw a segment."
        case .ray: return "Click a start point, then a point the ray passes through."
        case .line: return "Click two points to draw an infinite line."
        case .circle: return "Click the center, then a point on the circle."
        case .polygon: return "Click the vertices. Click the first point again or press Return to close."
        case .angle: return "Click three points: first side, vertex, second side."
        case .text: return "Click the canvas to add a caption."
        }
    }
}

// MARK: - The editing model

final class SketchModel: ObservableObject {
    @Published var document = SketchDocument()
    @Published var selection: [UUID] = []
    @Published var tool: SketchTool = .select
    @Published var draft: [UUID] = []
    @Published var hoverWorld: Vec2?
    @Published var isPointerOverCanvas = false
    @Published var inspectorVisible = true
    @Published var statusMessage: String = ""
    @Published var currentURL: URL?
    @Published var isDirty = false
    @Published var showAbout = false
    /// Animation (the original's Display > Animate).
    @Published var animationPointID: UUID?
    @Published var tracedIDs: Set<UUID> = []
    @Published var tracePaths: [UUID: [Vec2]] = [:]
    private var animationDirection: Double = 1

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var builtInSample = false

    struct Snapshot {
        var objects: [SketchObject]
        var selection: [UUID]
    }

    var objects: [SketchObject] {
        get { document.objects }
        set { document.objects = newValue }
    }
    var settings: CanvasSettings {
        get { document.settings }
        set { document.settings = newValue }
    }

    var selectedObjects: [SketchObject] {
        selection.compactMap { id in objects.first(where: { $0.id == id }) }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: document lifecycle

    static func sample() -> SketchModel {
        let model = SketchModel()
        model.builtInSample = true
        model.document.title = "Untitled Sketch"
        model.seedSample()
        model.undoStack.removeAll()
        model.redoStack.removeAll()
        model.isDirty = false
        return model
    }

    static func blank() -> SketchModel {
        let model = SketchModel()
        model.builtInSample = false
        return model
    }

    func newSketch() {
        checkpoint()
        objects = []
        selection = []
        draft = []
        document.title = "Untitled Sketch"
        currentURL = nil
        isDirty = false
        undoStack.removeAll()
        redoStack.removeAll()
        statusMessage = "New sketch"
    }

    private func seedSample() {
        let a = add(kind: .freePoint, label: "A", position: Vec2(-7.0, -3.3), silent: true)
        let b = add(kind: .freePoint, label: "B", position: Vec2(5.0, -3.3), silent: true)
        let c = add(kind: .freePoint, label: "C", position: Vec2(1.2, 5.5), silent: true)

        let poly = add(kind: .polygon(vertices: [a, b, c]), silent: true)
        if let idx = index(of: poly) {
            objects[idx].style.color = .accent
            objects[idx].style.fillOpacity = 0.07
        }
        let ab = add(kind: .segment(a: a, b: b), silent: true)
        let bc = add(kind: .segment(a: b, b: c), silent: true)
        let ca = add(kind: .segment(a: c, b: a), silent: true)

        let d = add(kind: .midpoint(a: a, b: b), label: "D", silent: true)
        let e = add(kind: .midpoint(a: b, b: c), label: "E", silent: true)
        let perp1 = add(kind: .perpendicular(line: ab, point: d), silent: true)
        let perp2 = add(kind: .perpendicular(line: bc, point: e), silent: true)
        if let i = index(of: perp1) { objects[i].style.dash = .dashed; objects[i].style.color = .secondaryInk }
        if let i = index(of: perp2) { objects[i].style.dash = .dashed; objects[i].style.color = .secondaryInk }

        let o = add(kind: .intersection(a: perp1, b: perp2, index: 0), label: "O", silent: true)
        let circle = add(kind: .circle(center: o, through: a), silent: true)
        if let i = index(of: circle) {
            objects[i].style.color = .violet
            objects[i].style.lineWidth = 1.8
            objects[i].style.fillOpacity = 0.035
        }

        let ang = add(kind: .angle(a: a, vertex: b, c: c),
                      kindLabel: "m∠ABC", silent: true)
        if let i = index(of: ang) {
            // The bisector points up-left here; keep the card to the right of B
            // so it does not cover the vertex or its label.
            objects[i].offset = Vec2(1.05, 0.15)
        }
        let dist = add(kind: .measurement(.length, refs: [ab]),
                       kindLabel: "m AB", silent: true)
        if let i = index(of: dist) {
            // Keep the length card clear of the angle card at B; both can be
            // dragged separately afterwards, as in the original.
            objects[i].offset = Vec2(0, -1.15)
        }
        let coords = add(kind: .measurement(.coordinates, refs: [o]),
                         kindLabel: "O", silent: true)
        if let i = index(of: coords) {
            objects[i].offset = Vec2(0.6, 0.55)
        }
        let caption = add(kind: .caption("Drag A, B or C — the whole construction follows."),
                          position: Vec2(-9.2, 7.4), silent: true)
        if let i = index(of: caption) {
            objects[i].style.color = .secondaryInk
            objects[i].showLabel = true
        }
    }

    func loadSample() {
        checkpoint()
        objects = []
        selection = []
        draft = []
        seedSample()
        document.title = "Welcome Sketch"
        currentURL = nil
        isDirty = true
        statusMessage = "Sample sketch loaded"
    }

    // MARK: undo

    private func snapshot() -> Snapshot {
        Snapshot(objects: objects, selection: selection)
    }

    func checkpoint() {
        undoStack.append(snapshot())
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll()
        isDirty = true
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        objects = snap.objects
        selection = snap.selection
        isDirty = true
        statusMessage = "Undo"
    }

    func redo() {
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        objects = snap.objects
        selection = snap.selection
        isDirty = true
        statusMessage = "Redo"
    }

    // MARK: object helpers

    func index(of id: UUID) -> Int? { objects.firstIndex(where: { $0.id == id }) }

    func objectByID(_ id: UUID) -> SketchObject? { objects.first(where: { $0.id == id }) }

    @discardableResult
    func add(kind: ObjectKind,
             label: String? = nil,
             kindLabel: String? = nil,
             position: Vec2? = nil,
             style: ObjectStyle = ObjectStyle(),
             silent: Bool = false) -> UUID {
        if !silent { checkpoint() }
        var object = SketchObject(kind: kind)
        object.label = label ?? kindLabel ?? autoLabel(for: kind)
        object.position = position
        object.style = style
        object.order = (objects.map(\.order).max() ?? 0) + 1
        object.showLabel = isLabelWorthy(kind)
        objects.append(object)
        if !silent { isDirty = true }
        return object.id
    }

    private func isLabelWorthy(_ kind: ObjectKind) -> Bool {
        switch kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection: return true
        case .caption, .measurement, .calculation, .angle: return true
        default: return false
        }
    }

    private func autoLabel(for kind: ObjectKind) -> String {
        switch kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return nextPointLabel()
        default:
            return ""
        }
    }

    func nextPointLabel() -> String {
        let used = Set(objects.filter { $0.isPointLike }.map(\.label))
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for letter in letters {
            let s = String(letter)
            if !used.contains(s) { return s }
        }
        var i = 1
        while true {
            for letter in letters {
                let s = "\(letter)\(i)"
                if !used.contains(s) { return s }
            }
            i += 1
        }
    }

    func displayName(for object: SketchObject) -> String {
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return object.label.isEmpty ? "Point" : "Point \(object.label)"
        case .segment(let a, let b):
            return "Segment \(objectByID(a)?.label ?? "")\(objectByID(b)?.label ?? "")"
        case .ray(let a, let b):
            return "Ray \(objectByID(a)?.label ?? "")\(objectByID(b)?.label ?? "")"
        case .line(let a, let b):
            return "Line \(objectByID(a)?.label ?? "")\(objectByID(b)?.label ?? "")"
        case .perpendicular:
            return "Perpendicular"
        case .parallel:
            return "Parallel"
        case .angleBisector:
            return "Angle Bisector"
        case .circle:
            return "Circle"
        case .polygon:
            return "Polygon"
        case .angle:
            return "Angle \(object.label)"
        case .measurement(let kind, _):
            return "\(kind.title) \(object.label)"
        case .calculation:
            return "Calculation"
        case .caption:
            return "Text"
        case .functionPlot:
            return "Function Plot"
        case .transformed:
            return "Transformed Image"
        case .locus:
            return "Locus"
        }
    }

    func symbol(for object: SketchObject) -> String {
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection: return "circle.fill"
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector: return "line.diagonal"
        case .circle: return "circle"
        case .polygon: return "pentagon"
        case .angle: return "angle"
        case .measurement, .calculation: return "ruler"
        case .caption: return "textformat"
        case .functionPlot: return "function"
        case .transformed: return "arrow.triangle.2.circlepath"
        case .locus: return "scribble"
        }
    }

    // MARK: geometry access

    func evaluator() -> GeometryEval {
        GeometryEval(objects: objects, settings: settings)
    }

    func evaluated(_ id: UUID) -> EvalResult {
        var e = evaluator()
        return e.evaluate(id)
    }

    func screenPoint(_ p: Vec2, size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + (p.x - settings.center.x) * settings.scale,
                y: size.height / 2 - (p.y - settings.center.y) * settings.scale)
    }

    func worldPoint(_ p: CGPoint, size: CGSize) -> Vec2 {
        Vec2(settings.center.x + (p.x - size.width / 2) / settings.scale,
             settings.center.y - (p.y - size.height / 2) / settings.scale)
    }

    func visibleRect(size: CGSize) -> WorldRect {
        let tl = worldPoint(CGPoint(x: 0, y: 0), size: size)
        let br = worldPoint(CGPoint(x: size.width, y: size.height), size: size)
        return WorldRect(minX: min(tl.x, br.x), minY: min(tl.y, br.y),
                         maxX: max(tl.x, br.x), maxY: max(tl.y, br.y))
    }

    func zoom(by factor: Double, size: CGSize? = nil) {
        let old = settings.scale
        settings.scale = min(max(old * factor, 12), 420)
        if let size, size.width > 0, size.height > 0 {
            // Keep the world point under the canvas centre fixed.
            _ = size
        }
        isDirty = true
    }

    func setZoom(_ value: Double) {
        settings.scale = min(max(value, 12), 420)
        isDirty = true
    }

    func pan(dx: Double, dy: Double) {
        settings.center = settings.center - Vec2(dx / settings.scale, -dy / settings.scale)
        isDirty = true
    }

    func fitCanvas(size: CGSize) {
        var e = evaluator()
        var pts: [Vec2] = []
        for object in objects where object.visible {
            let r = e.evaluate(object.id)
            if let p = r.point { pts.append(p) }
            if let b = r.path?.boundingBox {
                if b.width.isFinite && b.height.isFinite && b.width < 1_000 && b.height < 1_000 {
                    pts.append(Vec2(b.minX, b.minY)); pts.append(Vec2(b.maxX, b.maxY))
                }
            }
        }
        guard !pts.isEmpty, size.width > 40, size.height > 40 else {
            settings.center = Vec2(0, 0)
            settings.scale = SketchMetrics.pixelsPerCentimetre
            return
        }
        var box = WorldRect(minX: pts[0].x, minY: pts[0].y, maxX: pts[0].x, maxY: pts[0].y)
        for p in pts {
            box.minX = min(box.minX, p.x); box.maxX = max(box.maxX, p.x)
            box.minY = min(box.minY, p.y); box.maxY = max(box.maxY, p.y)
        }
        let w = max(box.width, 2), h = max(box.height, 2)
        settings.center = box.center
        settings.scale = min(max(min(size.width / (w * 1.35), size.height / (h * 1.35)), 18), 180)
        isDirty = true
    }

    // MARK: hit testing

    func hitTest(_ p: Vec2, tolerance: Double) -> UUID? {
        let tol = max(tolerance, 0.03)
        var e = evaluator()
        var best: (UUID, Double)?
        // Points first.
        for object in objects.reversed() where object.visible {
            if let pt = e.evaluate(object.id).point {
                let d = pt.distance(to: p)
                if d <= tol + 0.04 {
                    if best == nil || d < best!.1 { best = (object.id, d) }
                }
            }
        }
        if let best { return best.0 }
        // Paths.
        for object in objects.reversed() where object.visible {
            if case .functionPlot(let expression) = object.kind {
                if var parser = Expression(expression) {
                    parser.setAngleUnit(settings.angleUnit)
                    if let y = parser.evaluate(x: p.x), abs(y - p.y) * settings.scale <= 9 {
                        return object.id
                    }
                }
                continue
            }
            if let path = e.evaluate(object.id).path {
                if path.distance(to: p) <= tol { return object.id }
                // A polygon interior is a target too. routine uses the
                // winding-number rule for polygon hit testing.
                if path.contains(p) { return object.id }
            }
        }
        // Measurement / caption boxes.
        for object in objects.reversed() where object.visible {
            let r = e.evaluate(object.id)
            guard let text = r.text, let anchor = r.anchor else { continue }
            if textBounds(text: text, anchor: anchor).inset(-0.1).contains(p) {
                return object.id
            }
        }
        return nil
    }

    func textBounds(text: String, anchor: Vec2) -> WorldRect {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let w = (size.width + 14) / settings.scale
        let h = (size.height + 8) / settings.scale
        return WorldRect(minX: anchor.x, minY: anchor.y, maxX: anchor.x + w, maxY: anchor.y + h)
    }

    // MARK: selection

    func isSelected(_ id: UUID) -> Bool { selection.contains(id) }

    func select(_ id: UUID, additive: Bool = false) {
        if additive {
            if let i = selection.firstIndex(of: id) { selection.remove(at: i) }
            else { selection.append(id) }
        } else {
            selection = [id]
        }
        statusMessage = ""
    }

    func clearSelection() { selection = [] }

    func selectAll() { selection = objects.filter(\.visible).map(\.id) }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        checkpoint()
        var doomed = Set(selection)
        var changed = true
        while changed {
            changed = false
            for object in objects where !doomed.contains(object.id) {
                if parents(of: object).contains(where: { doomed.contains($0) }) {
                    doomed.insert(object.id); changed = true
                }
            }
        }
        objects.removeAll { doomed.contains($0.id) }
        selection = []
        draft = []
        isDirty = true
        statusMessage = "Deleted \(doomed.count) object\(doomed.count == 1 ? "" : "s")"
    }

    func parents(of object: SketchObject) -> [UUID] {
        switch object.kind {
        case .freePoint, .caption, .functionPlot, .calculation: return []
        case .pointOnPath(let p, _): return [p]
        case .midpoint(let a, let b): return [a, b]
        case .intersection(let a, let b, _): return [a, b]
        case .segment(let a, let b), .ray(let a, let b), .line(let a, let b): return [a, b]
        case .perpendicular(let l, let p), .parallel(let l, let p): return [l, p]
        case .angleBisector(let a, let v, let c): return [a, v, c]
        case .circle(let c, let t): return [c, t]
        case .polygon(let v): return v
        case .angle(let a, let v, let c): return [a, v, c]
        case .measurement(_, let refs): return refs
        case .transformed(let s, let spec):
            var out = [s]
            if let r = spec.reference { out.append(r) }
            if let r = spec.secondReference { out.append(r) }
            return out
        case .locus(let driver, let target): return [driver, target]
        }
    }

    func hideSelection() {
        guard !selection.isEmpty else { return }
        checkpoint()
        for id in selection {
            if let i = index(of: id) { objects[i].visible = false }
        }
        selection = []
        isDirty = true
        statusMessage = "Objects hidden"
    }

    func showAll() {
        checkpoint()
        for i in objects.indices { objects[i].visible = true }
        isDirty = true
        statusMessage = "All hidden objects are visible again"
    }

    func toggleLabels(for ids: [UUID]) {
        guard !ids.isEmpty else { return }
        checkpoint()
        for id in ids {
            if let i = index(of: id) { objects[i].showLabel.toggle() }
        }
        isDirty = true
    }

    // MARK: point creation

    func existingPoint(near p: Vec2, tolerance: Double) -> UUID? {
        var e = evaluator()
        var best: (UUID, Double)?
        for object in objects where object.visible {
            if let pt = e.evaluate(object.id).point {
                let d = pt.distance(to: p)
                if d <= max(tolerance, 0.05) {
                    if best == nil || d < best!.1 { best = (object.id, d) }
                }
            }
        }
        return best?.0
    }

    func ensurePoint(at p: Vec2, tolerance: Double) -> UUID {
        if let existing = existingPoint(near: p, tolerance: tolerance) { return existing }
        // Attach to a path when the click is close to one.
        var e = evaluator()
        var bestPath: (UUID, Double)?
        for object in objects where object.visible {
            if let path = e.evaluate(object.id).path {
                let d = path.distance(to: p)
                if d <= max(tolerance, 0.05) {
                    if bestPath == nil || d < bestPath!.1 { bestPath = (object.id, d) }
                }
            }
        }
        if let (id, _) = bestPath, let path = e.evaluate(id).path {
            checkpoint()
            let param = path.nearestParam(to: p)
            var object = SketchObject(kind: .pointOnPath(path: id, param: param))
            object.label = nextPointLabel()
            object.order = (objects.map(\.order).max() ?? 0) + 1
            objects.append(object)
            isDirty = true
            return object.id
        }
        checkpoint()
        var object = SketchObject(kind: .freePoint)
        object.position = p
        object.label = nextPointLabel()
        object.order = (objects.map(\.order).max() ?? 0) + 1
        objects.append(object)
        isDirty = true
        return object.id
    }

    // MARK: canvas tool actions

    func clickCanvas(at p: Vec2, tolerance: Double, additive: Bool) {
        switch tool {
        case .select:
            if let hit = hitTest(p, tolerance: tolerance) {
                select(hit, additive: additive)
            } else {
                clearSelection()
            }

        case .point:
            if let existing = existingPoint(near: p, tolerance: tolerance) {
                select(existing)
                return
            }
            let id = ensurePoint(at: p, tolerance: tolerance)
            selection = [id]
            statusMessage = "Point created"

        case .segment, .ray, .line:
            if draft.count == 0 {
                let id = ensurePoint(at: p, tolerance: tolerance)
                draft = [id]
                selection = [id]
            } else if draft.count == 1 {
                let id = ensurePoint(at: p, tolerance: tolerance)
                if id == draft[0] {
                    statusMessage = "Choose a different second point"
                    return
                }
                checkpoint()
                let kind: ObjectKind
                switch tool {
                case .segment: kind = .segment(a: draft[0], b: id)
                case .ray: kind = .ray(a: draft[0], b: id)
                default: kind = .line(a: draft[0], b: id)
                }
                var object = SketchObject(kind: kind)
                object.label = ""
                object.order = (objects.map(\.order).max() ?? 0) + 1
                objects.append(object)
                selection = [object.id]
                draft = []
                isDirty = true
                statusMessage = "\(tool.title) created"
            }

        case .circle:
            if draft.count == 0 {
                draft = [ensurePoint(at: p, tolerance: tolerance)]
                selection = draft
            } else {
                let id = ensurePoint(at: p, tolerance: tolerance)
                if id == draft[0] { return }
                checkpoint()
                var object = SketchObject(kind: .circle(center: draft[0], through: id))
                object.order = (objects.map(\.order).max() ?? 0) + 1
                objects.append(object)
                selection = [object.id]
                draft = []
                isDirty = true
                statusMessage = "Circle created"
            }

        case .polygon:
            let id = ensurePoint(at: p, tolerance: tolerance)
            if let first = draft.first, id == first, draft.count >= 3 {
                finishPolygon()
                return
            }
            if !draft.contains(id) { draft.append(id) }
            selection = draft
            statusMessage = draft.count >= 3 ? "Press Return to close the polygon" : "Click more vertices"

        case .angle:
            let id = ensurePoint(at: p, tolerance: tolerance)
            if draft.count == 0 {
                draft = [id]
            } else if draft.count == 1 {
                if id != draft[0] { draft.append(id) }
            } else {
                if id == draft[0] || id == draft[1] { return }
                draft.append(id)
                checkpoint()
                var object = SketchObject(kind: .angle(a: draft[0], vertex: draft[1], c: draft[2]))
                object.label = "m∠\(objectByID(draft[0])?.label ?? "")\(objectByID(draft[1])?.label ?? "")\(objectByID(draft[2])?.label ?? "")"
                object.order = (objects.map(\.order).max() ?? 0) + 1
                objects.append(object)
                selection = [object.id]
                draft = []
                isDirty = true
                statusMessage = "Angle marked"
            }

        case .text:
            break
        }
    }

    func finishPolygon() {
        guard draft.count >= 3 else {
            statusMessage = "A polygon needs at least three points"
            return
        }
        checkpoint()
        var object = SketchObject(kind: .polygon(vertices: draft))
        object.order = (objects.map(\.order).max() ?? 0) + 1
        objects.append(object)
        selection = [object.id]
        draft = []
        isDirty = true
        statusMessage = "Polygon created"
    }

    func cancelDraft() {
        draft = []
        statusMessage = "Cancelled"
    }

    // MARK: animation, trace and locus

    /// The point an animation can move: a selected point on a path, or the
    /// first point-on-path parent of a selected dependent object.
    var animatablePoint: UUID? {
        for id in selection {
            if case .pointOnPath = objectByID(id)?.kind { return id }
        }
        for id in selection {
            var current = objectByID(id)
            var hops = 0
            while let object = current, hops < 24 {
                if case .pointOnPath = object.kind { return object.id }
                current = parents(of: object).first.flatMap { objectByID($0) }
                hops += 1
            }
        }
        return nil
    }

    func toggleAnimation() {
        if animationPointID != nil {
            animationPointID = nil
            statusMessage = "Animation paused"
            return
        }
        guard let id = animatablePoint else {
            statusMessage = "Select a point on an object to animate"
            return
        }
        animationDirection = 1
        animationPointID = id
        statusMessage = "Animating \(objectByID(id)?.label ?? "point") — choose Animate again to pause"
    }

    /// Points on straight objects move back and forth; points on circles go
    /// all the way round, following the original's motion principles.
    func advanceAnimation() {
        var e = evaluator()
        guard let id = animationPointID, let i = index(of: id),
              case .pointOnPath(let parent, let param) = objects[i].kind,
              let path = e.path(parent) else { return }
        var next = param
        if case .circle = path {
            next = (param + 0.022).truncatingRemainder(dividingBy: 2 * .pi)
            if next < 0 { next += 2 * .pi }
        } else {
            next = param + 0.0045 * animationDirection
            if next > 1 { next = 1; animationDirection = -1 }
            if next < 0 { next = 0; animationDirection = 1 }
        }
        objects[i].kind = .pointOnPath(path: parent, param: next)
        isDirty = true
        recordTraceSamples()
    }

    func toggleTrace() {
        guard !selection.isEmpty else {
            statusMessage = "Select an object to trace"
            return
        }
        if selection.allSatisfy({ tracedIDs.contains($0) }) {
            for id in selection { tracedIDs.remove(id) }
            statusMessage = "Tracing off"
        } else {
            for id in selection { tracedIDs.insert(id) }
            statusMessage = "Tracing \(selection.count) object\(selection.count == 1 ? "" : "s")"
        }
    }

    func eraseTraces() {
        tracePaths.removeAll()
        statusMessage = "Traces erased"
    }

    func recordTraceSamples() {
        guard !tracedIDs.isEmpty else { return }
        var e = evaluator()
        for id in tracedIDs {
            guard let p = e.evaluate(id).point else { continue }
            var points = tracePaths[id] ?? []
            if points.last?.distance(to: p) ?? .greatestFiniteMagnitude > 0.004 {
                points.append(p)
            }
            if points.count > 800 { points.removeFirst(points.count - 800) }
            tracePaths[id] = points
        }
    }

    /// A locus is the set of positions of a driven object as its driver
    /// varies over the driver's path (the original's Locus definition).
    func constructLocus() {
        let chosen = selection.compactMap { objectByID($0) }
        guard let driver = chosen.first(where: {
            if case .pointOnPath = $0.kind { return true }
            return false
        }) else {
            statusMessage = "A locus needs a point on a path plus the point it drives"
            return
        }
        guard let target = chosen.last(where: { $0.id != driver.id && $0.isPointLike }) else {
            statusMessage = "Select the driven point after its driver"
            return
        }
        checkpoint()
        var object = SketchObject(kind: .locus(driver: driver.id, target: target.id))
        object.order = (objects.map(\.order).max() ?? 0) + 1
        object.style.color = .violet
        object.style.lineWidth = 1.6
        objects.append(object)
        selection = [object.id]
        isDirty = true
        statusMessage = "Locus constructed"
    }

    // MARK: drag

    func beginDrag(at p: Vec2, tolerance: Double) -> UUID? {
        guard let hit = hitTest(p, tolerance: tolerance), let object = objectByID(hit) else { return nil }
        switch object.kind {
        case .freePoint, .pointOnPath:
            checkpoint()
            return hit
        default:
            return nil
        }
    }

    func dragPoint(_ id: UUID, to p: Vec2) {
        guard let i = index(of: id) else { return }
        switch objects[i].kind {
        case .freePoint:
            if settings.snap {
                let u = max(settings.lengthUnit.perUnit, 1e-6)
                objects[i].position = Vec2((p.x / u).rounded() * u, (p.y / u).rounded() * u)
            } else {
                objects[i].position = p
            }
            isDirty = true
        case .pointOnPath(let parent, let oldParam):
            var e = evaluator()
            guard let path = e.path(parent) else { return }
            var target = p
            if settings.snap, case .circle(let c, _) = path {
                let a = atan2(target.y - c.y, target.x - c.x)
                let radius = c.distance(to: target)
                target = c + Vec2(cos(a), sin(a)) * radius
                // routine rounds the drag angle to 15° buckets. When the
                // bucket lands on a horizontal or vertical direction it keeps
                // the point's previous x or y, so the point does not jitter
                // across a cardinal point.
                let bucket = ((Int((a / (Double.pi / 12)).rounded()) % 12) + 12) % 12
                if let old = path.point(at: oldParam) {
                    if bucket == 0 {
                        let dy = old.y - c.y
                        let dx = max(radius * radius - dy * dy, 0).squareRoot()
                        target = Vec2(c.x + (cos(a) >= 0 ? dx : -dx), old.y)
                    } else if bucket == 6 {
                        let dx = old.x - c.x
                        let dy = max(radius * radius - dx * dx, 0).squareRoot()
                        target = Vec2(old.x, c.y + (sin(a) >= 0 ? dy : -dy))
                    }
                }
            }
            let param = path.nearestParam(to: target)
            objects[i].kind = .pointOnPath(path: parent, param: param)
            isDirty = true
        default:
            break
        }
        recordTraceSamples()
    }

    func translateObject(_ id: UUID, by delta: Vec2) {
        guard let i = index(of: id) else { return }
        switch objects[i].kind {
        case .freePoint, .caption:
            objects[i].position = (objects[i].position ?? .zero) + delta
            isDirty = true
        case .measurement, .calculation, .angle:
            objects[i].offset = objects[i].offset + delta
            isDirty = true
        default:
            break
        }
    }

    func setLabelOffset(_ id: UUID, _ offset: Vec2) {
        guard let i = index(of: id) else { return }
        objects[i].offset = offset
        isDirty = true
    }

    func setCaptionPosition(_ id: UUID, _ position: Vec2) {
        guard let i = index(of: id) else { return }
        objects[i].position = position
        isDirty = true
    }

    func setCaptionText(_ id: UUID, _ text: String) {
        guard let i = index(of: id) else { return }
        if case .caption = objects[i].kind {
            checkpoint()
            objects[i].kind = .caption(text)
            isDirty = true
        }
    }

    func moveLabel(_ id: UUID, by delta: Vec2) {
        guard let i = index(of: id) else { return }
        if case .measurement = objects[i].kind {
            objects[i].offset = objects[i].offset + delta
        } else if case .calculation = objects[i].kind {
            objects[i].offset = objects[i].offset + delta
        } else if case .caption = objects[i].kind {
            objects[i].position = (objects[i].position ?? .zero) + delta
        } else if case .angle = objects[i].kind {
            objects[i].offset = objects[i].offset + delta
        }
        isDirty = true
    }

    // MARK: construction commands

    private func selectedPoints() -> [UUID] {
        selectedObjects.filter { object in
            var e = evaluator()
            return e.evaluate(object.id).point != nil
        }.map(\.id)
    }

    private func selectedPaths() -> [UUID] {
        selectedObjects.filter { object in
            var e = evaluator()
            return e.evaluate(object.id).path != nil
        }.map(\.id)
    }

    private func selectedStraights() -> [UUID] {
        selectedObjects.filter { object in
            var e = evaluator()
            guard let p = e.evaluate(object.id).path?.straight else { return false }
            _ = p
            return true
        }.map(\.id)
    }

    func constructMidpoint() {
        let pts = selectedPoints()
        if pts.count >= 2 {
            checkpoint()
            let id = commit(kind: .midpoint(a: pts[0], b: pts[1]), label: nextPointLabel())
            selection = [id]
            statusMessage = "Midpoint created"
            return
        }
        var e = evaluator()
        if let pathID = selectedPaths().first, let s = e.path(pathID)?.straight {
            checkpoint()
            let a = ensureSilentPoint(at: s.a)
            let b = ensureSilentPoint(at: s.b)
            let id = commit(kind: .midpoint(a: a, b: b), label: nextPointLabel())
            selection = [id]
            statusMessage = "Midpoint created"
            return
        }
        statusMessage = "Select two points or a segment first"
    }

    func constructPerpendicular() {
        let points = selectedPoints()
        let straights = selectedStraights()
        guard let point = points.first, let line = straights.first else {
            statusMessage = "Select a point and a straight object"
            return
        }
        checkpoint()
        let id = commit(kind: .perpendicular(line: line, point: point), label: "")
        selection = [id]
        statusMessage = "Perpendicular created"
    }

    func constructParallel() {
        let points = selectedPoints()
        let straights = selectedStraights()
        guard let point = points.first, let line = straights.first else {
            statusMessage = "Select a point and a straight object"
            return
        }
        checkpoint()
        let id = commit(kind: .parallel(line: line, point: point), label: "")
        selection = [id]
        statusMessage = "Parallel created"
    }

    func constructBisector() {
        let pts = selectedPoints()
        guard pts.count >= 3 else {
            statusMessage = "Select three points, with the vertex in the middle"
            return
        }
        checkpoint()
        let id = commit(kind: .angleBisector(a: pts[0], vertex: pts[1], c: pts[2]), label: "")
        selection = [id]
        statusMessage = "Angle bisector created"
    }

    func constructIntersection() {
        let paths = selectedPaths()
        guard paths.count >= 2 else {
            statusMessage = "Select two paths first"
            return
        }
        var e = evaluator()
        guard let p1 = e.path(paths[0]), let p2 = e.path(paths[1]) else { return }
        let hits = p1.intersections(with: p2)
        guard !hits.isEmpty else {
            statusMessage = "Those objects do not meet"
            return
        }
        checkpoint()
        var created: [UUID] = []
        for i in hits.indices {
            let id = commit(kind: .intersection(a: paths[0], b: paths[1], index: i), label: nextPointLabel())
            created.append(id)
        }
        selection = created
        statusMessage = "\(created.count) intersection\(created.count == 1 ? "" : "s") created"
    }

    func constructSegment() {
        let pts = selectedPoints()
        guard pts.count >= 2 else {
            statusMessage = "Select at least two points"
            return
        }
        checkpoint()
        var created: [UUID] = []
        for i in 0..<(pts.count - 1) {
            created.append(commit(kind: .segment(a: pts[i], b: pts[i + 1]), label: ""))
        }
        selection = created
        statusMessage = "Segment created"
    }

    func constructCircle() {
        let pts = selectedPoints()
        guard pts.count >= 2 else {
            statusMessage = "Select a center point and a point on the circle"
            return
        }
        checkpoint()
        let id = commit(kind: .circle(center: pts[0], through: pts[1]), label: "")
        selection = [id]
        statusMessage = "Circle created"
    }

    func constructPolygon() {
        let pts = selectedPoints()
        guard pts.count >= 3 else {
            statusMessage = "Select at least three points"
            return
        }
        checkpoint()
        let id = commit(kind: .polygon(vertices: pts), label: "")
        selection = [id]
        statusMessage = "Polygon created"
    }

    func constructPointOnPath() {
        guard let id = selectedPaths().first, let object = objectByID(id) else {
            statusMessage = "Select a path first"
            return
        }
        _ = object
        var e = evaluator()
        guard let path = e.path(id) else { return }
        let worldCenter = settings.center
        checkpoint()
        let newID = commit(kind: .pointOnPath(path: id, param: path.nearestParam(to: worldCenter)),
                            label: nextPointLabel())
        selection = [newID]
        statusMessage = "Point attached to the path"
    }

    private func ensureSilentPoint(at p: Vec2) -> UUID {
        if let id = existingPoint(near: p, tolerance: 0.04) { return id }
        var object = SketchObject(kind: .freePoint)
        object.position = p
        object.label = nextPointLabel()
        object.order = (objects.map(\.order).max() ?? 0) + 1
        objects.append(object)
        return object.id
    }

    private func commit(kind: ObjectKind, label: String) -> UUID {
        var object = SketchObject(kind: kind)
        object.label = label
        object.order = (objects.map(\.order).max() ?? 0) + 1
        object.showLabel = isLabelWorthy(kind)
        objects.append(object)
        isDirty = true
        return object.id
    }

    // MARK: measurement commands

    func measure(_ kind: MeasureKind) {
        let ids = selection
        var e = evaluator()
        var refs: [UUID] = []
        switch kind {
        case .distance:
            let pts = ids.filter { e.evaluate($0).point != nil }
            guard pts.count >= 2 else { statusMessage = "Select two points"; return }
            refs = Array(pts.prefix(2))
        case .length, .perimeter, .circumference, .radius, .slope:
            guard let id = ids.first(where: { e.evaluate($0).path != nil }) else {
                statusMessage = "Select a path first"; return
            }
            refs = [id]
        case .angle:
            let pts = ids.filter { e.evaluate($0).point != nil }
            guard pts.count >= 3 else { statusMessage = "Select three points"; return }
            refs = Array(pts.prefix(3))
        case .area:
            guard let id = ids.first(where: { e.evaluate($0).path != nil }) else {
                statusMessage = "Select a polygon or circle"; return
            }
            refs = [id]
        case .ratio:
            let paths = ids.filter { e.evaluate($0).path?.straight != nil }
            guard paths.count >= 2 else { statusMessage = "Select two segments"; return }
            refs = Array(paths.prefix(2))
        case .coordinates:
            guard let id = ids.first(where: { e.evaluate($0).point != nil }) else {
                statusMessage = "Select a point"; return
            }
            refs = [id]
        case .equation:
            guard let id = ids.first(where: { e.evaluate($0).path != nil }) else {
                statusMessage = "Select a line or circle"; return
            }
            refs = [id]
        }
        _ = e
        checkpoint()
        let id = commit(kind: .measurement(kind, refs: refs), label: "")
        selection = [id]
        statusMessage = "\(kind.title) measured"
    }

    func addCalculation(expression: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        checkpoint()
        let id = commit(kind: .calculation(trimmed), label: "")
        selection = [id]
        isDirty = true
        statusMessage = "Calculation added"
    }

    // MARK: transform commands

    func reflectSelection() {
        guard let mirror = selectedStraights().last else {
            statusMessage = "Select a mirror line with the other objects"
            return
        }
        let sources = selection.filter { $0 != mirror }
        guard !sources.isEmpty else {
            statusMessage = "Select objects to reflect as well as the mirror"
            return
        }
        checkpoint()
        var created: [UUID] = []
        for source in sources {
            let spec = TransformSpec(kind: .reflect, reference: mirror)
            created.append(commit(kind: .transformed(source: source, spec: spec), label: ""))
        }
        selection = created
        statusMessage = "Reflection created"
    }

    func rotateSelection(center: UUID, degrees: Double) {
        let sources = selection.filter { $0 != center }
        guard !sources.isEmpty else {
            statusMessage = "Select objects to rotate as well as the center"
            return
        }
        checkpoint()
        var created: [UUID] = []
        for source in sources {
            let spec = TransformSpec(kind: .rotate, reference: center, angle: degrees)
            created.append(commit(kind: .transformed(source: source, spec: spec), label: ""))
        }
        selection = created
        statusMessage = "Rotation created"
    }

    func dilateSelection(center: UUID, factor: Double) {
        let sources = selection.filter { $0 != center }
        guard !sources.isEmpty else {
            statusMessage = "Select objects to dilate as well as the center"
            return
        }
        checkpoint()
        var created: [UUID] = []
        for source in sources {
            let spec = TransformSpec(kind: .dilate, reference: center, factor: factor)
            created.append(commit(kind: .transformed(source: source, spec: spec), label: ""))
        }
        selection = created
        statusMessage = "Dilation created"
    }

    func translateSelection(dx: Double, dy: Double) {
        let sources = selection
        guard !sources.isEmpty else { statusMessage = "Select objects to translate"; return }
        checkpoint()
        var created: [UUID] = []
        for source in sources {
            let spec = TransformSpec(kind: .translate, dx: dx, dy: dy)
            created.append(commit(kind: .transformed(source: source, spec: spec), label: ""))
        }
        selection = created
        statusMessage = "Translation created"
    }

    // MARK: graph

    func addFunctionPlot(expression: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Expression(trimmed) != nil else {
            statusMessage = "That expression could not be read"
            return
        }
        checkpoint()
        let id = commit(kind: .functionPlot(trimmed), label: "")
        selection = [id]
        isDirty = true
        statusMessage = "Function plotted"
    }

    // MARK: save & open

    func save() {
        if let url = currentURL {
            write(to: url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.title = "Save Sketch"
        panel.nameFieldStringValue = document.title.hasSuffix(".gsp") ? document.title : "\(document.title).gsp"
        panel.allowedContentTypes = [UTType(filenameExtension: "gsp") ?? .json]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            write(to: url)
        }
    }

    private func write(to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var doc = document
            doc.title = url.deletingPathExtension().lastPathComponent
            let data = try encoder.encode(doc)
            try data.write(to: url, options: .atomic)
            document.title = doc.title
            currentURL = url
            isDirty = false
            statusMessage = "Saved to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.title = "Open Sketch"
        panel.allowedContentTypes = [UTType(filenameExtension: "gsp") ?? .json, .json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let doc = try JSONDecoder().decode(SketchDocument.self, from: data)
            checkpoint()
            document = doc
            currentURL = url
            selection = []
            draft = []
            isDirty = false
            statusMessage = "Opened \(url.lastPathComponent)"
        } catch {
            statusMessage = "That file could not be opened: \(error.localizedDescription)"
        }
    }
}
