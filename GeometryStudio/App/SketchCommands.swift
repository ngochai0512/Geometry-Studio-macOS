import AppKit
import SwiftUI

struct SketchCommands: Commands {
    @FocusedValue(\.sketchModel) private var model

    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else {
            return false
        }
        return responder is NSTextView
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Geometry Studio") { model?.showAbout = true }
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Delete") {
                if isEditingText {
                    NSApp.sendAction(#selector(NSResponder.deleteBackward(_:)), to: nil, from: nil)
                } else {
                    model?.deleteSelection()
                }
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(model?.selection.isEmpty != false && !isEditingText)
            Button("Select All") {
                if isEditingText {
                    NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                } else {
                    model?.selectAll()
                }
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(model == nil)
            Divider()
            Button("Duplicate") { model?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model?.selection.isEmpty != false)
            Button("Copy Objects") { model?.copySelection() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model?.selection.isEmpty != false)
            Button("Cut Objects") { model?.cutSelection() }
                .keyboardShortcut("x", modifiers: [.command, .option])
                .disabled(model?.selection.isEmpty != false)
            Button("Paste Objects") { model?.pasteObjects() }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(model?.canPasteObjects != true)
            Button("Paste in Place") { model?.pasteObjects(inPlace: true) }
                .keyboardShortcut("v", modifiers: [.command, .control])
                .disabled(model?.canPasteObjects != true)
            Button("Undo History…") {
                NotificationCenter.default.post(name: .openUndoHistory, object: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(model == nil)
        }

        CommandGroup(after: .saveItem) {
            Divider()
            Menu("Export") {
                ForEach(SketchExportFormat.allCases) { format in
                    Button("\(format.title)…") {
                        if let model {
                            SketchExporter.export(format, model: model)
                        }
                    }
                }
            }
            .disabled(model == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                if let model {
                    SketchPrinter.printSketch(model)
                }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(model == nil)

            Button("Page Setup…") {
                SketchPrinter.runPageSetup()
            }
        }

        CommandMenu("Construct") {
            Button("Midpoint") { model?.constructMidpoint() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Perpendicular Line") { model?.constructPerpendicular() }
                .disabled(model == nil)
            Button("Parallel Line") { model?.constructParallel() }
                .disabled(model == nil)
            Button("Angle Bisector") { model?.constructBisector() }
                .disabled(model == nil)
            Button("Intersection") { model?.constructIntersection() }
                .disabled(model == nil)
            Divider()
            Button("Segment") { model?.constructSegment() }
                .disabled(model == nil)
            Button("Circle by Center + Point") { model?.constructCircle() }
                .disabled(model == nil)
            Button("Circle by Center + Radius…") {
                NotificationCenter.default.post(name: .openCircleRadius, object: nil)
            }
            .disabled(model == nil)
            Button("Arc on Circle") { model?.constructArcOnCircle() }
                .disabled(model == nil)
            Button("Arc Through 3 Points") { model?.constructArcThroughPoints() }
                .disabled(model == nil)
            Button("Polygon Interior") { model?.constructPolygon() }
                .disabled(model == nil)
            Button("Point on Object") { model?.constructPointOnPath() }
                .disabled(model == nil)
            Divider()
            Button("Perpendicular Bisector") { model?.constructPerpendicularBisector() }
                .disabled(model == nil)
            Button("Tangents") { model?.constructTangents() }
                .disabled(model == nil)
            Button("Radical Axis") { model?.constructRadicalAxis() }
                .disabled(model == nil)
            Button("Vector") { model?.constructVector() }
                .disabled(model == nil)
            Button("Vector Sum") { model?.constructVectorSum(subtract: false) }
                .disabled(model == nil)
            Button("Vector Difference") { model?.constructVectorSum(subtract: true) }
                .disabled(model == nil)
            Button("Parameter") { model?.addParameter() }
                .disabled(model == nil)
            Menu("Coordinate System") {
                Button("Cartesian") { model?.constructCoordinateSystem(.cartesian) }
                Button("Polar") { model?.constructCoordinateSystem(.polar) }
            }
            .disabled(model == nil)
            Divider()
            Button("Locus from Selection") { model?.constructLocus() }
                .disabled(model == nil)
            Divider()
            Button("Construction Protocol…") {
                NotificationCenter.default.post(name: .openProtocol, object: nil)
            }
            .disabled(model == nil)
        }

        CommandMenu("Measure") {
            Button("Distance") { model?.measure(.distance) }
                .disabled(model == nil)
            Button("Length") { model?.measure(.length) }
                .disabled(model == nil)
            Button("Perimeter") { model?.measure(.perimeter) }
                .disabled(model == nil)
            Button("Circumference") { model?.measure(.circumference) }
                .disabled(model == nil)
            Button("Angle") { model?.measure(.angle) }
                .disabled(model == nil)
            Button("Arc Angle") { model?.measure(.arcAngle) }
                .disabled(model == nil)
            Button("Arc Length") { model?.measure(.arcLength) }
                .disabled(model == nil)
            Button("Area") { model?.measure(.area) }
                .disabled(model == nil)
            Button("Radius") { model?.measure(.radius) }
                .disabled(model == nil)
            Button("Ratio") { model?.measure(.ratio) }
                .disabled(model == nil)
            Divider()
            Button("Coordinates") { model?.measure(.coordinates) }
                .disabled(model == nil)
            Button("Abscissa") { model?.measure(.abscissa) }
                .disabled(model == nil)
            Button("Ordinate") { model?.measure(.ordinate) }
                .disabled(model == nil)
            Button("Polar Distance") { model?.measure(.polarDistance) }
                .disabled(model == nil)
            Button("Polar Direction") { model?.measure(.polarDirection) }
                .disabled(model == nil)
            Button("Coordinate Distance") { model?.measure(.coordinateDistance) }
                .disabled(model == nil)
            Button("Equation") { model?.measure(.equation) }
                .disabled(model == nil)
            Button("Slope") { model?.measure(.slope) }
                .disabled(model == nil)
            Divider()
            Button("Measure All") { model?.measureAll() }
                .disabled(model == nil)
            Divider()
            Button("Calculate…") {
                NotificationCenter.default.post(name: .openCalculation, object: nil)
            }
            .disabled(model == nil)
            Button("Plot Function…") {
                NotificationCenter.default.post(name: .openFunction, object: nil)
            }
            .disabled(model == nil)
        }

        CommandMenu("Transform") {
            Button("Mark Mirror") { model?.markMirror() }
                .disabled(model == nil)
            Button("Mark Center") { model?.markCenter() }
                .disabled(model == nil)
            Button("Mark Angle") { model?.markAngle() }
                .disabled(model == nil)
            Button("Mark Ratio") { model?.markRatio() }
                .disabled(model == nil)
            Button("Mark Vector") { model?.markVector() }
                .disabled(model == nil)
            Divider()
            Button("Reflect") { model?.reflectSelection() }
                .disabled(model == nil)
            Button("Rotate") { model?.rotateSelection() }
                .disabled(model == nil)
            Button("Dilate") { model?.dilateSelection() }
                .disabled(model == nil)
            Button("Translate") { model?.translateSelection() }
                .disabled(model == nil)
            Divider()
            Button("Clear Marks") { model?.clearMarks() }
                .disabled(model == nil)
        }

        CommandMenu("Graph") {
            Button(model?.settings.grid == true ? "Hide Grid" : "Show Grid") {
                model?.settings.grid.toggle()
            }
            .disabled(model == nil)
            Button(model?.settings.axes == true ? "Hide Axes" : "Show Axes") {
                model?.settings.axes.toggle()
            }
            .disabled(model == nil)
            Button(model?.settings.snap == true ? "Turn Snapping Off" : "Snap Points to Grid") {
                model?.settings.snap.toggle()
            }
            .disabled(model == nil)
            Divider()
            Button("Plot Function…") {
                NotificationCenter.default.post(name: .openFunction, object: nil)
            }
            .disabled(model == nil)
            Divider()
            Button("Plot Derivative") { model?.addDerivativePlot() }
                .disabled(model == nil)
            Button("Shade Integral") { model?.addIntegralPlot() }
                .disabled(model == nil)
            Button("Tangent at x") { model?.addTangentAt() }
                .disabled(model == nil)
            Button("Value Table") { model?.addValueTable() }
                .disabled(model == nil)
            Button("Find Roots") { model?.findFunctionRoots() }
                .disabled(model == nil)
            Button("Find Intersections") { model?.findFunctionIntersections() }
                .disabled(model == nil)
        }

        CommandMenu("Display") {
            Button("Show Labels") { model?.settings.showLabels = true }
                .disabled(model == nil)
            Button("Hide Labels") { model?.settings.showLabels = false }
                .disabled(model == nil)
            Divider()
            Button("Hide Selected") { model?.hideSelection() }
                .disabled(model?.selection.isEmpty != false)
            Button("Show All Hidden") { model?.showAll() }
                .disabled(model == nil)
            Divider()
            Button(model?.animationPointID == nil ? "Animate" : "Pause Animation") {
                model?.toggleAnimation()
            }
            .keyboardShortcut("`", modifiers: [])
            .disabled(model == nil)
            Button("Trace Selection") { model?.toggleTrace() }
                .disabled(model == nil)
            Button("Erase Traces") { model?.eraseTraces() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model == nil)
            Divider()
            Button("Fit Sketch") {
                if let model {
                    model.fitCanvas(size: model.canvasSize)
                }
            }
            .disabled(model == nil)
            Button(model?.inspectorVisible == true ? "Hide Inspector" : "Show Inspector") {
                model?.inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(model == nil)
            Divider()
            Button("Command Palette…") {
                NotificationCenter.default.post(name: .openCommandPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(model == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Geometry Studio Tips") {
                NotificationCenter.default.post(name: .openTips, object: nil)
            }
        }
    }
}
