import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.newDocument) private var newDocument
    @State private var settings = ActiveSketch.model?.settings ?? AppPreferences.canvasSettings()

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                unitsTab
                    .tabItem {
                        Label("Units", systemImage: "ruler")
                    }
                canvasTab
                    .tabItem {
                        Label("Canvas", systemImage: "squareshape.split.2x2")
                    }
            }

            Divider()

            HStack(spacing: 10) {
                Button("Restore Defaults") {
                    settings = CanvasSettings()
                    persist(settings)
                }
                Spacer()
                Button("Create New Sketch") {
                    persist(settings)
                    newDocument(contentType: .geometryStudioSketch)
                }
            }
            .padding(12)
        }
        .frame(width: 480, height: 500)
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

    private var unitsTab: some View {
        Form {
            Section {
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
            } header: {
                Text("Unit System")
            } footer: {
                Text("These settings apply to the active sketch and become the defaults for new sketches.")
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private var canvasTab: some View {
        Form {
            Section {
                Toggle("Show grid", isOn: $settings.grid)
                Picker("Grid style", selection: gridTypeBinding) {
                    ForEach(GridType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.menu)
                LabeledContent("Grid color") {
                    Picker("Grid color", selection: $settings.gridColor) {
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
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Toggle("Bold grid", isOn: $settings.gridBold)
            } header: {
                Text("Grid")
            }

            Section {
                Toggle("Show axes", isOn: $settings.axes)
                Toggle("Axes numbers", isOn: $settings.axesLabels)
                LabeledContent("Label style") {
                    Picker("Label style", selection: $settings.axesLabelStyle) {
                        ForEach(AxisLabelStyle.presets, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Axes")
            }

            Section {
                ColorPicker("Canvas background", selection: backgroundColorBinding)
                Toggle("Snap points to grid", isOn: $settings.snap)
                Toggle("Show labels", isOn: $settings.showLabels)
            } header: {
                Text("Canvas")
            } footer: {
                Text("These settings apply to the active sketch and become the defaults for new sketches.")
            }
        }
        .formStyle(.grouped)
        .padding(12)
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

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { settings.backgroundColor.color },
            set: { newValue in
                let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .white
                settings.backgroundColor = RGBA(Double(ns.redComponent),
                                                Double(ns.greenComponent),
                                                Double(ns.blueComponent),
                                                Double(ns.alphaComponent))
            }
        )
    }
}

#Preview("Settings") {
    SettingsView()
}
