import Observation
import SwiftUI

/// The sketch in the key document window. Settings is a separate scene, so it
/// uses this weak reference to apply changes to the active document.
enum ActiveSketch {
    static weak var model: SketchModel?
}

/// One entry in the undo history panel.
struct UndoHistoryEntry: Identifiable, Hashable {
    var id = UUID()
    var name: String
}

@Observable
final class SketchModel {
    // MARK: state
    var document: SketchDocument
    var selection: [UUID] = []
    var tool: SketchTool = .select
    var draft: [UUID] = []
    var hoverWorld: Vec2?
    /// Last pointer position on the canvas, kept after the pointer leaves so
    /// menu commands can place new objects where the user was working.
    @ObservationIgnored
    var lastPointerWorld: Vec2?
    /// Objects excluded from smart snapping while the current point drag runs.
    @ObservationIgnored
    var dragSnapExclusions: Set<UUID> = []
    var isPointerOverCanvas = false
    /// Space held: pan without switching away from the current tool.
    var spacePanning = false
    /// Presentation: hide chrome, go full screen, page through open sketches.
    var presentationMode = false
    /// The canvas's last laid-out size, so Fit and the inspector use the real
    /// window instead of a guessed frame.
    var canvasSize = CGSize(width: 900, height: 720)
    var inspectorVisible = true
    var statusMessage: String = ""
    var showAbout = false
    /// Transient guides drawn while a point is placed or dragged.
    var smartGuides: [SmartGuide] = []
    /// A parallel record of undo step names for the history panel. Snapshots
    /// stay in NSUndoManager; this is only the list the panel shows.
    var undoHistory: [UndoHistoryEntry] = []
    var undoHistoryIndex = 0
    /// Animation.
    var animationPointID: UUID?
    var tracedIDs: Set<UUID> = []
    var tracePaths: [UUID: [Vec2]] = [:]
    @ObservationIgnored
    private var animationTimer: Timer?
    @ObservationIgnored
    var animationDirection: Double = 1

    @ObservationIgnored
    private var openGroup = false
    @ObservationIgnored
    private var lastCoalescingKey: String?
    @ObservationIgnored
    private var lastCheckpointAt = Date.distantPast
    private let undoLimit = 80
    /// Undo snapshots copy the whole object array, so a large sketch keeps a
    /// shorter history: past this count, 80 snapshots cost more than the
    /// history is worth.
    private let largeSketchObjectCount = 400
    private let largeSketchUndoLimit = 40
    /// The window's undo manager. It is the only undo stack: the document
    /// architecture observes it for the edited dot, the native save sheet and
    /// autosave, so nothing else has to mirror change counts.
    @ObservationIgnored
    weak var undoManager: UndoManager? {
        didSet {
            guard let manager = undoManager else {
                return
            }
            MainActor.assumeIsolated {
                if manager.levelsOfUndo != undoDepth {
                    manager.levelsOfUndo = undoDepth
                }
                // Each registration is its own top-level group, so one ⌘Z
                // always takes back exactly one step.
                if manager.groupsByEvent {
                    manager.groupsByEvent = false
                }
            }
            observeUndoState(of: manager)
        }
    }
    @ObservationIgnored
    private var undoObservers: [NSObjectProtocol] = []
    @ObservationIgnored
    private var undoRefreshPending = false
    /// Bumped when the object array or canvas settings change. Render paths use
    /// it to reuse the object index, the paint order and Metal vertices instead
    /// of rebuilding them several times per frame.
    private(set) var geometryRevision = 0
    /// Traces change without touching the object array; the Metal layer needs
    /// its own signal so erased or extended traces are picked up.
    private(set) var traceRevision = 0
    @ObservationIgnored
    private var cachedIndex: [UUID: SketchObject]?
    @ObservationIgnored
    private var cachedIndexRevision = -1
    @ObservationIgnored
    private var cachedOrder: [SketchObject] = []
    @ObservationIgnored
    private var cachedOrderRevision = -1
    /// Bumped when the undo manager changes so views that read canUndo or
    /// the action names have an observable dependency to refresh on.
    private var undoRevision = 0

    init(document: SketchDocument = SketchDocument()) {
        self.document = document
    }

    deinit {
        animationTimer?.invalidate()
        // NotificationCenter outlives the model and keeps block observers until
        // they are removed by hand, so every closed document would leave two
        // registrations behind.
        for observer in undoObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: animation clock

    /// The clock only exists while an animation is running. An always-on
    /// timer kept the window redrawing at 60 Hz even when nothing moved.
    func startAnimationClock() {
        animationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    func stopAnimationClock() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    struct Snapshot {
        var objects: [SketchObject]
        var selection: [UUID]
        var marks: TransformMarks
    }

    var objects: [SketchObject] {
        get {
            document.objects
        }
        set {
            document.objects = newValue
            invalidateGeometry()
        }
        _modify {
            // Yielding the stored array in place keeps a drag or animation tick
            // from copying the whole array back through the setter.
            yield &document.objects
            invalidateGeometry()
        }
    }
    var settings: CanvasSettings {
        get {
            document.settings
        }
        set {
            document.settings = newValue
            invalidateGeometry()
        }
    }
    var marks: TransformMarks {
        get {
            document.marks
        }
        set {
            document.marks = newValue
        }
    }

    var selectedObjects: [SketchObject] {
        selection.compactMap { id in objects.first(where: { $0.id == id }) }
    }

    var canUndo: Bool {
        _ = undoRevision
        guard let undoManager else {
            return false
        }
        return MainActor.assumeIsolated {
            undoManager.canUndo
        }
    }
    var canRedo: Bool {
        _ = undoRevision
        guard let undoManager else {
            return false
        }
        return MainActor.assumeIsolated {
            undoManager.canRedo
        }
    }
    /// The action ⌘Z would take back, for menu titles and status text.
    var undoActionName: String? {
        _ = undoRevision
        guard let undoManager else {
            return nil
        }
        let name = MainActor.assumeIsolated {
            undoManager.undoActionName
        }
        return name.isEmpty ? nil : name
    }
    var redoActionName: String? {
        _ = undoRevision
        guard let undoManager else {
            return nil
        }
        let name = MainActor.assumeIsolated {
            undoManager.redoActionName
        }
        return name.isEmpty ? nil : name
    }

    // MARK: document lifecycle

    static func sample() -> SketchModel {
        let model = SketchModel()
        model.seedSample()
        return model
    }

    /// Content for a new document. Settings are injected so a new sketch starts
    /// empty with the user's grid, unit and precision choices instead of
    /// reading them lazily.
    static func blankDocument(settings: CanvasSettings = CanvasSettings()) -> SketchDocument {
        var document = SketchDocument()
        document.settings = settings
        return document
    }

    /// Swaps in content that changed outside the editor, such as Revert To
    /// Saved or browsing versions. History belongs to the document, so it resets.
    func adopt(_ newDocument: SketchDocument) {
        stopAnimationClock()
        animationPointID = nil
        document = newDocument
        invalidateGeometry()
        selection = []
        draft = []
        smartGuides = []
        dragSnapExclusions = []
        lastPointerWorld = nil
        resetHistory()
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
        _ = add(kind: .segment(a: c, b: a), silent: true)

        let d = add(kind: .midpoint(a: a, b: b), label: "D", silent: true)
        let e = add(kind: .midpoint(a: b, b: c), label: "E", silent: true)
        let perp1 = add(kind: .perpendicular(line: ab, point: d), silent: true)
        let perp2 = add(kind: .perpendicular(line: bc, point: e), silent: true)
        if let i = index(of: perp1) {
            objects[i].style.dash = .dashed
            objects[i].style.color = .secondaryInk
        }
        if let i = index(of: perp2) {
            objects[i].style.dash = .dashed
            objects[i].style.color = .secondaryInk
        }

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
            // dragged separately afterwards.
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

    // MARK: undo

    /// Records the state before a change. `action` names the step in menus;
    /// `coalescing` folds continuous edits (typing, dragging a slider) into
    /// the step that started them while the same key keeps arriving.
    func checkpoint(_ action: String = "Change", coalescing key: String? = nil) {
        guard !openGroup else {
            return
        }
        if let key, key == lastCoalescingKey,
           Date().timeIntervalSince(lastCheckpointAt) < 1.2 {
            // Keep extending while the edit continues; a pause starts a step.
            lastCheckpointAt = Date()
            return
        }
        registerUndo(action: action, snapshot: Snapshot(objects: objects, selection: selection, marks: marks))
        lastCoalescingKey = key
        lastCheckpointAt = Date()
    }

    /// Runs a multi-step change as one undoable action. Nested checkpoints are
    /// folded into the snapshot taken here, so drawing a segment does not leave
    /// its two new endpoints behind as separate steps.
    func perform(_ action: String, _ body: () -> Void) {
        guard !openGroup else {
            body()
            return
        }
        let before = Snapshot(objects: objects, selection: selection, marks: marks)
        openGroup = true
        body()
        openGroup = false
        guard before.objects != objects || before.selection != selection || before.marks != marks else {
            return
        }
        registerUndo(action: action, snapshot: before)
    }

    /// Registers the inverse of a change about to be made. Each registration
    /// is its own top-level group so one ⌘Z takes back one step.
    private func registerUndo(action: String, snapshot: Snapshot) {
        guard let undoManager else {
            return
        }
        let depth = undoDepth
        MainActor.assumeIsolated {
            if undoManager.levelsOfUndo != depth {
                undoManager.levelsOfUndo = depth
            }
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: self) { model in
                model.restore(snapshot, action: action)
            }
            undoManager.setActionName(action)
            undoManager.endUndoGrouping()
        }
        if undoHistoryIndex < undoHistory.count {
            undoHistory.removeSubrange(undoHistoryIndex...)
        }
        undoHistory.append(UndoHistoryEntry(name: action))
        undoHistoryIndex = undoHistory.count
        let overflow = undoHistory.count - depth
        if overflow > 0 {
            undoHistory.removeFirst(overflow)
            undoHistoryIndex -= overflow
        }
        lastCoalescingKey = nil
        lastCheckpointAt = Date()
        scheduleUndoRefresh()
    }

    /// How many snapshots the manager keeps. A snapshot holds the whole object
    /// array, so a big sketch trades history depth for memory.
    private var undoDepth: Int {
        objects.count > largeSketchObjectCount ? largeSketchUndoLimit : undoLimit
    }

    /// Applies a snapshot and registers its inverse. `NSUndoManager` routes
    /// that inverse to the redo stack while undoing and the undo stack while
    /// redoing, so the manager already knows which direction runs.
    private func restore(_ snapshot: Snapshot, action: String) {
        guard let undoManager else {
            return
        }
        let current = Snapshot(objects: objects, selection: selection, marks: marks)
        objects = snapshot.objects
        selection = snapshot.selection
        marks = snapshot.marks
        smartGuides = []
        lastCoalescingKey = nil
        MainActor.assumeIsolated {
            if undoManager.isUndoing {
                undoHistoryIndex = max(0, undoHistoryIndex - 1)
            } else if undoManager.isRedoing {
                undoHistoryIndex = min(undoHistory.count, undoHistoryIndex + 1)
            }
            undoManager.registerUndo(withTarget: self) { model in
                model.restore(current, action: action)
            }
            undoManager.setActionName(action)
            statusMessage = undoManager.isUndoing ? "Undo \(action)" : "Redo \(action)"
        }
        scheduleUndoRefresh()
    }

    /// A document swap or recovery must not continue coalescing into the
    /// previous document's edit.
    func resetTransientEditingState() {
        openGroup = false
        lastCoalescingKey = nil
    }

    /// Loading a different document starts a fresh history: snapshots hold
    /// objects and selection only, so undoing across a swap would leave the
    /// window pointing at the wrong file.
    func resetHistory() {
        if let undoManager {
            MainActor.assumeIsolated {
                undoManager.removeAllActions()
            }
        }
        undoHistory.removeAll()
        undoHistoryIndex = 0
        resetTransientEditingState()
        scheduleUndoRefresh()
    }

    func undo() {
        guard let undoManager, undoManager.canUndo else {
            return
        }
        MainActor.assumeIsolated {
            undoManager.undo()
        }
        clearSmartGuides()
    }

    func redo() {
        guard let undoManager, undoManager.canRedo else {
            return
        }
        MainActor.assumeIsolated {
            undoManager.redo()
        }
        clearSmartGuides()
    }

    /// Walks the undo stack until the panel's selected step is current.
    func travelHistory(to index: Int) {
        let target = min(max(index, 0), undoHistory.count)
        while undoHistoryIndex > target, canUndo {
            undo()
        }
        while undoHistoryIndex < target, canRedo {
            redo()
        }
    }

    /// Undo state lives in NSUndoManager, not in a published property, so
    /// views that show it (the toolbar) re-render from its own notifications.
    private func observeUndoState(of manager: UndoManager) {
        for observer in undoObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        let names: [Notification.Name] = [
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange
        ]
        undoObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: manager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleUndoRefresh()
                }
            }
        }
    }

    /// Notifications can fire while SwiftUI is updating views, and publishing
    /// then is undefined. Defer one change to the next turn and coalesce the
    /// burst of checkpoints a single edit produces.
    private func scheduleUndoRefresh() {
        guard !undoRefreshPending else {
            return
        }
        undoRefreshPending = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            undoRefreshPending = false
            undoRevision &+= 1
        }
    }

    // MARK: object helpers

    /// Called on every geometry change; the caches below rebuild on the next
    /// read. Wrapping add keeps a long session from ever reusing a stale value.
    private func invalidateGeometry() {
        geometryRevision &+= 1
    }

    /// Traces are drawn geometry but live outside the object array, so they get
    /// their own signal for the Metal layer.
    func invalidateTraces() {
        traceRevision &+= 1
    }

    /// The evaluator's object index, shared by every call in a frame instead of
    /// being rebuilt as a dictionary of the whole sketch per call.
    func objectIndex() -> [UUID: SketchObject] {
        if let cachedIndex, cachedIndexRevision == geometryRevision {
            return cachedIndex
        }
        let index = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        cachedIndex = index
        cachedIndexRevision = geometryRevision
        return index
    }

    /// Objects in paint order. The Canvas and Metal layers each walk this list
    /// several times per frame; sorting once per revision is enough.
    func orderedObjects() -> [SketchObject] {
        if cachedOrderRevision == geometryRevision {
            return cachedOrder
        }
        let ordered = objects.sorted { $0.order < $1.order }
        cachedOrder = ordered
        cachedOrderRevision = geometryRevision
        return ordered
    }

    func index(of id: UUID) -> Int? {
        objects.firstIndex(where: { $0.id == id })
    }

    func objectByID(_ id: UUID) -> SketchObject? {
        objects.first(where: { $0.id == id })
    }

    /// The colour family defaults applied to a newly created object.
    func defaultObjectStyle(for kind: ObjectKind) -> ObjectStyle {
        var style = ObjectStyle()
        if let family = AppearanceFamily.family(for: kind) {
            style.color = AppPreferences.appearance().color(for: family)
        }
        return style
    }

    func makeObject(kind: ObjectKind) -> SketchObject {
        var object = SketchObject(kind: kind)
        object.style = defaultObjectStyle(for: kind)
        return object
    }

    @discardableResult
    func add(kind: ObjectKind,
             label: String? = nil,
             kindLabel: String? = nil,
             position: Vec2? = nil,
             style: ObjectStyle? = nil,
             silent: Bool = false) -> UUID {
        if !silent {
            let name = label ?? kindLabel
            if let name, !name.isEmpty {
                checkpoint("Add \(name)")
            } else {
                checkpoint("Add Object")
            }
        }
        var object = makeObject(kind: kind)
        object.label = label ?? kindLabel ?? autoLabel(for: kind)
        object.position = position
        if let style {
            object.style = style
        }
        object.order = (objects.map(\.order).max() ?? 0) + 1
        object.showLabel = isLabelWorthy(kind)
        objects.append(object)
        return object.id
    }

    func isLabelWorthy(_ kind: ObjectKind) -> Bool {
        switch kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return true
        case .caption, .measurement, .calculation, .angle:
            return true
        case .parameter:
            return true
        case .graph(.table):
            return true
        default:
            return false
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
            if !used.contains(s) {
                return s
            }
        }
        var i = 1
        while true {
            for letter in letters {
                let s = "\(letter)\(i)"
                if !used.contains(s) {
                    return s
                }
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
        case .circle, .circleRadius:
            return "Circle"
        case .arcOnCircle, .arcThroughPoints:
            return "Arc"
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
        case .parameter:
            return "Parameter"
        case .construction(let kind):
            switch kind {
            case .perpendicularBisector:
                return "Perpendicular Bisector"
            case .tangentPointToCircle, .tangentCircleToCircle:
                return "Tangent"
            case .radicalAxis:
                return "Radical Axis"
            }
        case .vector(let kind):
            switch kind {
            case .fromPoints:
                return "Vector"
            case .sum(_, _, let subtract):
                return subtract ? "Vector Difference" : "Vector Sum"
            }
        case .coordinateSystem(let kind, _, _, _):
            return "\(kind.title) Coordinate System"
        case .graph(let feature):
            switch feature {
            case .derivative:
                return "Derivative Plot"
            case .integral:
                return "Integral"
            case .tangent:
                return "Tangent"
            case .table:
                return "Value Table"
            }
        }
    }

    func symbol(for object: SketchObject) -> String {
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection:
            return "circle.fill"
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector:
            return "line.diagonal"
        case .circle, .circleRadius:
            return "circle"
        case .arcOnCircle, .arcThroughPoints:
            return "circle.dotted"
        case .polygon:
            return "pentagon"
        case .angle:
            return "angle"
        case .measurement, .calculation:
            return "ruler"
        case .caption:
            return "textformat"
        case .functionPlot:
            return "function"
        case .transformed:
            return "arrow.triangle.2.circlepath"
        case .locus:
            return "scribble"
        case .parameter:
            return "slider.horizontal.3"
        case .construction(let kind):
            switch kind {
            case .perpendicularBisector:
                return "line.diagonal"
            case .tangentPointToCircle, .tangentCircleToCircle:
                return "line.diagonal.arrow"
            case .radicalAxis:
                return "line.diagonal"
            }
        case .vector:
            return "arrow.right"
        case .coordinateSystem(let kind, _, _, _):
            return kind == .polar ? "circle.grid.cross" : "grid"
        case .graph(let feature):
            switch feature {
            case .derivative:
                return "function"
            case .integral:
                return "square.split.bottomrightquarter"
            case .tangent:
                return "line.diagonal"
            case .table:
                return "tablecells"
            }
        }
    }
}
