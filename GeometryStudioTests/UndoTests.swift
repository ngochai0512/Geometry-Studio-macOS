import Foundation
import Testing
@testable import GeometryStudio

@MainActor
@Suite("Undo")
struct UndoTests {
    @Test("a grouped change is one undo step")
    func groupedChange() {
        let model = SketchModel()
        let manager = UndoManager()
        model.undoManager = manager
        model.perform("Draw Segment") {
            model.checkpoint("Add Point")
            let a = model.add(kind: .freePoint, silent: true)
            model.checkpoint("Add Point")
            let b = model.add(kind: .freePoint, silent: true)
            model.add(kind: .segment(a: a, b: b), silent: true)
        }

        #expect(model.canUndo)
        #expect(model.undoActionName == "Draw Segment")
        #expect(model.objects.count == 3)

        model.undo()
        #expect(model.objects.isEmpty)
        #expect(model.redoActionName == "Draw Segment")
        #expect(manager.canRedo)
    }

    @Test("checkpoints with the same coalescing key fold together")
    func coalescedEdits() {
        let model = SketchModel()
        let manager = UndoManager()
        model.undoManager = manager
        model.add(kind: .freePoint, silent: true)
        model.checkpoint("Edit Label", coalescing: "label")
        model.objects[0].label = "A"
        model.checkpoint("Edit Label", coalescing: "label")
        model.objects[0].label = "AB"

        model.undo()
        #expect(model.objects[0].label == "A")
        #expect(manager.canRedo)
    }

    @Test("a different coalescing key starts a new step")
    func separateEdits() {
        let model = SketchModel()
        let manager = UndoManager()
        model.undoManager = manager
        model.add(kind: .freePoint, silent: true)
        model.checkpoint("Edit Label", coalescing: "label")
        model.objects[0].label = "A"
        model.checkpoint("Change Line Width", coalescing: "line-width")
        model.objects[0].style.lineWidth = 3

        #expect(model.canUndo)
        model.undo()
        #expect(model.objects[0].style.lineWidth == 1.5)
        #expect(model.canUndo)
        model.undo()
        #expect(!model.canUndo)
        #expect(manager.canRedo)
    }

    @Test("the segment tool creates an opaque black segment")
    func segmentToolCreatesVisibleSegment() {
        let model = SketchModel()
        model.tool = .segment
        model.clickCanvas(at: Vec2(-1, 0), tolerance: 0.1, additive: false)
        model.clickCanvas(at: Vec2(1, 0), tolerance: 0.1, additive: false)

        guard let segment = model.objects.first(where: { object in
            if case .segment = object.kind {
                return true
            }
            return false
        }) else {
            Issue.record("expected the segment tool to add a segment")
            return
        }
        #expect(segment.visible)
        #expect(segment.style.color == RGBA.black)
        #expect(segment.style.color.a == 1)
    }

    @Test("a single selected point can be measured as coordinates")
    func singlePointMeasurement() {
        let model = SketchModel()
        let point = model.add(kind: .freePoint, position: Vec2(1, 2), silent: true)
        model.selection = [point]
        model.measure(.coordinates)

        let measured = model.objects.contains { object in
            if case .measurement(.coordinates, _) = object.kind {
                return true
            }
            return false
        }
        #expect(measured)
    }

    @Test("an invalid measurement is refused instead of creating a blank card")
    func invalidMeasurementRefused() {
        let model = SketchModel()
        let a = model.add(kind: .freePoint, position: Vec2(0, 0), silent: true)
        let b = model.add(kind: .freePoint, position: Vec2(1, 0), silent: true)
        let segment = model.add(kind: .segment(a: a, b: b), silent: true)
        model.selection = [segment]
        let before = model.objects.count
        model.measure(.area)
        #expect(model.objects.count == before)
    }

    @Test("marks are part of the undo snapshot")
    func markUndo() {
        let model = SketchModel()
        let manager = UndoManager()
        model.undoManager = manager
        let point = model.add(kind: .freePoint, position: Vec2(0, 0), silent: true)
        model.selection = [point]
        model.markCenter()
        #expect(model.marks.center == point)

        model.undo()
        #expect(model.marks.center == nil)
    }

    @Test("redo restores an undone change")
    func redoRestores() {
        let model = SketchModel()
        let manager = UndoManager()
        model.undoManager = manager
        model.checkpoint("Add A")
        model.add(kind: .freePoint, silent: true)

        model.undo()
        #expect(model.objects.isEmpty)
        model.redo()
        #expect(model.objects.count == 1)
        #expect(!model.canRedo)
        #expect(manager.canUndo)
    }
}
