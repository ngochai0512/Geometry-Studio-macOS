import SwiftUI
import AppKit

struct SketchCommands: Commands {
    @ObservedObject var model: SketchModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Geometry Studio") { model.showAbout = true }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Sketch") { model.newSketch() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open…") { model.open() }
                .keyboardShortcut("o", modifiers: .command)
            Divider()
            Button("Load Welcome Sketch") { model.loadSample() }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Save As…") { model.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
            Button("Redo") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Delete") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selection.isEmpty)
            Button("Select All") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
        }

        CommandMenu("Construct") {
            Button("Midpoint") { model.constructMidpoint() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Perpendicular Line") { model.constructPerpendicular() }
            Button("Parallel Line") { model.constructParallel() }
            Button("Angle Bisector") { model.constructBisector() }
            Button("Intersection") { model.constructIntersection() }
            Divider()
            Button("Segment") { model.constructSegment() }
            Button("Circle by Center + Point") { model.constructCircle() }
            Button("Polygon Interior") { model.constructPolygon() }
            Button("Point on Object") { model.constructPointOnPath() }
            Divider()
            Button("Locus from Selection") { model.constructLocus() }
            Divider()
            Button("Midpoint of Two Points") { model.constructMidpoint() }
        }

        CommandMenu("Measure") {
            Button("Distance") { model.measure(.distance) }
            Button("Length") { model.measure(.length) }
            Button("Perimeter") { model.measure(.perimeter) }
            Button("Circumference") { model.measure(.circumference) }
            Button("Angle") { model.measure(.angle) }
            Button("Area") { model.measure(.area) }
            Button("Radius") { model.measure(.radius) }
            Button("Ratio") { model.measure(.ratio) }
            Divider()
            Button("Coordinates") { model.measure(.coordinates) }
            Button("Equation") { model.measure(.equation) }
            Button("Slope") { model.measure(.slope) }
            Divider()
            Button("Calculate…") {
                NotificationCenter.default.post(name: .openCalculation, object: nil)
            }
            Button("Plot Function…") {
                NotificationCenter.default.post(name: .openFunction, object: nil)
            }
        }

        CommandMenu("Transform") {
            Button("Reflect Across Selected Line") { model.reflectSelection() }
            Divider()
            Button("Rotate…") { NotificationCenter.default.post(name: .openRotate, object: nil) }
            Button("Dilate…") { NotificationCenter.default.post(name: .openDilate, object: nil) }
            Button("Translate…") { NotificationCenter.default.post(name: .openTranslate, object: nil) }
        }

        CommandMenu("Graph") {
            Button(model.settings.grid ? "Hide Grid" : "Show Grid") {
                model.settings.grid.toggle()
            }
            Button(model.settings.axes ? "Hide Axes" : "Show Axes") {
                model.settings.axes.toggle()
            }
            Button(model.settings.snap ? "Turn Snapping Off" : "Snap Points to Grid") {
                model.settings.snap.toggle()
            }
            Divider()
            Button("Plot Function…") {
                NotificationCenter.default.post(name: .openFunction, object: nil)
            }
        }

        CommandMenu("Display") {
            Button("Show Labels") {
                model.settings.showLabels = true
            }
            Button("Hide Labels") {
                model.settings.showLabels = false
            }
            Divider()
            Button("Hide Selected") { model.hideSelection() }
                .disabled(model.selection.isEmpty)
            Button("Show All Hidden") { model.showAll() }
            Divider()
            Button(model.animationPointID == nil ? "Animate" : "Pause Animation") {
                model.toggleAnimation()
            }
            .keyboardShortcut("`", modifiers: [])
            Button("Trace Selection") { model.toggleTrace() }
            Button("Erase Traces") { model.eraseTraces() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Fit Sketch") {
                model.fitCanvas(size: CGSize(width: 980, height: 740))
            }
            Button(model.inspectorVisible ? "Hide Inspector" : "Show Inspector") {
                model.inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
