import SwiftUI
import Combine

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
    /// Failures are surfaced as alerts, not only in the status bar.
    @Published var errorAlert: SketchAlert?
    /// A draft or salvage the user can put back.
    @Published var recoveryOffer: RecoveryOffer?
    /// Identifies this editing session's autosave draft.
    let sessionID = UUID()
    /// Animation (the original's Display > Animate).
    @Published var animationPointID: UUID?
    @Published var tracedIDs: Set<UUID> = []
    @Published var tracePaths: [UUID: [Vec2]] = [:]
    var animationDirection: Double = 1

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var openGroup: Snapshot?
    private var lastCoalescingKey: String?
    private var lastCheckpointAt = Date.distantPast
    private let undoLimit = 80
    private var builtInSample = false
    private var autosaveCancellable: AnyCancellable?
    private var autosaveEnabled = false
    /// The objects as of the last save or open. Drafts are only written when
    /// the construction differs, so panning alone does not offer a recovery.
    private var cleanObjects: [SketchObject] = []

    struct Snapshot {
        var objects: [SketchObject]
        var selection: [UUID]
        /// The action that produced the state after this snapshot.
        var action: String
    }

    struct UndoStep: Identifiable {
        let id: Int
        let name: String
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
    /// The action ⌘Z would take back, for menu titles and status text.
    var undoActionName: String? { undoStack.last?.action }
    var redoActionName: String? { redoStack.last?.action }
    /// Oldest first. An entry's `id` is the number of undo steps before it,
    /// which is the depth to keep to take that step back.
    var undoHistory: [UndoStep] {
        undoStack.enumerated().map { UndoStep(id: $0.offset, name: $0.element.action) }
    }

    // MARK: document lifecycle

    static func sample() -> SketchModel {
        let model = SketchModel()
        model.builtInSample = true
        model.document.title = "Untitled Sketch"
        model.seedSample()
        model.undoStack.removeAll()
        model.redoStack.removeAll()
        model.isDirty = false
        model.cleanObjects = model.objects
        return model
    }

    static func blank() -> SketchModel {
        let model = SketchModel()
        model.builtInSample = false
        return model
    }

    func newSketch() {
        objects = []
        selection = []
        draft = []
        document.title = "Untitled Sketch"
        document.settings = AppPreferences.canvasSettings()
        currentURL = nil
        isDirty = false
        resetHistory()
        cleanObjects = []
        DocumentDrafts.remove(sessionID: sessionID)
        statusMessage = "New sketch"
    }

    // MARK: autosave

    /// Starts the debounced draft writer. The screenshot path never calls this,
    /// so automated renders do not touch Application Support.
    func enableAutosave() {
        guard !autosaveEnabled else { return }
        autosaveEnabled = true
        autosaveCancellable = objectWillChange
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.writeDraftIfNeeded()
            }
    }

    private func writeDraftIfNeeded() {
        guard autosaveEnabled, isDirty else { return }
        if objects == cleanObjects {
            DocumentDrafts.remove(sessionID: sessionID)
            return
        }
        let record = DraftRecord(savedAt: Date(), document: document, sourceURL: currentURL)
        // Autosave is best-effort; explicit Save reports its own failures.
        try? DocumentDrafts.write(record, sessionID: sessionID)
    }

    /// Called once at launch. Loads before the window appears, so the alert
    /// can ask for a decision on first appearance.
    func checkForRecoverableDraft() {
        guard recoveryOffer == nil,
              let (record, url) = DocumentDrafts.latest(),
              !record.document.objects.isEmpty else {
            return
        }
        recoveryOffer = .draft(record, url)
    }

    func acceptRecovery() {
        guard let offer = recoveryOffer else { return }
        recoveryOffer = nil
        switch offer {
        case .draft(let record, let url):
            document = record.document
            currentURL = record.sourceURL
            selection = []
            draft = []
            isDirty = true
            resetHistory()
            DocumentDrafts.remove(at: url)
            statusMessage = "Recovered unsaved changes"
        case .salvage(let result):
            document = result.document
            currentURL = nil
            selection = []
            draft = []
            isDirty = true
            resetHistory()
            statusMessage = "Recovered \(result.recovered) of \(result.total) objects"
        }
    }

    func discardRecovery() {
        if case .draft(_, let url) = recoveryOffer {
            DocumentDrafts.remove(at: url)
        }
        recoveryOffer = nil
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
        checkpoint("Load Welcome Sketch")
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

    /// Records the state before a change. `action` names the step in menus;
    /// `coalescing` folds continuous edits (typing, dragging a slider) into
    /// the step that started them while the same key keeps arriving.
    func checkpoint(_ action: String = "Change", coalescing key: String? = nil) {
        guard openGroup == nil else {
            isDirty = true
            return
        }
        if let key, key == lastCoalescingKey,
           Date().timeIntervalSince(lastCheckpointAt) < 1.2 {
            isDirty = true
            // Keep extending while the edit continues; a pause starts a step.
            lastCheckpointAt = Date()
            return
        }
        push(Snapshot(objects: objects, selection: selection, action: action))
        lastCoalescingKey = key
        isDirty = true
    }

    /// Runs a multi-step change as one undoable action. Nested checkpoints are
    /// folded into the snapshot taken here, so drawing a segment does not leave
    /// its two new endpoints behind as separate steps.
    func perform(_ action: String, _ body: () -> Void) {
        guard openGroup == nil else {
            body()
            return
        }
        let before = Snapshot(objects: objects, selection: selection, action: action)
        openGroup = before
        body()
        openGroup = nil
        guard before.objects != objects || before.selection != selection else { return }
        push(before)
    }

    private func push(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        // A separate action must not merge into the step that preceded it.
        lastCoalescingKey = nil
        lastCheckpointAt = Date()
    }

    /// A document swap or recovery must not continue coalescing into the
    /// previous document's edit.
    func resetTransientEditingState() {
        openGroup = nil
        lastCoalescingKey = nil
    }

    /// Loading a different document starts a fresh history: snapshots hold
    /// objects and selection only, so undoing across a swap would leave the
    /// window pointing at the wrong file.
    func resetHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        resetTransientEditingState()
    }

    /// Marks the current construction as the state on disk, so autosave only
    /// offers recovery for real changes.
    func markDocumentClean() {
        cleanObjects = objects
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(Snapshot(objects: objects, selection: selection, action: snap.action))
        objects = snap.objects
        selection = snap.selection
        isDirty = true
        lastCoalescingKey = nil
        statusMessage = "Undo \(snap.action)"
    }

    func redo() {
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(Snapshot(objects: objects, selection: selection, action: snap.action))
        objects = snap.objects
        selection = snap.selection
        isDirty = true
        lastCoalescingKey = nil
        statusMessage = "Redo \(snap.action)"
    }

    /// Jumps to the state after keeping `depth` undo steps. Zero restores the
    /// state the document opened in.
    func revert(toUndoDepth depth: Int) {
        let target = max(0, min(depth, undoStack.count))
        guard target < undoStack.count else { return }
        let name = target == 0 ? "Original State" : undoStack[target - 1].action
        while undoStack.count > target { undo() }
        statusMessage = "Went back to \(name)"
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
        if !silent {
            let name = label ?? kindLabel
            if let name, !name.isEmpty {
                checkpoint("Add \(name)")
            } else {
                checkpoint("Add Object")
            }
        }
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
