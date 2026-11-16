import Foundation
import Testing
@testable import GeometryStudio

@Suite("Undo")
struct UndoTests {
    @Test("a grouped change is one undo step")
    func groupedChange() {
        let model = SketchModel()
        model.perform("Draw Segment") {
            model.checkpoint("Add Point")
            let a = model.add(kind: .freePoint, silent: true)
            model.checkpoint("Add Point")
            let b = model.add(kind: .freePoint, silent: true)
            model.add(kind: .segment(a: a, b: b), silent: true)
        }

        #expect(model.undoHistory.count == 1)
        #expect(model.undoActionName == "Draw Segment")
        #expect(model.objects.count == 3)

        model.undo()
        #expect(model.objects.isEmpty)
        #expect(model.redoActionName == "Draw Segment")
    }

    @Test("checkpoints with the same coalescing key fold together")
    func coalescedEdits() {
        let model = SketchModel()
        model.add(kind: .freePoint, silent: true)
        model.checkpoint("Edit Label", coalescing: "label")
        model.objects[0].label = "A"
        model.checkpoint("Edit Label", coalescing: "label")
        model.objects[0].label = "AB"

        #expect(model.undoHistory.count == 1)
        model.undo()
        #expect(model.objects[0].label == "A")
    }

    @Test("a different coalescing key starts a new step")
    func separateEdits() {
        let model = SketchModel()
        model.add(kind: .freePoint, silent: true)
        model.checkpoint("Edit Label", coalescing: "label")
        model.checkpoint("Change Line Width", coalescing: "line-width")

        #expect(model.undoHistory.count == 2)
    }

    @Test("history reverts to the state after a chosen step")
    func revertToDepth() {
        let model = SketchModel()
        model.checkpoint("Add A")
        model.add(kind: .freePoint, silent: true)
        model.checkpoint("Add B")
        model.add(kind: .freePoint, silent: true)

        model.revert(toUndoDepth: 1)

        #expect(model.objects.count == 1)
        #expect(model.canRedo)
        #expect(model.undoActionName == "Add A")
    }
}
