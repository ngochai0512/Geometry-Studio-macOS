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
    var animationTimer: Timer?
    @ObservationIgnored
    var animationDirection: Double = 1

    @ObservationIgnored
    var openGroup = false
    @ObservationIgnored
    var lastCoalescingKey: String?
    @ObservationIgnored
    var lastCheckpointAt = Date.distantPast
    let undoLimit = 80
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
                if manager.levelsOfUndo != undoLimit {
                    manager.levelsOfUndo = undoLimit
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
    var undoObservers: [NSObjectProtocol] = []
    @ObservationIgnored
    var undoRefreshPending = false
    /// Bumped when the undo manager changes so views that read canUndo or
    /// the action names have an observable dependency to refresh on.
    var undoRevision = 0

    init(document: SketchDocument = SketchDocument()) {
        self.document = document
    }

    deinit {
        animationTimer?.invalidate()
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
        }
    }
    var settings: CanvasSettings {
        get {
            document.settings
        }
        set {
            document.settings = newValue
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
        selection = []
        draft = []
        smartGuides = []
        dragSnapExclusions = []
        lastPointerWorld = nil
        resetHistory()
    }

    func seedSample() {
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












    // MARK: object helpers










}
