import SwiftUI
import AppKit

/// The right-hand inspector. This file owns the panel frame and the tab switch;
/// the sections live in `InspectorSections.swift` and the model plumbing in
/// `InspectorBindings.swift`.
struct InspectorView: View {
    @Bindable var model: SketchModel
    @Binding var tab: ContentView.InspectorTab
    var onTextAnnotation: (Vec2) -> Void

    init(model: SketchModel,
         tab: Binding<ContentView.InspectorTab>,
         onTextAnnotation: @escaping (Vec2) -> Void) {
        _model = Bindable(wrappedValue: model)
        _tab = tab
        self.onTextAnnotation = onTextAnnotation
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
                Picker("Inspector Section", selection: $tab) {
                    ForEach(ContentView.InspectorTab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(16)

            switch tab {
            case .object:
                List {
                    objectSection
                    actionsSection
                    stylingSection
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            case .sketch:
                List(selection: objectSelection) {
                    sketchSection
                    canvasSection
                    constructSection
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Inspector")
                .font(.title3.weight(.semibold))
            Text("\(model.objects.filter(\.visible).count) visible objects")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Inspector") {
    InspectorView(model: SketchModel.sample(),
                  tab: .constant(.object),
                  onTextAnnotation: { _ in })
        .frame(width: 320, height: 720)
}
