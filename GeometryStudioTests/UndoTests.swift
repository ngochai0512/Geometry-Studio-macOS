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
