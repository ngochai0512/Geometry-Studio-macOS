import AppKit
import Observation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    private enum Tab: Hashable {
        case general
        case units
        case canvas
        case update
        case about
    }

    @State private var settings = ActiveSketch.model?.settings ?? AppPreferences.canvasSettings()
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                generalTab
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }
                    .tag(Tab.general)
                unitsTab
                    .tabItem {
                        Label("Units", systemImage: "ruler")
                    }
                    .tag(Tab.units)
                canvasTab
                    .tabItem {
                        Label("Canvas", systemImage: "squareshape.split.2x2")
                    }
                    .tag(Tab.canvas)
                updateTab
                    .tabItem {
                        Label("Update", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .tag(Tab.update)
                aboutTab
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
                    .tag(Tab.about)
            }

            if showsSketchActions {
                Divider()

                HStack(spacing: 10) {
                    Button("Restore Defaults") {
                        settings = CanvasSettings()
                        persist(settings)
                    }
                    Spacer()
                    Button("Create New Sketch") {
                        persist(settings)
                        NotificationCenter.default.post(name: .newSketchRequested, object: nil)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 480, height: 500)
        .onAppear {
            settings = ActiveSketch.model?.settings ?? AppPreferences.canvasSettings()
            launchAtLogin.refresh()
        }
        .onChange(of: settings) { _, newValue in
            persist(newValue)
        }
        .onDisappear {
            persist(settings)
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: launchAtLoginBinding)

                if launchAtLogin.needsApproval {
                    Text("Approve Geometry Studio in System Settings > General > Login Items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let message = launchAtLogin.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Startup")
            }

            Section {
                Toggle("GPU rendering", isOn: $settings.useMetalRenderer)
                    .disabled(!MetalCanvas.isSupported)
                    .help(MetalCanvas.isSupported
                          ? "Draw sketch geometry with Metal"
                          : "Metal is not available on this Mac")
            } header: {
                Text("Rendering")
            } footer: {
                Text("These settings apply to the active sketch and become the defaults for new sketches.")
            }
        }
        .formStyle(.grouped)
        .padding(12)
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
                Toggle("Smart guides", isOn: $settings.smartGuides)
                LabeledContent("Angle snap") {
                    Picker("Angle snap", selection: $settings.angleSnap) {
                        ForEach(CanvasSettings.angleSnapChoices, id: \.self) { angle in
                            Text(angleSnapTitle(angle)).tag(angle)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
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

    private var updateTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Updates")
                .font(.headline)
            Text("This build does not check for updates yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var aboutTab: some View {
        ScrollView {
            AboutContent()
                .padding(26)
                .frame(maxWidth: .infinity)
        }
    }

    /// The sketch footer only makes sense while editing canvas preferences;
    /// the Update and About panes have nothing to restore or create.
    private var showsSketchActions: Bool {
        switch tab {
        case .general, .units, .canvas:
            return true
        case .update, .about:
            return false
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
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

    private func angleSnapTitle(_ value: Double) -> String {
        value == 0 ? "Off" : "\(Int(value))°"
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

/// Mirrors the main app's login item. The system owns the state, so the
/// toggle re-reads it instead of storing a duplicate preference.
@Observable
private final class LaunchAtLogin {
    var isEnabled = false
    var needsApproval = false
    var errorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            needsApproval = false
        case .requiresApproval:
            isEnabled = false
            needsApproval = true
        default:
            isEnabled = false
            needsApproval = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        // Registering again while the system waits for approval would not
        // change the state; the notice below already says what to do.
        if enabled, SMAppService.mainApp.status == .requiresApproval {
            refresh()
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The toggle keeps the system's real state; the message explains
            // why it sprang back without exposing technical error text.
            errorMessage = enabled
                ? "Could not add Geometry Studio to your login items. Move the app to Applications and try again."
                : "Could not remove Geometry Studio from your login items."
        }
        refresh()
    }
}

#Preview("Settings") {
    SettingsView()
}
