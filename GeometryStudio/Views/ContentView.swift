import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @Bindable var model: SketchModel
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var textAnchor: Vec2 = .zero
    @State private var showTextSheet = false
    @State private var textDraft = ""
    @State private var showCircleRadius = false
    @State private var showProtocol = false
    @State private var showFunction = false
    @State private var showCalculation = false
    @State private var circleRadius: Double = 2
    @State private var functionText = "sin(x)"
    @State private var calculationText = ""
    @State private var scrollMonitor: Any?
    @State private var selectedTab: InspectorTab = .object

    enum InspectorTab: String, CaseIterable, Identifiable {
        case object = "Object"
        case sketch = "Sketch"
        var id: String {
            rawValue
        }
    }

    init(model: SketchModel) {
        _model = Bindable(wrappedValue: model)
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
                          tab: $selectedTab,
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
        .navigationSubtitle("Dynamic Geometry")
        .toolbar {
            toolbarContent
        }
        .onChange(of: model.tool) { _, newValue in
            model.draft = []
            model.statusMessage = newValue.hint
        }
        .onChange(of: controlActiveState) { _, state in
            if state != .inactive {
                ActiveSketch.model = model
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: installScrollMonitor)
        .onAppear {
            ActiveSketch.model = model
        }
        .onDisappear {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
            }
            scrollMonitor = nil
            if ActiveSketch.model === model {
                ActiveSketch.model = nil
            }
        }
        .onExitCommand { model.cancelDraft() }
        .onReceive(NotificationCenter.default.publisher(for: .openCircleRadius)) { _ in
            showCircleRadius = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProtocol)) { _ in
            showProtocol = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFunction)) { _ in
            showFunction = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCalculation)) { _ in
            calculationText = ""
            showCalculation = true
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

            Toggle(isOn: $model.settings.grid) {
                Label("Grid", systemImage: "squareshape.split.2x2")
            }
            .toggleStyle(.button)
            .help("Show or hide the grid")

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
            Button("Plot Derivative") { model.addDerivativePlot() }
            Button("Shade Integral") { model.addIntegralPlot() }
            Button("Tangent at x") { model.addTangentAt() }
            Button("Value Table") { model.addValueTable() }
            Button("Find Roots") { model.findFunctionRoots() }
            Button("Find Intersections") { model.findFunctionIntersections() }
            Divider()
            Button("Calculate…") {
                calculationText = ""
                showCalculation = true
            }
            Button("Plot Function…") {
                showFunction = true
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
    ContentView(model: SketchModel.sample())
        .frame(width: 1100, height: 760)
}
