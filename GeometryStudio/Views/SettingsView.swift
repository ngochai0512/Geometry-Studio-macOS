import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferences.Keys.lengthUnit) private var lengthUnit: LengthUnit = .inches
    @AppStorage(AppPreferences.Keys.angleUnit) private var angleUnit: AngleUnit = .degrees
    @AppStorage(AppPreferences.Keys.precision) private var precision: Int = 2
    @AppStorage(AppPreferences.Keys.grid) private var grid = true
    @AppStorage(AppPreferences.Keys.gridType) private var gridType: GridType = .orthogonal
    @AppStorage(AppPreferences.Keys.axes) private var axes = true
    @AppStorage(AppPreferences.Keys.snap) private var snap = false
    @AppStorage(AppPreferences.Keys.showLabels) private var showLabels = true

    var body: some View {
        TabView {
            Tab("Units", systemImage: "ruler") {
                unitsTab
            }
            Tab("New Sketches", systemImage: "doc.badge.plus") {
                newSketchTab
            }
        }
        .frame(width: 460, height: 360)
    }

    private var unitsTab: some View {
        Form {
            Picker("Length unit", selection: $lengthUnit) {
                ForEach(LengthUnit.allCases) { unit in
                    Text(unit.name).tag(unit)
                }
            }
            Picker("Angle unit", selection: $angleUnit) {
                ForEach(AngleUnit.allCases) { unit in
                    Text(unit.name).tag(unit)
                }
            }
            Picker("Decimal places", selection: $precision) {
                ForEach(0...5, id: \.self) { places in
                    Text("\(places)").tag(places)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
    }

    private var newSketchTab: some View {
        Form {
            Section {
                Toggle("Show grid", isOn: $grid)
                Picker("Grid style", selection: $gridType) {
                    ForEach(GridType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                Toggle("Show axes", isOn: $axes)
                Toggle("Snap points to grid", isOn: $snap)
                Toggle("Show labels", isOn: $showLabels)
            } header: {
                Text("Canvas")
            }

            Section {
                Text("These defaults apply when you create a new sketch. An open sketch keeps its own units, precision and canvas settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Restore Defaults") {
                    restoreDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
    }

    private func restoreDefaults() {
        lengthUnit = .inches
        angleUnit = .degrees
        precision = 2
        grid = true
        gridType = .orthogonal
        axes = true
        snap = false
        showLabels = true
    }
}

#Preview("Settings") {
    SettingsView()
}
