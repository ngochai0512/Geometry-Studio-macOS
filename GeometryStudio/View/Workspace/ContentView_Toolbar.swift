import SwiftUI
import AppKit
import Combine

extension ContentView {

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .help(model.undoActionName.map { "Undo \($0)" } ?? "Undo")
            .disabled(!model.canUndo)

            Button {
                model.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .help(model.redoActionName.map { "Redo \($0)" } ?? "Redo")
            .disabled(!model.canRedo)
        }

        ForEach(SketchTool.allCases) { tool in
            ToolbarItem(id: tool.rawValue, placement: .principal) {
                Toggle(isOn: toolBinding(tool)) {
                    Label(tool.title, systemImage: tool.symbol)
                }
                .toggleStyle(.button)
                .help("\(tool.title) (\(String(tool.shortcut.character)))")
                // Toolbar content caches its selected look; rebuild it when
                // the active tool changes so the highlight follows the model.
                .id(model.tool)
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.zoom(by: 0.84)
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .help("Zoom out")

            Menu {
                Button("50%") { model.setZoom(31) }
                Button("75%") { model.setZoom(46.5) }
                Button("100%") { model.setZoom(SketchMetrics.pixelsPerCentimetre) }
                Button("150%") { model.setZoom(93) }
                Button("200%") { model.setZoom(124) }
                Divider()
                Button("Fit Sketch") { model.fitCanvas(size: model.canvasSize) }
                Button("Zoom to Selection") { model.zoomToSelection(size: model.canvasSize) }
                    .disabled(model.selection.isEmpty)
                Button("Actual Size") { model.setZoom(SketchMetrics.pixelsPerCentimetre) }
            } label: {
                Text("\(Int(model.settings.scale / SketchMetrics.pixelsPerCentimetre * 100))%")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 40)
            }
            .menuIndicator(.hidden)
            .help("Zoom")

            Button {
                model.zoom(by: 1.19)
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .help("Zoom in")

            constructMenu
            measureMenu

            gridMenu
            shareMenu

            Toggle(isOn: $model.inspectorVisible) {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .toggleStyle(.button)
            .help("Show or hide the inspector")
        }
    }

    /// One real toolbar item per tool, centered, so Icon and Text mode shows
    /// each title like the other items; a segmented Picker or a single
    /// principal group fuses into one custom item and ignores display mode.
    func toolBinding(_ tool: SketchTool) -> Binding<Bool> {
        Binding(
            get: { model.tool == tool },
            set: { isOn in
                if isOn, model.tool != tool {
                    model.tool = tool
                }
            }
        )
    }

    /// Floating command palette, pinned near the top of the canvas.
    @ViewBuilder
    var paletteOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { showPalette = false }
            CommandPalettePanel(commands: paletteCommands,
                                recents: $recentPalette,
                                onClose: { showPalette = false })
                .padding(.top, 64)
        }
    }

    /// Export result, with a path to the file in Finder. Clears itself after
    /// a few seconds or when dismissed.
    @ViewBuilder
    var exportToast: some View {
        if let notice = exportNotice {
            HStack(spacing: 10) {
                Image(systemName: notice.url == nil
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notice.url == nil ? .orange : .green)
                Text(notice.message)
                    .font(.callout)
                    .lineLimit(1)
                if let url = notice.url {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.link)
                }
                Button {
                    exportNotice = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.quaternary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.bottom, 36)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: notice.message) {
                try? await Task.sleep(for: .seconds(5))
                if exportNotice?.message == notice.message {
                    exportNotice = nil
                }
            }
        }
    }

    /// Toolbar grid control: the current state plus the grid, axis and snap
    /// options that used to live in the inspector.
    var gridMenu: some View {
        Menu {
            Toggle("Show Grid", isOn: $model.settings.grid)

            Picker("Grid Style", selection: $model.settings.gridType) {
                ForEach(GridType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }

            Picker("Grid Color", selection: $model.settings.gridColor) {
                ForEach(RGBA.gridPalette, id: \.0) { name, color in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color.color)
                            .frame(width: 10, height: 10)
                        Text(name)
                    }
                    .tag(color)
                }
            }

            Toggle("Bold Grid", isOn: $model.settings.gridBold)

            Divider()

            Toggle("Show Axes", isOn: $model.settings.axes)
            Toggle("Axes Numbers", isOn: $model.settings.axesLabels)

            Picker("Axis Label Style", selection: $model.settings.axesLabelStyle) {
                ForEach(AxisLabelStyle.presets, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }

            Divider()

            Toggle("Snap to Grid", isOn: $model.settings.snap)
            Toggle("Smart Guides", isOn: $model.settings.smartGuides)

            Picker("Angle Snap", selection: $model.settings.angleSnap) {
                ForEach(CanvasSettings.angleSnapChoices, id: \.self) { angle in
                    Text(angle == 0 ? "Off" : "\(Int(angle))°").tag(angle)
                }
            }

            Divider()

            Button("Canvas Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        } label: {
            Label(model.settings.grid ? "Grid" : "Grid Off",
                  systemImage: "squareshape.split.2x2")
        }
        .help("Grid, axes and snapping options")
    }

    /// Shares the sketch as a lazily rendered PDF or PNG.
    var shareMenu: some View {
        let name = SketchExporter.suggestedName(for: model)
        return Menu {
            ShareLink(item: SketchPDFShare(document: model.document, name: name),
                      preview: SharePreview("\(name).pdf")) {
                Label("PDF", systemImage: "doc.richtext")
            }
            ShareLink(item: SketchPNGShare(document: model.document, name: name),
                      preview: SharePreview("\(name).png")) {
                Label("PNG", systemImage: "photo")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .help("Share the sketch as PDF or PNG")
    }

    var constructMenu: some View {
        Menu {
            Button("Midpoint") { model.constructMidpoint() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Perpendicular Line") { model.constructPerpendicular() }
            Button("Parallel Line") { model.constructParallel() }
            Button("Angle Bisector") { model.constructBisector() }
            Button("Intersection") { model.constructIntersection() }
            Divider()
            Button("Segment") { model.constructSegment() }
            Button("Circle by Center + Point") { model.constructCircle() }
            Button("Circle by Center + Radius…") {
                NotificationCenter.default.post(name: .openCircleRadius, object: nil)
            }
            Button("Arc on Circle") { model.constructArcOnCircle() }
            Button("Arc Through 3 Points") { model.constructArcThroughPoints() }
            Button("Polygon Interior") { model.constructPolygon() }
            Button("Point on Object") { model.constructPointOnPath() }
            Divider()
            Button("Perpendicular Bisector") { model.constructPerpendicularBisector() }
            Button("Tangents") { model.constructTangents() }
            Button("Radical Axis") { model.constructRadicalAxis() }
            Button("Vector") { model.constructVector() }
            Button("Vector Sum") { model.constructVectorSum(subtract: false) }
            Button("Vector Difference") { model.constructVectorSum(subtract: true) }
            Button("Parameter") { model.addParameter() }
            Menu("Coordinate System") {
                Button("Cartesian") { model.constructCoordinateSystem(.cartesian) }
                Button("Polar") { model.constructCoordinateSystem(.polar) }
            }
            Divider()
            Button("Locus") { model.constructLocus() }
            Divider()
            Button("Construction Protocol…") {
                NotificationCenter.default.post(name: .openProtocol, object: nil)
            }
        } label: {
            Label("Construct", systemImage: "hammer")
        }
        .help("Construct objects from the selection")
    }

    var measureMenu: some View {
        Menu {
            Button("Distance") { model.measure(.distance) }
            Button("Length") { model.measure(.length) }
            Button("Perimeter") { model.measure(.perimeter) }
            Button("Circumference") { model.measure(.circumference) }
            Button("Angle") { model.measure(.angle) }
            Button("Arc Angle") { model.measure(.arcAngle) }
            Button("Arc Length") { model.measure(.arcLength) }
            Button("Area") { model.measure(.area) }
            Button("Radius") { model.measure(.radius) }
            Button("Ratio") { model.measure(.ratio) }
            Divider()
            Button("Coordinates") { model.measure(.coordinates) }
            Button("Abscissa") { model.measure(.abscissa) }
            Button("Ordinate") { model.measure(.ordinate) }
            Button("Polar Distance") { model.measure(.polarDistance) }
            Button("Polar Direction") { model.measure(.polarDirection) }
            Button("Coordinate Distance") { model.measure(.coordinateDistance) }
            Button("Equation") { model.measure(.equation) }
            Button("Slope") { model.measure(.slope) }
            Divider()
            Button("Measure All") { model.measureAll() }
            Divider()
            Button("Calculate…") {
                calculationText = ""
                showCalculation = true
            }
        } label: {
            Label("Measure", systemImage: "ruler")
        }
        .help("Measure the selection")
    }
}
