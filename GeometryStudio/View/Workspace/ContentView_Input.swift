import SwiftUI
import AppKit
import Combine

extension ContentView {

    func installScrollMonitor() {
        guard scrollMonitor == nil else {
            return
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard model.isPointerOverCanvas else {
                return event
            }
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            if event.modifierFlags.contains(.command) {
                model.zoom(by: dy > 0 ? 1.06 : 0.94)
            } else if event.modifierFlags.contains(.shift) {
                model.pan(dx: dy, dy: 0)
            } else {
                model.pan(dx: dx, dy: -dy)
            }
            return nil
        }
    }

    /// Tool letters, Return for the polygon draft, arrow-key nudging and
    /// Space-to-pan. Text fields, command shortcuts and sheets keep their
    /// normal keyboard behavior.
    func installKeyMonitor() {
        guard keyMonitor == nil else {
            return
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard let window = NSApp.keyWindow, event.window === window else {
                return event
            }
            if event.type == .keyUp {
                if event.keyCode == 49 {
                    model.spacePanning = false
                }
                return event
            }
            if window is NSPanel {
                return event
            }
            if window.identifier?.rawValue.contains("Settings") == true {
                return event
            }
            if window.firstResponder is NSTextView {
                return event
            }
            if window.sheetParent != nil {
                return event
            }
            if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                return event
            }
            if model.presentationMode {
                switch event.keyCode {
                case 53:
                    model.presentationMode = false
                case 123:
                    cycleSketchWindow(by: -1)
                case 124:
                    cycleSketchWindow(by: 1)
                default:
                    return event
                }
                return nil
            }
            if event.keyCode == 49 {
                model.spacePanning = true
                return nil
            }
            if [123, 124, 125, 126].contains(event.keyCode) {
                guard !model.selection.isEmpty else {
                    return event
                }
                let step = (event.modifierFlags.contains(.shift) ? 10.0 : 1.0)
                    / model.settings.scale
                let dx: Double
                let dy: Double
                switch event.keyCode {
                case 123:
                    dx = -step
                    dy = 0
                case 124:
                    dx = step
                    dy = 0
                case 125:
                    dx = 0
                    dy = -step
                default:
                    dx = 0
                    dy = step
                }
                model.nudgeSelection(by: Vec2(dx, dy))
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                guard model.tool == .polygon, !model.draft.isEmpty else {
                    return event
                }
                model.finishPolygon()
                return nil
            }
            guard let characters = event.charactersIgnoringModifiers?.lowercased(),
                  let tool = SketchTool.allCases.first(where: {
                      String($0.shortcut.character).lowercased() == characters
                  }) else {
                return event
            }
            model.tool = tool
            return nil
        }
    }

    var paletteCommands: [PaletteCommand] {
        [
            PaletteCommand(title: "Duplicate Selection", category: "Edit",
                           symbol: "plus.square.on.square", shortcut: "⌘D") { model.duplicateSelection() },
            PaletteCommand(title: "Copy Objects", category: "Edit",
                           symbol: "doc.on.doc", shortcut: "⌘C") { model.copySelection() },
            PaletteCommand(title: "Cut Objects", category: "Edit",
                           symbol: "scissors", shortcut: "⌘X") { model.cutSelection() },
            PaletteCommand(title: "Paste Objects", category: "Edit",
                           symbol: "doc.on.clipboard", shortcut: "⌘V") { model.pasteObjects() },
            PaletteCommand(title: "Paste in Place", category: "Edit",
                           symbol: "doc.on.clipboard", shortcut: "⇧⌘V") { model.pasteObjects(inPlace: true) },
            PaletteCommand(title: "Lock or Unlock Selection", category: "Edit",
                           symbol: "lock") { model.toggleLockSelection() },
            PaletteCommand(title: "Send to Back", category: "Edit",
                           symbol: "chevron.down.square") { model.sendSelectionToBack() },
            PaletteCommand(title: "Bring to Front", category: "Edit",
                           symbol: "chevron.up.square") { model.bringSelectionToFront() },
            PaletteCommand(title: "Undo History…", category: "Edit",
                           symbol: "clock.arrow.circlepath") { showHistory = true },
            PaletteCommand(title: "Midpoint", category: "Construct",
                           symbol: "circle.dotted") { model.constructMidpoint() },
            PaletteCommand(title: "Perpendicular Line", category: "Construct",
                           symbol: "arrow.up.and.line.horizontal.and.arrow.down") { model.constructPerpendicular() },
            PaletteCommand(title: "Parallel Line", category: "Construct",
                           symbol: "equal") { model.constructParallel() },
            PaletteCommand(title: "Angle Bisector", category: "Construct",
                           symbol: "angle") { model.constructBisector() },
            PaletteCommand(title: "Intersection", category: "Construct",
                           symbol: "circle.circle") { model.constructIntersection() },
            PaletteCommand(title: "Segment", category: "Construct",
                           symbol: "line.diagonal") { model.constructSegment() },
            PaletteCommand(title: "Circle by Center + Point", category: "Construct",
                           symbol: "circle") { model.constructCircle() },
            PaletteCommand(title: "Circle by Center + Radius…", category: "Construct",
                           symbol: "circle.dashed") { showCircleRadius = true },
            PaletteCommand(title: "Arc on Circle", category: "Construct",
                           symbol: "circle.dotted") { model.constructArcOnCircle() },
            PaletteCommand(title: "Arc Through 3 Points", category: "Construct",
                           symbol: "circle.dashed") { model.constructArcThroughPoints() },
            PaletteCommand(title: "Polygon Interior", category: "Construct",
                           symbol: "pentagon") { model.constructPolygon() },
            PaletteCommand(title: "Point on Object", category: "Construct",
                           symbol: "smallcircle.filled.circle") { model.constructPointOnPath() },
            PaletteCommand(title: "Perpendicular Bisector", category: "Construct",
                           symbol: "line.diagonal") { model.constructPerpendicularBisector() },
            PaletteCommand(title: "Tangents", category: "Construct",
                           symbol: "line.diagonal.arrow") { model.constructTangents() },
            PaletteCommand(title: "Radical Axis", category: "Construct",
                           symbol: "line.diagonal") { model.constructRadicalAxis() },
            PaletteCommand(title: "Vector", category: "Construct",
                           symbol: "arrow.right") { model.constructVector() },
            PaletteCommand(title: "Vector Sum", category: "Construct",
                           symbol: "arrow.triangle.merge") { model.constructVectorSum(subtract: false) },
            PaletteCommand(title: "Vector Difference", category: "Construct",
                           symbol: "arrow.triangle.branch") { model.constructVectorSum(subtract: true) },
            PaletteCommand(title: "Parameter", category: "Construct",
                           symbol: "slider.horizontal.3") { model.addParameter() },
            PaletteCommand(title: "Cartesian Coordinate System", category: "Construct",
                           symbol: "grid") { model.constructCoordinateSystem(.cartesian) },
            PaletteCommand(title: "Polar Coordinate System", category: "Construct",
                           symbol: "circle.grid.cross") { model.constructCoordinateSystem(.polar) },
            PaletteCommand(title: "Locus", category: "Construct",
                           symbol: "scribble") { model.constructLocus() },
            PaletteCommand(title: "Construction Protocol…", category: "Construct",
                           symbol: "list.number") { showProtocol = true },
            PaletteCommand(title: "Distance", category: "Measure",
                           symbol: "ruler") { model.measure(.distance) },
            PaletteCommand(title: "Length", category: "Measure",
                           symbol: "ruler") { model.measure(.length) },
            PaletteCommand(title: "Perimeter", category: "Measure",
                           symbol: "ruler") { model.measure(.perimeter) },
            PaletteCommand(title: "Circumference", category: "Measure",
                           symbol: "ruler") { model.measure(.circumference) },
            PaletteCommand(title: "Angle", category: "Measure",
                           symbol: "angle") { model.measure(.angle) },
            PaletteCommand(title: "Area", category: "Measure",
                           symbol: "square.dashed") { model.measure(.area) },
            PaletteCommand(title: "Radius", category: "Measure",
                           symbol: "circle") { model.measure(.radius) },
            PaletteCommand(title: "Ratio", category: "Measure",
                           symbol: "divide") { model.measure(.ratio) },
            PaletteCommand(title: "Coordinates", category: "Measure",
                           symbol: "location") { model.measure(.coordinates) },
            PaletteCommand(title: "Equation", category: "Measure",
                           symbol: "function") { model.measure(.equation) },
            PaletteCommand(title: "Slope", category: "Measure",
                           symbol: "line.diagonal") { model.measure(.slope) },
            PaletteCommand(title: "Measure All", category: "Measure",
                           symbol: "ruler.fill") { model.measureAll() },
            PaletteCommand(title: "Calculate…", category: "Measure",
                           symbol: "function") {
                calculationText = ""
                showCalculation = true
            },
            PaletteCommand(title: "Plot Function…", category: "Graph",
                           symbol: "function") { showFunction = true },
            PaletteCommand(title: "Zoom to Selection", category: "View",
                           symbol: "arrow.up.left.and.arrow.down.right") {
                model.zoomToSelection(size: model.canvasSize)
            },
            PaletteCommand(title: "Actual Size", category: "View",
                           symbol: "1.magnifyingglass", shortcut: "⌘0") {
                model.setZoom(SketchMetrics.pixelsPerCentimetre)
            },
            PaletteCommand(title: "Fit Sketch", category: "View",
                           symbol: "arrow.up.left.and.arrow.down.right", shortcut: "⇧⌘F") {
                model.fitCanvas(size: model.canvasSize)
            },
            PaletteCommand(title: "Toggle Grid", category: "View",
                           symbol: "squareshape.split.2x2") { model.settings.grid.toggle() },
            PaletteCommand(title: "Toggle Axes", category: "View",
                           symbol: "chart.xyaxis.line") { model.settings.axes.toggle() },
            PaletteCommand(title: "Toggle Grid Snapping", category: "View",
                           symbol: "grid.circle") { model.settings.snap.toggle() },
            PaletteCommand(title: "Toggle Inspector", category: "View",
                           symbol: "sidebar.right", shortcut: "⌥⌘I") { model.inspectorVisible.toggle() },
            PaletteCommand(title: "Undo", category: "Edit",
                           symbol: "arrow.uturn.backward", shortcut: "⌘Z") { model.undo() },
            PaletteCommand(title: "Redo", category: "Edit",
                           symbol: "arrow.uturn.forward", shortcut: "⇧⌘Z") { model.redo() }
        ]
    }

    /// Presentation paging: move to the previous or next open sketch window,
    /// skipping panels, sheets and the Settings window.
    func cycleSketchWindow(by offset: Int) {
        let windows = NSApp.orderedWindows.filter { window in
            window.isVisible
                && !(window is NSPanel)
                && window.sheetParent == nil
                && window.parent == nil
                && window.identifier?.rawValue.contains("Settings") != true
        }
        guard windows.count > 1, let current = NSApp.keyWindow,
              let index = windows.firstIndex(of: current) else {
            return
        }
        let next = (index + offset + windows.count) % windows.count
        windows[next].makeKeyAndOrderFront(nil)
    }
}
