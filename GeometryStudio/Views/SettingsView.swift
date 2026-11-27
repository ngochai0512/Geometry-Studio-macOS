import AppKit
import Observation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    private enum Tab: Hashable {
        case general
        case appearance
        case units
        case canvas
    }

    @State private var settings = ActiveSketch.model?.settings ?? AppPreferences.canvasSettings()
    @State private var appearance = AppPreferences.appearance()
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
                appearanceTab
                    .tabItem {
                        Label("Appearance", systemImage: "paintpalette")
                    }
                    .tag(Tab.appearance)
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
        .frame(width: 540, height: 540)
        .onAppear {
            settings = ActiveSketch.model?.settings ?? AppPreferences.canvasSettings()
            appearance = AppPreferences.appearance()
            launchAtLogin.refresh()
        }
        .onChange(of: settings) { _, newValue in
            persist(newValue)
        }
        .onChange(of: appearance) { _, newValue in
            AppPreferences.saveAppearance(newValue)
        }
        .onDisappear {
            AppPreferences.saveAppearance(appearance)
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

    private var appearanceTab: some View {
        Form {
            Section {
                ForEach(AppearanceFamily.allCases) { family in
                    LabeledContent(family.title) {
                        ColorPicker(family.title,
                                    selection: appearanceColorBinding(family))
                            .labelsHidden()
                            .accessibilityLabel(family.title)
                    }
                }
            } header: {
                Text("Default Object Colors")
            } footer: {
                Text("Applied to newly created objects. Existing objects keep their own colors.")
            }

            Section {
                Button("Restore Default Colors") {
                    appearance = AppearancePreferences()
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private func appearanceColorBinding(_ family: AppearanceFamily) -> Binding<Color> {
        Binding(
            get: { appearance.color(for: family).color },
            set: { newValue in
                let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .black
                var updated = appearance
                updated.setColor(RGBA(Double(ns.redComponent),
                                      Double(ns.greenComponent),
                                      Double(ns.blueComponent),
                                      Double(ns.alphaComponent)),
                                 for: family)
                appearance = updated
            }
        )
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
                Picker("Theme", selection: themeBinding) {
                    ForEach(CanvasTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                ColorPicker("Canvas background", selection: backgroundColorBinding)
            } header: {
                Text("Background")
            } footer: {
                Text("A dark background switches ink, labels, cards and halos to their light tokens automatically.")
            }

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

    /// The sketch footer only makes sense while editing canvas preferences;
    /// the Appearance pane has nothing to restore or create.
    private var showsSketchActions: Bool {
        switch tab {
        case .general, .units, .canvas:
            return true
        case .appearance:
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

    private var themeBinding: Binding<CanvasTheme> {
        Binding(
            get: { settings.theme },
            set: { theme in
                var updated = settings
                updated.theme = theme
                updated.backgroundColor = theme.background
                settings = updated
            }
        )
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
