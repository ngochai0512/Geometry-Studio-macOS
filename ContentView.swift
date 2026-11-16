import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var model: SketchModel
    var screenshotMode: Bool = false

    @State private var textAnchor: Vec2 = .zero
    @State private var showTextSheet = false
    @State private var textDraft = ""
    @State private var showRotate = false
    @State private var showDilate = false
    @State private var showTranslate = false
    @State private var showFunction = false
    @State private var showCalculation = false
    @State private var rotateAngle: Double = 90
    @State private var dilateFactor: Double = 2
    @State private var translateX: Double = 1
    @State private var translateY: Double = 0
    @State private var functionText = "sin(x)"
    @State private var calculationText = ""
    @State private var scrollMonitor: Any?
    @State private var selectedTab: InspectorTab = .object

    enum InspectorTab: String, CaseIterable, Identifiable {
        case object = "Object"
        case sketch = "Sketch"
        var id: String { rawValue }
    }

    init(model: SketchModel, screenshotMode: Bool = false) {
        self.model = model
        self.screenshotMode = screenshotMode
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                SketchCanvas(model: model) { point in
                    textAnchor = point
                    textDraft = ""
                    showTextSheet = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.inspectorVisible {
                    Divider().opacity(0.5)
                    InspectorView(model: model,
                                  tab: $selectedTab,
                                  onTextAnnotation: { point in
                                      textAnchor = point
                                      textDraft = ""
                                      showTextSheet = true
                                  })
                        .frame(width: 306)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.22), value: model.inspectorVisible)
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: installScrollMonitor)
        .onDisappear {
            if let monitor = scrollMonitor { NSEvent.removeMonitor(monitor) }
            scrollMonitor = nil
        }
        .onExitCommand { model.cancelDraft() }
        .onReceive(animationClock) { _ in
            if model.animationPointID != nil { model.advanceAnimation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRotate)) { _ in
            showRotate = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDilate)) { _ in
            showDilate = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTranslate)) { _ in
            showTranslate = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFunction)) { _ in
            showFunction = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCalculation)) { _ in
            calculationText = ""
            showCalculation = true
        }
        .sheet(isPresented: $showTextSheet) { textSheet }
        .sheet(isPresented: $showRotate) { rotateSheet }
        .sheet(isPresented: $showDilate) { dilateSheet }
        .sheet(isPresented: $showTranslate) { translateSheet }
        .sheet(isPresented: $showFunction) { functionSheet }
        .sheet(isPresented: $showCalculation) { calculationSheet }
        .sheet(isPresented: $model.showAbout) { AboutView() }
    }

    // MARK: top bar

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.51, blue: 0.96),
                                                      Color(red: 0.44, green: 0.31, blue: 0.90)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "compass.drawing")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)

                VStack(alignment: .leading, spacing: -1) {
                    Text(model.document.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("Dynamic Geometry")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 170, alignment: .leading)
            }
            .padding(.leading, screenshotMode ? 14 : 82)

            Spacer(minLength: 4)

            toolCapsule

            Spacer(minLength: 4)

            constructMenu
            measureMenu

            Divider().frame(height: 22).opacity(0.5)

            HStack(spacing: 2) {
                barButton("arrow.uturn.backward", help: "Undo") { model.undo() }
                    .disabled(!model.canUndo)
                barButton("arrow.uturn.forward", help: "Redo") { model.redo() }
                    .disabled(!model.canRedo)
            }

            HStack(spacing: 2) {
                barButton("minus.magnifyingglass", help: "Zoom out") { model.zoom(by: 0.84) }
                Menu {
                    Button("50%") { model.setZoom(31) }
                    Button("75%") { model.setZoom(46.5) }
                    Button("100%") { model.setZoom(SketchMetrics.pixelsPerCentimetre) }
                    Button("150%") { model.setZoom(93) }
                    Button("200%") { model.setZoom(124) }
                    Divider()
                    Button("Fit Sketch") { model.fitCanvas(size: lastCanvasSize) }
                    Button("Actual Size") { model.setZoom(SketchMetrics.pixelsPerCentimetre) }
                } label: {
                    Text("\(Int(model.settings.scale / SketchMetrics.pixelsPerCentimetre * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(width: 42)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                barButton("plus.magnifyingglass", help: "Zoom in") { model.zoom(by: 1.19) }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))

            barButton(model.settings.grid ? "grid" : "grid.circle", help: "Show or hide the grid") {
                model.settings.grid.toggle()
            }
            barButton("sidebar.right", help: "Inspector") {
                model.inspectorVisible.toggle()
            }
            .background(model.inspectorVisible ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(.regularMaterial)
    }

    @State private var lastCanvasSize = CGSize(width: 900, height: 720)
    private let animationClock = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var toolCapsule: some View {
        HStack(spacing: 1) {
            ForEach(SketchTool.allCases) { tool in
                Button {
                    model.tool = tool
                    model.draft = []
                    model.statusMessage = tool.hint
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 13.5, weight: .medium))
                        .frame(width: 29, height: 27)
                        .foregroundStyle(model.tool == tool ? Color.white : Color.primary.opacity(0.78))
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.tool == tool ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(tool.title) (\(tool.shortcut.character))")
            }
        }
        .padding(3)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
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
            Button("Polygon Interior") { model.constructPolygon() }
            Button("Point on Object") { model.constructPointOnPath() }
            Divider()
            Button("Locus") { model.constructLocus() }
        } label: {
            Label("Construct", systemImage: "plus.square.on.square")
                .font(.system(size: 11.5, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Construct objects from the selection")
    }

    private var measureMenu: some View {
        Menu {
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
                calculationText = ""
                showCalculation = true
            }
            Button("Plot Function…") {
                showFunction = true
            }
        } label: {
            Label("Measure", systemImage: "ruler")
                .font(.system(size: 11.5, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Measure the selection")
    }

    private func barButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 27, height: 25)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(0.8))
        .help(help)
    }

    // MARK: status bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let hover = model.hoverWorld {
                Text("x \(fmt(hover.x / model.settings.lengthUnit.perUnit))   y \(fmt(hover.y / model.settings.lengthUnit.perUnit)) \(model.settings.lengthUnit.short)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text(model.tool.hint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !model.draft.isEmpty {
                Divider().frame(height: 14)
                Text("\(model.draft.count) picked")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                if model.tool == .polygon && model.draft.count >= 3 {
                    Button("Close Polygon") { model.finishPolygon() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5, weight: .semibold))
                }
                Button("Cancel") { model.cancelDraft() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5))
            }

            Spacer(minLength: 6)

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider().frame(height: 14)

            Text("\(model.objects.filter(\.visible).count) objects")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if !model.selection.isEmpty {
                Text("\(model.selection.count) selected")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    // MARK: scroll monitor

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard model.isPointerOverCanvas else { return event }
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

    // MARK: sheets

    private var textSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Add Text", systemImage: "textformat")
                .font(.headline)
            Text("Captions are objects on the canvas. They can be selected, moved and styled just like geometry.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $textDraft)
                .font(.system(size: 13))
                .frame(height: 88)
                .padding(6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
            HStack {
                Spacer()
                Button("Cancel") { showTextSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let t = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        model.checkpoint()
                        let id = model.add(kind: .caption(t), position: textAnchor, silent: true)
                        model.selection = [id]
                        model.isDirty = true
                    }
                    showTextSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private var rotateSheet: some View {
        let center = selectedPoint() ?? firstPoint()
        return VStack(alignment: .leading, spacing: 14) {
            Label("Rotate", systemImage: "rotate.right")
                .font(.headline)
            Text("Rotate the selected objects around a point.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let center, let object = model.objectByID(center) {
                HStack {
                    Text("Center")
                    Spacer()
                    Text(object.label.isEmpty ? "Point" : object.label)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select a center point as well as the objects to rotate.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Text("Angle")
                TextField("Angle", value: $rotateAngle, format: .number)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                Text("degrees").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { showRotate = false }.keyboardShortcut(.cancelAction)
                Button("Rotate") {
                    if let center { model.rotateSelection(center: center, degrees: rotateAngle) }
                    showRotate = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(center == nil)
            }
        }
        .padding(22)
        .frame(width: 400)
    }

    private var dilateSheet: some View {
        let center = selectedPoint() ?? firstPoint()
        return VStack(alignment: .leading, spacing: 14) {
            Label("Dilate", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.headline)
            Text("Scale the selected objects about a center point.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let center, let object = model.objectByID(center) {
                HStack { Text("Center"); Spacer(); Text(object.label).foregroundStyle(.secondary) }
            } else {
                Text("Select a center point as well as the objects to dilate.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Text("Scale factor")
                TextField("Factor", value: $dilateFactor, format: .number)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Spacer()
                Button("Cancel") { showDilate = false }.keyboardShortcut(.cancelAction)
                Button("Dilate") {
                    if let center { model.dilateSelection(center: center, factor: dilateFactor) }
                    showDilate = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(center == nil)
            }
        }
        .padding(22)
        .frame(width: 400)
    }

    private var translateSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Translate", systemImage: "arrow.right")
                .font(.headline)
            Text("Move a copy of the selected objects by a fixed amount.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Text("Horizontal")
                TextField("dx", value: $translateX, format: .number)
                    .frame(width: 80).multilineTextAlignment(.trailing)
                Text(model.settings.lengthUnit.short).foregroundStyle(.secondary)
            }
            HStack {
                Text("Vertical")
                TextField("dy", value: $translateY, format: .number)
                    .frame(width: 80).multilineTextAlignment(.trailing)
                Text(model.settings.lengthUnit.short).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { showTranslate = false }.keyboardShortcut(.cancelAction)
                Button("Translate") {
                    model.translateSelection(dx: translateX, dy: translateY)
                    showTranslate = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
    }

    private var functionSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Plot a Function", systemImage: "function")
                .font(.headline)
            Text("Type an expression in x. Examples: sin(x), x^2 - 2, 3cos(2x) + 1.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("f(x) =", text: $functionText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, design: .monospaced))
            HStack {
                Spacer()
                Button("Cancel") { showFunction = false }.keyboardShortcut(.cancelAction)
                Button("Plot") {
                    model.addFunctionPlot(expression: functionText)
                    showFunction = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Expression(functionText) == nil)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private var calculationSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Calculate", systemImage: "function")
                .font(.headline)
            Text("Use measurement names (spaces become underscores), numbers, + − × ÷, ^ and functions such as sqrt, sin and cos.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("expression", text: $calculationText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, design: .monospaced))
            let names = measurementNames()
            if !names.isEmpty {
                Text("Measurements").font(.caption).foregroundStyle(.secondary)
                FlowChips(items: names) { name in
                    if !calculationText.isEmpty && !calculationText.hasSuffix(" ") && !calculationText.hasSuffix("(") {
                        calculationText += " "
                    }
                    calculationText += name
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { showCalculation = false }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    model.addCalculation(expression: calculationText)
                    showCalculation = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(calculationText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

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
            guard let object = model.objectByID(id) else { return false }
            return model.evaluated(object.id).point != nil
        }
    }

    private func firstPoint() -> UUID? {
        model.objects.first { object in
            guard object.visible else { return false }
            return model.evaluated(object.id).point != nil
        }?.id
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @ObservedObject var model: SketchModel
    @Binding var tab: ContentView.InspectorTab
    var onTextAnnotation: (Vec2) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Picker("", selection: $tab) {
                    ForEach(ContentView.InspectorTab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if tab == .object {
                    objectSection
                    actionsSection
                    stylingSection
                } else {
                    sketchSection
                    canvasSection
                    constructSection
                }
            }
            .padding(16)
        }
        .background(.thinMaterial)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Inspector")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(model.objects.filter(\.visible).count) visible objects")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.inspectorVisible = false
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide the inspector")
        }
    }

    @ViewBuilder
    private var objectSection: some View {
        if model.selection.count == 1, let id = model.selection.first, let object = model.objectByID(id) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Selection")
                HStack(spacing: 9) {
                    Image(systemName: model.symbol(for: object))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.displayName(for: object))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(typeDescription(object))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if needsLabel(object) {
                    HStack {
                        Text("Label").font(.system(size: 11.5))
                        Spacer()
                        TextField("Label", text: labelBinding(id))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                            .font(.system(size: 11.5))
                    }
                }

                if case .caption = object.kind {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Text").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        TextField("Text", text: captionBinding(id), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...5)
                            .font(.system(size: 11.5))
                    }
                }

                let measurement = model.evaluated(id).text
                if let measurement, !measurement.isEmpty, isMeasurement(object) {
                    Text(measurement)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                        .textSelection(.enabled)
                }

                Toggle("Show label", isOn: showLabelBinding(id))
                    .font(.system(size: 11.5))
                Toggle("Visible", isOn: visibleBinding(id))
                    .font(.system(size: 11.5))
            }
        } else if model.selection.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Selection")
                Text("\(model.selection.count) objects selected")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Change their colour, line style or visibility together, or use Construct to build from them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Selection")
                Text("Nothing selected")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Pick an object on the canvas, or choose Sketch to browse every object.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if !model.selection.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                sectionTitle("Actions")
                HStack(spacing: 7) {
                    actionButton("eye.slash", "Hide") { model.hideSelection() }
                    actionButton("textformat.abc", "Labels") { model.toggleLabels(for: model.selection) }
                    actionButton("trash", "Delete", role: .destructive) { model.deleteSelection() }
                }
                Menu {
                    Button("Reflect Across Selected Line") { model.reflectSelection() }
                    Button("Rotate…") { model.showAbout = false; NotificationCenter.default.post(name: .openRotate, object: nil) }
                    Button("Dilate…") { NotificationCenter.default.post(name: .openDilate, object: nil) }
                    Button("Translate…") { NotificationCenter.default.post(name: .openTranslate, object: nil) }
                } label: {
                    Label("Transform Selection", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)

                HStack(spacing: 7) {
                    actionButton(model.animationPointID == nil ? "play" : "pause",
                                 model.animationPointID == nil ? "Animate" : "Pause") {
                        model.toggleAnimation()
                    }
                    actionButton("point.topleft.down.to.point.bottomright.curvepath",
                                 traceLabel) { model.toggleTrace() }
                }
            }
        }
    }

    private var traceLabel: String {
        !model.selection.isEmpty && model.selection.allSatisfy { model.tracedIDs.contains($0) }
            ? "Untrace" : "Trace"
    }

    @ViewBuilder
    private var stylingSection: some View {
        if !model.selection.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Style")
                colorRow
                HStack {
                    Text("Line").font(.system(size: 11.5)).frame(width: 40, alignment: .leading)
                    Picker("", selection: lineWidthBinding) {
                        Text("Hairline").tag(0.8)
                        Text("Thin").tag(1.2)
                        Text("Regular").tag(1.5)
                        Text("Bold").tag(2.2)
                        Text("Heavy").tag(3.2)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                HStack {
                    Text("Dash").font(.system(size: 11.5)).frame(width: 40, alignment: .leading)
                    Picker("", selection: dashBinding) {
                        ForEach(DashStyle.allCases) { style in
                            Text(style.name).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                HStack {
                    Text("Point").font(.system(size: 11.5)).frame(width: 40, alignment: .leading)
                    Picker("", selection: pointShapeBinding) {
                        ForEach(PointShape.allCases) { shape in
                            Text(shape.name).tag(shape)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                HStack {
                    Text("Size").font(.system(size: 11.5)).frame(width: 40, alignment: .leading)
                    Picker("", selection: pointSizeBinding) {
                        Text("Dot").tag(3.0)
                        Text("Small").tag(4.5)
                        Text("Medium").tag(6.0)
                        Text("Large").tag(8.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                if anySelectedIsRegion {
                    HStack {
                        Text("Fill").font(.system(size: 11.5))
                        Slider(value: fillBinding, in: 0...0.4)
                    }
                }
            }
        }
    }

    private var colorRow: some View {
        HStack(spacing: 6) {
            ForEach(RGBA.palette, id: \.0) { name, color in
                Button {
                    applyToSelection { object in
                        object.style.color = color
                    }
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                                .padding(-1)
                        )
                }
                .buttonStyle(.plain)
                .help(name)
            }
            Spacer()
            ColorPicker("", selection: colorBinding)
                .labelsHidden()
                .frame(width: 26)
        }
    }

    private var sketchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Objects")
            let groups: [(String, [SketchObject])] = [
                ("Points", model.objects.filter { $0.isPointLike }),
                ("Lines", model.objects.filter { isLineObject($0) }),
                ("Circles & Regions", model.objects.filter { isRegionObject($0) }),
                ("Measures & Text", model.objects.filter { isMeasureObject($0) })
            ]
            ForEach(groups, id: \.0) { title, objects in
                if !objects.isEmpty {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 4)
                    ForEach(objects.sorted(by: { $0.order < $1.order })) { object in
                        objectRow(object)
                    }
                }
            }
        }
    }

    private func objectRow(_ object: SketchObject) -> some View {
        Button {
            model.selection = [object.id]
            tab = .object
        } label: {
            HStack(spacing: 7) {
                Image(systemName: model.symbol(for: object))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(model.selection.contains(object.id) ? Color.accentColor : Color.secondary)
                    .frame(width: 15)
                Text(model.displayName(for: object))
                    .font(.system(size: 11.5))
                    .foregroundStyle(object.visible ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer()
                if !object.visible {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(model.selection.contains(object.id) ? Color.accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Canvas")
            Toggle("Grid", isOn: $model.settings.grid)
                .font(.system(size: 11.5))
            Toggle("Axes", isOn: $model.settings.axes)
                .font(.system(size: 11.5))
            Toggle("Snap points to grid", isOn: $model.settings.snap)
                .font(.system(size: 11.5))
            Toggle("Show labels", isOn: $model.settings.showLabels)
                .font(.system(size: 11.5))
            HStack {
                Text("Length").font(.system(size: 11.5)).frame(width: 54, alignment: .leading)
                Picker("", selection: $model.settings.lengthUnit) {
                    ForEach(LengthUnit.allCases) { unit in
                        Text(unit.name).tag(unit)
                    }
                }
                .labelsHidden().pickerStyle(.menu)
            }
            HStack {
                Text("Angle").font(.system(size: 11.5)).frame(width: 54, alignment: .leading)
                Picker("", selection: $model.settings.angleUnit) {
                    ForEach(AngleUnit.allCases) { unit in
                        Text(unit.name).tag(unit)
                    }
                }
                .labelsHidden().pickerStyle(.menu)
            }
            HStack {
                Text("Decimals").font(.system(size: 11.5)).frame(width: 54, alignment: .leading)
                Picker("", selection: $model.settings.precision) {
                    ForEach(0...5, id: \.self) { p in
                        Text("\(p)").tag(p)
                    }
                }
                .labelsHidden().pickerStyle(.segmented)
            }
            HStack(spacing: 7) {
                Button("Fit") { model.fitCanvas(size: CGSize(width: 900, height: 700)) }
                Button("100%") { model.setZoom(SketchMetrics.pixelsPerCentimetre) }
                Button("Reset") {
                    model.settings.center = .zero
                    model.setZoom(SketchMetrics.pixelsPerCentimetre)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var constructSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("Construct")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                smallAction("Midpoint", "circle.dotted") { model.constructMidpoint() }
                smallAction("Intersection", "circle.circle") { model.constructIntersection() }
                smallAction("Perpendicular", "arrow.up.and.line.horizontal.and.arrow.down") { model.constructPerpendicular() }
                smallAction("Parallel", "equal") { model.constructParallel() }
                smallAction("Bisector", "angle") { model.constructBisector() }
                smallAction("Circle", "circle") { model.constructCircle() }
                smallAction("Polygon", "pentagon") { model.constructPolygon() }
                smallAction("Point on Object", "smallcircle.filled.circle") { model.constructPointOnPath() }
            }
            Button {
                onTextAnnotation(model.settings.center)
            } label: {
                Label("Add a caption", systemImage: "textformat")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
    }

    private func smallAction(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9.5))
                Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func actionButton(_ symbol: String, _ title: String, role: ButtonRole? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(title).font(.system(size: 9.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: object helpers / bindings

    private func needsLabel(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection, .caption, .angle: return true
        default: return false
        }
    }

    private func isMeasurement(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .angle: return true
        default: return false
        }
    }

    private func isLineObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector: return true
        default: return false
        }
    }

    private func isRegionObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .circle, .polygon: return true
        default: return false
        }
    }

    private func isMeasureObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .caption, .angle, .functionPlot: return true
        default: return false
        }
    }

    private func typeDescription(_ object: SketchObject) -> String {
        switch object.kind {
        case .freePoint: return "Free point"
        case .pointOnPath: return "Point on an object"
        case .midpoint: return "Constructed midpoint"
        case .intersection: return "Constructed intersection"
        case .segment: return "Segment"
        case .ray: return "Ray"
        case .line: return "Line"
        case .perpendicular: return "Perpendicular line"
        case .parallel: return "Parallel line"
        case .angleBisector: return "Angle bisector"
        case .circle: return "Circle"
        case .polygon: return "Polygon interior"
        case .angle: return "Angle marker"
        case .measurement(let kind, _): return "\(kind.title) measurement"
        case .calculation: return "Calculation"
        case .caption: return "Caption"
        case .functionPlot: return "Function plot"
        case .transformed(let _, let spec): return "\(spec.kind.title) image"
        case .locus: return "Locus"
        }
    }

    private func labelBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { model.objectByID(id)?.label ?? "" },
            set: { value in
                guard let i = model.index(of: id) else { return }
                model.checkpoint()
                model.objects[i].label = value
                model.isDirty = true
            }
        )
    }

    private func captionBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                if let object = model.objectByID(id), case .caption(let text) = object.kind { return text }
                return ""
            },
            set: { value in
                guard let i = model.index(of: id) else { return }
                if case .caption = model.objects[i].kind {
                    model.objects[i].kind = .caption(value)
                    model.isDirty = true
                }
            }
        )
    }

    private func showLabelBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.objectByID(id)?.showLabel ?? true },
            set: { value in
                guard let i = model.index(of: id) else { return }
                model.checkpoint()
                model.objects[i].showLabel = value
                model.isDirty = true
            }
        )
    }

    private func visibleBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.objectByID(id)?.visible ?? true },
            set: { value in
                guard let i = model.index(of: id) else { return }
                model.checkpoint()
                model.objects[i].visible = value
                model.isDirty = true
            }
        )
    }

    private var lineWidthBinding: Binding<Double> {
        Binding(
            get: { model.selectedObjects.first?.style.lineWidth ?? 1.5 },
            set: { value in applyToSelection { $0.style.lineWidth = value } }
        )
    }

    private var dashBinding: Binding<DashStyle> {
        Binding(
            get: { model.selectedObjects.first?.style.dash ?? .solid },
            set: { value in applyToSelection { $0.style.dash = value } }
        )
    }

    private var pointShapeBinding: Binding<PointShape> {
        Binding(
            get: { model.selectedObjects.first?.style.pointShape ?? .filled },
            set: { value in applyToSelection { $0.style.pointShape = value } }
        )
    }

    private var pointSizeBinding: Binding<Double> {
        Binding(
            get: { model.selectedObjects.first?.style.pointSize ?? 5.5 },
            set: { value in applyToSelection { $0.style.pointSize = value } }
        )
    }

    private var fillBinding: Binding<Double> {
        Binding(
            get: { model.selectedObjects.first?.style.fillOpacity ?? 0.1 },
            set: { value in applyToSelection { $0.style.fillOpacity = value } }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                let c = model.selectedObjects.first?.style.color ?? .ink
                return Color(red: c.r, green: c.g, blue: c.b)
            },
            set: { newValue in
                let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .black
                let c = RGBA(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
                applyToSelection { $0.style.color = c }
            }
        )
    }

    private var anySelectedIsRegion: Bool {
        model.selectedObjects.contains { isRegionObject($0) }
    }

    private func applyToSelection(_ change: (inout SketchObject) -> Void) {
        guard !model.selection.isEmpty else { return }
        model.checkpoint()
        for id in model.selection {
            if let i = model.index(of: id) {
                change(&model.objects[i])
            }
        }
        model.isDirty = true
    }
}

// MARK: - Small helpers

struct FlowChips: View {
    var items: [String]
    var action: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 5)], alignment: .leading, spacing: 5) {
            ForEach(items, id: \.self) { item in
                Button(item) { action(item) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .lineLimit(1)
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.51, blue: 0.96),
                                                  Color(red: 0.44, green: 0.31, blue: 0.90)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "compass.drawing")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 84, height: 84)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)

            Text("Geometry Studio")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("A dynamic geometry sketchpad for macOS")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 30)

            VStack(alignment: .leading, spacing: 7) {
                Label("Native Swift and SwiftUI", systemImage: "swift")
                Label("Built for Apple silicon", systemImage: "cpu")
                Label("Drag a free point and every construction follows", systemImage: "hand.draw")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)

            Text("The original is a 32-bit the legacy framework application whose geometry engine is written in C: its objects are plain C structs. This rebuild is a new Swift implementation, not a copy of its code.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 26)

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(26)
        .frame(width: 380)
    }
}

extension Notification.Name {
    static let openRotate = Notification.Name("openRotate")
    static let openDilate = Notification.Name("openDilate")
    static let openTranslate = Notification.Name("openTranslate")
}
