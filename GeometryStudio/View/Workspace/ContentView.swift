import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @Bindable var model: SketchModel
    @Environment(\.controlActiveState) var controlActiveState
    @Environment(\.newDocument) var newDocument
    var presentsOnboarding: Bool = true

    @State var textAnchor: Vec2 = .zero
    @State var showTextSheet = false
    @State var textDraft = ""
    @State var showCircleRadius = false
    @State var showProtocol = false
    @State var showFunction = false
    @State var showCalculation = false
    @State var showWelcome = false
    @State var welcomeFirstRun = true
    @State var showPalette = false
    @State var showHistory = false
    @State var recentPalette: [String] = []
    @State var exportNotice: ExportNotice?
    @State var enteredFullScreen = false
    @State var showPresentationHint = false
    @State var circleRadius: Double = 2
    @State var functionText = "sin(x)"
    @State var calculationText = ""
    @State var scrollMonitor: Any?
    @State var keyMonitor: Any?
    struct ExportNotice: Equatable {
        var message: String
        var url: URL?
    }

    init(model: SketchModel, presentsOnboarding: Bool = true) {
        _model = Bindable(wrappedValue: model)
        self.presentsOnboarding = presentsOnboarding
    }

    var body: some View {
        dialogs(
            notifications(
                interactions(
                    overlays(
                        chrome(canvas)
                    )
                )
            )
        )
    }

    // The modifier chain is split into groups: one long expression exceeded
    // the compiler's type-check budget and failed the build.
    var canvas: some View {
        SketchCanvas(model: model) { point in
            textAnchor = point
            textDraft = ""
            showTextSheet = true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func chrome<V: View>(_ content: V) -> some View {
        content
            .inspector(isPresented: inspectorVisibleBinding) {
                InspectorView(model: model)
                    .inspectorColumnWidth(min: 280, ideal: 306, max: 380)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !model.presentationMode {
                    SketchStatusBar(model: model)
                }
            }
            .toolbar {
                toolbarContent
            }
            .toolbarVisibility(model.presentationMode ? .hidden : .visible,
                               for: .windowToolbar)
    }

    func overlays<V: View>(_ content: V) -> some View {
        content
            .overlay(alignment: .top) {
                if showPalette {
                    paletteOverlay
                }
            }
            .overlay(alignment: .bottom) {
                exportToast
            }
            .overlay(alignment: .bottom) {
                if model.presentationMode, showPresentationHint {
                    Text("Esc to exit   ← → switch sketches")
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 28)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: exportNotice)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    func interactions<V: View>(_ content: V) -> some View {
        content
            .onChange(of: model.tool) { _, _ in
                model.draft = []
            }
            .onChange(of: model.presentationMode) { _, presenting in
                applyPresentationChange(presenting)
            }
            .onChange(of: controlActiveState) { _, state in
                if state != .inactive {
                    ActiveSketch.model = model
                } else {
                    model.spacePanning = false
                }
            }
            .onAppear(perform: installScrollMonitor)
            .onAppear(perform: installKeyMonitor)
            .onChange(of: showPalette) { _, open in
                applyPaletteChange(open)
            }
            .onAppear {
                ActiveSketch.model = model
            }
            .onDisappear {
                removeEventMonitors()
                if ActiveSketch.model === model {
                    ActiveSketch.model = nil
                }
            }
            .onExitCommand {
                if model.presentationMode {
                    model.presentationMode = false
                } else if model.draft.isEmpty {
                    model.tool = .select
                } else {
                    model.cancelDraft()
                }
            }
            .onAppear {
                if presentsOnboarding, !AppPreferences.hasCompletedOnboarding() {
                    welcomeFirstRun = true
                    showWelcome = true
                }
            }
    }

    func notifications<V: View>(_ content: V) -> some View {
        content
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
    }

    func dialogs<V: View>(_ content: V) -> some View {
        content
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

    func applyPresentationChange(_ presenting: Bool) {
        showPalette = false
        guard let window = NSApp.keyWindow else {
            return
        }
        let fullScreen = window.styleMask.contains(.fullScreen)
        if presenting {
            showPresentationHint = true
            if !fullScreen {
                enteredFullScreen = true
                window.toggleFullScreen(nil)
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                if model.presentationMode {
                    showPresentationHint = false
                }
            }
        } else if enteredFullScreen {
            enteredFullScreen = false
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }

    func applyPaletteChange(_ open: Bool) {
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

    func removeEventMonitors() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
        scrollMonitor = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
    }

    // MARK: toolbar









    // MARK: scroll monitor



    var inspectorVisibleBinding: Binding<Bool> {
        Binding(
            get: { model.presentationMode ? false : model.inspectorVisible },
            set: { model.inspectorVisible = $0 }
        )
    }


    // MARK: palette and templates

    func openTemplate(_ template: SketchTemplate) {
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


    // MARK: selection helpers

    func measurementNames() -> [String] {
        var out: [String] = []
        for object in model.objects {
            if case .measurement = object.kind, !object.label.isEmpty {
                out.append(object.label.replacingOccurrences(of: " ", with: "_"))
            }
        }
        return Array(Set(out)).sorted()
    }

    func selectedPoint() -> UUID? {
        model.selection.first { id in
            guard let object = model.objectByID(id) else {
                return false
            }
            return model.evaluated(object.id).point != nil
        }
    }

    func circleCenterName() -> String? {
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
