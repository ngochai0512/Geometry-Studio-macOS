import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @Bindable var model: SketchModel
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.newDocument) private var newDocument
    var presentsOnboarding: Bool = true

    @State private var textAnchor: Vec2 = .zero
    @State private var showTextSheet = false
    @State private var textDraft = ""
    @State private var showCircleRadius = false
    @State private var showProtocol = false
    @State private var showFunction = false
    @State private var showCalculation = false
    @State private var showWelcome = false
    @State private var welcomeFirstRun = true
    @State private var showPalette = false
    @State private var showHistory = false
    @State private var recentPalette: [String] = []
    @State private var exportNotice: ExportNotice?
    @State private var circleRadius: Double = 2
    @State private var functionText = "sin(x)"
    @State private var calculationText = ""
    @State private var scrollMonitor: Any?
    @State private var keyMonitor: Any?
    private struct ExportNotice: Equatable {
        var message: String
        var url: URL?
    }

    init(model: SketchModel, presentsOnboarding: Bool = true) {
        _model = Bindable(wrappedValue: model)
        self.presentsOnboarding = presentsOnboarding
    }

    var body: some View {
        SketchCanvas(model: model) { point in
            textAnchor = point
            textDraft = ""
            showTextSheet = true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inspector(isPresented: $model.inspectorVisible) {
            InspectorView(model: model,
                          onTextAnnotation: { point in
                              textAnchor = point
                              textDraft = ""
                              showTextSheet = true
                          })
                .inspectorColumnWidth(min: 280, ideal: 306, max: 380)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SketchStatusBar(model: model)
        }
        .toolbar {
            toolbarContent
        }
        .overlay(alignment: .top) {
            if showPalette {
                paletteOverlay
            }
        }
        .overlay(alignment: .bottom) {
            exportToast
        }
        .animation(.easeInOut(duration: 0.2), value: exportNotice)
        .onChange(of: model.tool) { _, _ in
            model.draft = []
        }
        .onChange(of: controlActiveState) { _, state in
            if state != .inactive {
                ActiveSketch.model = model
            } else {
                model.spacePanning = false
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: installScrollMonitor)
        .onAppear(perform: installKeyMonitor)
        .onChange(of: showPalette) { _, open in
            // Tool letters belong to the palette search while it is open.
            model.spacePanning = false
            if open {
                if let monitor = keyMonitor {
                    NSEvent.removeMonitor(monitor)
                    keyMonitor = nil
                }
            } else {
                installKeyMonitor()
            }
        }
        .onAppear {
            ActiveSketch.model = model
        }
        .onDisappear {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
            }
            scrollMonitor = nil
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
            keyMonitor = nil
            if ActiveSketch.model === model {
                ActiveSketch.model = nil
            }
        }
        .onExitCommand {
            if model.draft.isEmpty {
                model.tool = .select
            } else {
                model.cancelDraft()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCircleRadius)) { _ in
            showCircleRadius = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProtocol)) { _ in
            showProtocol = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportFinished)) { note in
            guard note.object as? SketchModel === model else {
                return
            }
            if let url = note.userInfo?["url"] as? URL {
                exportNotice = ExportNotice(message: "Exported \(url.lastPathComponent)",
                                            url: url)
            } else if let message = note.userInfo?["message"] as? String {
                exportNotice = ExportNotice(message: message, url: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTextAnnotation)) { _ in
            textAnchor = model.settings.center
            textDraft = ""
            showTextSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFunction)) { _ in
            showFunction = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCalculation)) { _ in
            calculationText = ""
            showCalculation = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
            showPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openUndoHistory)) { _ in
            showHistory = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTips)) { _ in
            welcomeFirstRun = false
            showWelcome = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSketchRequested)) { _ in
            guard ActiveSketch.model === model else {
                return
            }
            newDocument(contentType: .geometryStudioSketch)
        }
        .onAppear {
            if presentsOnboarding, !AppPreferences.hasCompletedOnboarding() {
                welcomeFirstRun = true
                showWelcome = true
            }
        }
        .sheet(isPresented: $showTextSheet) {
            AddTextSheet(text: $textDraft) { text in
                model.checkpoint("Add Text")
                let id = model.add(kind: .caption(text), position: textAnchor, silent: true)
                model.selection = [id]
            }
        }
        .sheet(isPresented: $showCircleRadius) {
            CircleRadiusSheet(radius: $circleRadius,
                              centerName: circleCenterName(),
                              unit: model.settings.lengthUnit.short) { radius in
                model.constructCircleRadius(radius)
            }
        }
        .sheet(isPresented: $showProtocol) {
            ProtocolSheet(steps: model.constructionProtocol())
        }
        .sheet(isPresented: $showFunction) {
            FunctionSheet(text: $functionText) { expression in
                model.addFunctionPlot(expression: expression)
            }
        }
        .sheet(isPresented: $showCalculation) {
            CalculationSheet(text: $calculationText, names: measurementNames()) { expression in
                model.addCalculation(expression: expression)
            }
        }
        .sheet(isPresented: $showWelcome, onDismiss: {
            AppPreferences.markOnboardingCompleted()
        }) {
            WelcomeSheet(isFirstRun: welcomeFirstRun,
                         onTemplate: { template in
                             openTemplate(template)
                         })
        }
        .sheet(isPresented: $showHistory) {
            UndoHistorySheet(model: model)
        }
        .sheet(isPresented: $model.showAbout) { AboutView() }
    }

    // MARK: toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
    private func toolBinding(_ tool: SketchTool) -> Binding<Bool> {
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
    private var paletteOverlay: some View {
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
    private var exportToast: some View {
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
    private var gridMenu: some View {
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

    private var constructMenu: some View {
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

    private var measureMenu: some View {
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

    // MARK: scroll monitor

    private func installScrollMonitor() {
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
    private func installKeyMonitor() {
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

    // MARK: palette and templates

    private func openTemplate(_ template: SketchTemplate) {
        TemplateLibrary.pending = template
        newDocument(contentType: .geometryStudioSketch)
        // A failed or abandoned new-document action must not turn the next
        // ordinary new sketch into the starter sample.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if TemplateLibrary.pending != nil {
                TemplateLibrary.pending = nil
            }
        }
    }

    private var paletteCommands: [PaletteCommand] {
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

    // MARK: selection helpers

    private func measurementNames() -> [String] {
        var out: [String] = []
        for object in model.objects {
            if case .measurement = object.kind, !object.label.isEmpty {
                out.append(object.label.replacingOccurrences(of: " ", with: "_"))
            }
        }
        return Array(Set(out)).sorted()
    }

    private func selectedPoint() -> UUID? {
        model.selection.first { id in
            guard let object = model.objectByID(id) else {
                return false
            }
            return model.evaluated(object.id).point != nil
        }
    }

    private func circleCenterName() -> String? {
        guard let id = selectedPoint(), let object = model.objectByID(id) else {
            return nil
        }
        return object.label.isEmpty ? "Point" : object.label
    }
}

#Preview("Workspace") {
    ContentView(model: SketchModel.sample(), presentsOnboarding: false)
        .frame(width: 1100, height: 760)
}
