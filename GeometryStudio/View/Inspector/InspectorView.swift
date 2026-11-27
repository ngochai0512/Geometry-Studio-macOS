import SwiftUI
import AppKit

/// The right-hand inspector: one persistent panel with the selected object's
/// details above the layer list. Canvas settings live in Settings and the grid
/// menu; marks live next to the transform actions.
struct InspectorView: View {
    @Bindable var model: SketchModel
    @State var browserQuery = ""
    @State var browserFilter: ObjectBrowserFilter = .all
    @State private var collapsedGroups: Set<String> = []

    init(model: SketchModel) {
        _model = Bindable(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)

            Divider()

            List(selection: objectSelection) {
                objectSection
                numericSection
                actionsSection
                animationSection
                stylingSection
                layersSection
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Inspector")
                .font(.title3.weight(.semibold))
            Text("\(model.objects.filter(\.visible).count) objects")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func expandedGroup(_ title: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(title) },
            set: { isExpanded in
                if isExpanded {
                    collapsedGroups.remove(title)
                } else {
                    collapsedGroups.insert(title)
                }
            }
        )
    }
}

#Preview("Inspector") {
    InspectorView(model: SketchModel.sample())
        .frame(width: 320, height: 720)
}
