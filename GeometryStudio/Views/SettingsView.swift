import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.newDocument) private var newDocument
    @State private var settings = ActiveSketch.model?.settings ?? AppPreferences.canvasSettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Units") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Length unit", selection: $settings.lengthUnit) {
                            ForEach(LengthUnit.allCases) { unit in
                                Text(unit.name).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Angle unit", selection: $settings.angleUnit) {
                            ForEach(AngleUnit.allCases) { unit in
                                Text(unit.name).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Decimal places", selection: $settings.precision) {
                            ForEach(0...5, id: \.self) { places in
                                Text("\(places)").tag(places)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(8)
                }

                GroupBox("Canvas") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show grid", isOn: $settings.grid)

                        Picker("Grid style", selection: gridTypeBinding) {
                            ForEach(GridType.allCases) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .pickerStyle(.menu)

                        Toggle("Show axes", isOn: $settings.axes)
                        Toggle("Snap points to grid", isOn: $settings.snap)
                        Toggle("Show labels", isOn: $settings.showLabels)
                    }
                    .padding(8)
                }

                Text("These settings apply to the active sketch and become the defaults for new sketches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Restore Defaults") {
                        settings = CanvasSettings()
                        persist(settings)
                    }
                    Button("Create New Sketch") {
                        persist(settings)
                        newDocument(contentType: .geometryStudioSketch)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 520)
        .onAppear {
            settings = ActiveSketch.model?.settings ?? AppPreferences.canvasSettings()
        }
        .onChange(of: settings) { _, newValue in
            persist(newValue)
        }
        .onDisappear {
            persist(settings)
        }
    }

    /// Choosing a style while the grid is hidden would look like a no-op, so
    /// selecting one also makes the grid visible.
    private var gridTypeBinding: Binding<GridType> {
        Binding(
            get: { settings.gridType },
            set: { newValue in
                var updated = settings
                updated.gridType = newValue
                updated.grid = true
                settings = updated
                persist(updated)
            }
        )
    }

    private func persist(_ value: CanvasSettings) {
        AppPreferences.save(value)
        ActiveSketch.model?.applyCanvasDefaults(value)
    }
}

#Preview("Settings") {
    SettingsView()
}
