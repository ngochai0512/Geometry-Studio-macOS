import SwiftUI

struct SketchCommands: Commands {
    @FocusedValue(\.sketchModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Geometry Studio") { model?.showAbout = true }
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Delete") { model?.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model?.selection.isEmpty != false)
            Button("Select All") { model?.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
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
            Button("Equation") { model?.measure(.equation) }
                .disabled(model == nil)
            Button("Slope") { model?.measure(.slope) }
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
            Button("Reflect Across Selected Line") { model?.reflectSelection() }
                .disabled(model == nil)
            Divider()
            Button("Rotate…") { NotificationCenter.default.post(name: .openRotate, object: nil) }
                .disabled(model == nil)
            Button("Dilate…") { NotificationCenter.default.post(name: .openDilate, object: nil) }
                .disabled(model == nil)
            Button("Translate…") { NotificationCenter.default.post(name: .openTranslate, object: nil) }
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
                model?.fitCanvas(size: CGSize(width: 980, height: 740))
            }
            .disabled(model == nil)
            Button(model?.inspectorVisible == true ? "Hide Inspector" : "Show Inspector") {
                model?.inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(model == nil)
        }
    }
}
