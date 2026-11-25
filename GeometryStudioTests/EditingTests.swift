import Foundation
import Testing
@testable import GeometryStudio

@MainActor
@Suite("Editing and measurement")
struct EditingTests {
    private func point(_ model: SketchModel, _ x: Double, _ y: Double) -> UUID {
        model.add(kind: .freePoint, position: Vec2(x, y), silent: true)
    }

    private func measurement(_ model: SketchModel) -> SketchObject? {
        model.objects.first { object in
            if case .measurement = object.kind {
                return true
            }
            return false
        }
    }

    @Test("smart guides snap to a segment midpoint")
    func smartGuideMidpoint() {
        let model = SketchModel()
        let a = point(model, 0, 0)
        let b = point(model, 4, 0)
        model.add(kind: .segment(a: a, b: b), silent: true)

        let result = model.smartSnappedPoint(Vec2(2.03, 0.02), tolerance: 0.1)

        #expect(result.point.distance(to: Vec2(2, 0)) < 1e-9)
        #expect(result.guides.contains { $0.kind == .midpoint })
    }

    @Test("angle snapping rounds the drawing direction around the anchor")
    func angleSnap() {
        var settings = CanvasSettings()
        settings.angleSnap = 15
        settings.smartGuides = false
        let model = SketchModel()
        model.settings = settings

        let snapped = model.angleSnappedPoint(Vec2(10, 6), anchor: .zero)

        #expect(abs(snapped.angle - .pi / 6) < 1e-9)
        #expect(abs(snapped.length - hypot(10, 6)) < 1e-9)
    }

    @Test("duplicating a point gives it a fresh label")
    func duplicatePointLabel() {
        let model = SketchModel()
        let a = point(model, 0, 0)
        model.selection = [a]

        let copies = model.duplicateSelection()
        guard let copy = copies.first.flatMap({ model.objectByID($0) }) else {
            Issue.record("expected a duplicated point")
            return
        }
        #expect(copies.count == 1)
        #expect(!copy.label.isEmpty)
        #expect(copy.label != "A")
    }

    @Test("duplicating a segment rewires it to copied endpoints")
    func duplicateSegmentWiring() {
        let model = SketchModel()
        let a = point(model, 0, 0)
        let b = point(model, 3, 0)
        let segment = model.add(kind: .segment(a: a, b: b), silent: true)
        model.selection = [segment]

        let copies = model.duplicateSelection()
        #expect(copies.count == 3)

        var copiedSegment: SketchObject?
        for id in copies {
            guard let object = model.objectByID(id),
                  case .segment(let first, let second) = object.kind else {
                continue
            }
            copiedSegment = object
            #expect(first != a && first != b)
            #expect(second != a && second != b)
            #expect(copies.contains(first))
            #expect(copies.contains(second))
        }
        #expect(copiedSegment != nil)
    }

    @Test("a locked object keeps its label")
    func lockedLabelCannotChange() {
        let model = SketchModel()
        let a = point(model, 0, 0)
        model.selection = [a]
        model.toggleLockSelection()

        model.setLabelText(a, "Z")

        #expect(model.objectByID(a)?.label == "A")
        #expect(model.objectByID(a)?.isLocked == true)
    }

    @Test("a selected polygon exposes its free vertices as transform handles")
    func polygonTransformHandles() {
        let model = SketchModel()
        let a = point(model, 0, 0)
        let b = point(model, 2, 0)
        let c = point(model, 0, 2)
        let polygon = model.add(kind: .polygon(vertices: [a, b, c]), silent: true)
        model.selection = [polygon]

        #expect(model.canTransformSelection)
        guard let bounds = model.movableSelectionBounds() else {
            Issue.record("expected selection bounds")
            return
        }
        let base = model.movableSelectionPositions()
        #expect(base.count == 3)

        model.applyMovableSelection(base, around: bounds.center, scale: 2, rotation: 0)

        guard let before = base[a], let after = model.objectByID(a)?.position else {
            Issue.record("expected point A to move")
            return
        }
        #expect(abs((after - bounds.center).length
                    - (before - bounds.center).length * 2) < 1e-9)
    }

    @Test("coordinates honor a selected coordinate system")
    func coordinateSystemMeasurement() {
        let model = SketchModel()
        let origin = point(model, 0, 0)
        let p = point(model, 3, 4)
        let system = model.add(kind: .coordinateSystem(kind: .cartesian,
                                                       origin: origin,
                                                       step: 2.54,
                                                       unit: .inches),
                               silent: true)
        model.selection = [p, system]

        model.measure(.coordinates)

        guard let measurement = measurement(model) else {
            Issue.record("expected a coordinates measurement")
            return
        }
        var evaluator = model.evaluator()
        let result = evaluator.evaluate(measurement.id)
        #expect(result.text?.contains(" in") == true)
        #expect(abs((result.value ?? 0) - 3) < 1e-9)
    }

    @Test("function roots are tied to the function plot")
    func functionRootsTrackPlot() {
        let model = SketchModel()
        let plot = model.add(kind: .functionPlot("x"), silent: true)
        model.selection = [plot]

        model.findFunctionRoots()

        guard let rootID = model.selection.first,
              let root = model.objectByID(rootID),
              case .pointOnPath(let path, _) = root.kind else {
            Issue.record("expected a root point on the plot")
            return
        }
        #expect(path == plot)
        var evaluator = model.evaluator()
        guard let position = evaluator.evaluate(rootID).point else {
            Issue.record("expected the root to evaluate")
            return
        }
        #expect(abs(position.y) < 1e-6)
    }

    @Test("point on object follows a function plot")
    func pointOnFunctionPlot() {
        let model = SketchModel()
        let plot = model.add(kind: .functionPlot("x^2"), silent: true)
        model.selection = [plot]
        model.hoverWorld = Vec2(2, 0)

        model.constructPointOnPath()

        guard let pointID = model.selection.first else {
            Issue.record("expected a point on the function")
            return
        }
        var evaluator = model.evaluator()
        guard let position = evaluator.evaluate(pointID).point else {
            Issue.record("expected the point to evaluate")
            return
        }
        #expect(abs(position.x - 2) < 1e-9)
        #expect(abs(position.y - 4) < 1e-9)
    }

    @Test("selection totals do not count polygon edges twice")
    func selectionTotals() {
        let model = SketchModel()
        let a = point(model, 0, 0)
        let b = point(model, 4, 0)
        let c = point(model, 0, 3)
        let polygon = model.add(kind: .polygon(vertices: [a, b, c]), silent: true)
        let ab = model.add(kind: .segment(a: a, b: b), silent: true)
        let bc = model.add(kind: .segment(a: b, b: c), silent: true)
        let ca = model.add(kind: .segment(a: c, b: a), silent: true)
        model.selection = [polygon, ab, bc, ca]

        guard let metrics = model.selectionMetrics() else {
            Issue.record("expected selection metrics")
            return
        }
        #expect(abs(metrics.perimeter - 12) < 1e-9)
        #expect(abs(metrics.area - 6) < 1e-9)
    }

    @Test("undo history travels back and forward")
    func historyTravel() {
        let model = SketchModel()
        let manager = UndoManager()
        model.undoManager = manager

        model.checkpoint("Add A")
        model.add(kind: .freePoint, position: Vec2(0, 0), silent: true)
        model.checkpoint("Add B")
        model.add(kind: .freePoint, position: Vec2(1, 0), silent: true)

        #expect(model.undoHistory.count == 2)
        #expect(model.undoHistoryIndex == 2)

        model.travelHistory(to: 0)
        #expect(model.objects.isEmpty)
        #expect(model.undoHistoryIndex == 0)

        model.travelHistory(to: 2)
        #expect(model.objects.count == 2)
        #expect(model.undoHistoryIndex == 2)
    }
}
