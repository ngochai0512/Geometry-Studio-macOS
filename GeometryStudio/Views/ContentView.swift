import SwiftUI
import AppKit
import Combine

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
                .help("\(tool.title) (\(String(tool.shortcut.character)))")
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
