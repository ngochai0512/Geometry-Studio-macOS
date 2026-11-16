import SwiftUI

final class SketchModel: ObservableObject {
    // MARK: state
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
    var animationDirection: Double = 1

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

    func isLabelWorthy(_ kind: ObjectKind) -> Bool {
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
}
