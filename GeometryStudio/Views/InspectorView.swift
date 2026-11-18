import SwiftUI
import AppKit

/// The right-hand inspector. This file owns the panel frame and the tab switch;
/// the sections live in `InspectorSections.swift` and the model plumbing in
/// `InspectorBindings.swift`.
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Inspector")
                .font(.system(size: 15, weight: .semibold))
            Text("\(model.objects.filter(\.visible).count) visible objects")
                .font(.system(size: 10.5))
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
