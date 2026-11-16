import SwiftUI
import AppKit

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
        .background(.thinMaterial)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Inspector")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(model.objects.filter(\.visible).count) visible objects")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.inspectorVisible = false
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide the inspector")
        }
    }

    @ViewBuilder
    private var objectSection: some View {
        if model.selection.count == 1, let id = model.selection.first, let object = model.objectByID(id) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Selection")
                HStack(spacing: 9) {
                    Image(systemName: model.symbol(for: object))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.displayName(for: object))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(typeDescription(object))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if needsLabel(object) {
                    HStack {
                        Text("Label").font(.system(size: 11.5))
                        Spacer()
                        TextField("Label", text: labelBinding(id))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                            .font(.system(size: 11.5))
                    }
                }

                if case .caption = object.kind {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Text").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        TextField("Text", text: captionBinding(id), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...5)
                            .font(.system(size: 11.5))
                    }
                }

                let measurement = model.evaluated(id).text
                if let measurement, !measurement.isEmpty, isMeasurement(object) {
                    Text(measurement)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                        .textSelection(.enabled)
                }

                Toggle("Show label", isOn: showLabelBinding(id))
                    .font(.system(size: 11.5))
                Toggle("Visible", isOn: visibleBinding(id))
                    .font(.system(size: 11.5))
            }
        } else if model.selection.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Selection")
                Text("\(model.selection.count) objects selected")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Change their colour, line style or visibility together, or use Construct to build from them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Selection")
                Text("Nothing selected")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Pick an object on the canvas, or choose Sketch to browse every object.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if !model.selection.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                sectionTitle("Actions")
                HStack(spacing: 7) {
                    actionButton("eye.slash", "Hide") { model.hideSelection() }
                    actionButton("textformat.abc", "Labels") { model.toggleLabels(for: model.selection) }
                    actionButton("trash", "Delete", role: .destructive) { model.deleteSelection() }
                }
                Menu {
                    Button("Reflect Across Selected Line") { model.reflectSelection() }
                    Button("Rotate…") { model.showAbout = false; NotificationCenter.default.post(name: .openRotate, object: nil) }
                    Button("Dilate…") { NotificationCenter.default.post(name: .openDilate, object: nil) }
                    Button("Translate…") { NotificationCenter.default.post(name: .openTranslate, object: nil) }
                } label: {
                    Label("Transform Selection", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)

                HStack(spacing: 7) {
                    actionButton(model.animationPointID == nil ? "play" : "pause",
                                 model.animationPointID == nil ? "Animate" : "Pause") {
                        model.toggleAnimation()
                    }
                    actionButton("point.topleft.down.to.point.bottomright.curvepath",
                                 traceLabel) { model.toggleTrace() }
                }
            }
        }
    }

    private var traceLabel: String {
        !model.selection.isEmpty && model.selection.allSatisfy { model.tracedIDs.contains($0) }
            ? "Untrace" : "Trace"
    }

    @ViewBuilder
    private var stylingSection: some View {
        if !model.selection.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Style")
                colorRow
                HStack {
                    Text("Line").font(.system(size: 11.5)).frame(width: 40, alignment: .leading)
                    Picker("", selection: lineWidthBinding) {
                        Text("Hairline").tag(0.8)
                        Text("Thin").tag(1.2)
                        Text("Regular").tag(1.5)
                        Text("Bold").tag(2.2)
                        Text("Heavy").tag(3.2)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                HStack {
                    Text("Dash").font(.system(size: 11.5)).frame(width: 40, alignment: .leading)
                    Picker("", selection: dashBinding) {
                        ForEach(DashStyle.allCases) { style in
                            Text(style.name).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                HStack {
                    Text("Point").font(.system(size: 11.5)).frame(width: 40, alignment: .leading)
                    Picker("", selection: pointShapeBinding) {
                        ForEach(PointShape.allCases) { shape in
                            Text(shape.name).tag(shape)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                HStack {
                    Text("Size").font(.system(size: 11.5)).frame(width: 40, alignment: .leading)
                    Picker("", selection: pointSizeBinding) {
                        Text("Dot").tag(3.0)
                        Text("Small").tag(4.5)
                        Text("Medium").tag(6.0)
                        Text("Large").tag(8.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                if anySelectedIsRegion {
                    HStack {
                        Text("Fill").font(.system(size: 11.5))
                        Slider(value: fillBinding, in: 0...0.4)
                    }
                }
            }
        }
    }

    private var colorRow: some View {
        HStack(spacing: 6) {
            ForEach(RGBA.palette, id: \.0) { name, color in
                Button {
                    applyToSelection("Change Color") { object in
                        object.style.color = color
                    }
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                                .padding(-1)
                        )
                }
                .buttonStyle(.plain)
                .help(name)
            }
            Spacer()
            ColorPicker("", selection: colorBinding)
                .labelsHidden()
                .frame(width: 26)
        }
    }

    private var sketchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Objects")
            let groups: [(String, [SketchObject])] = [
                ("Points", model.objects.filter { $0.isPointLike }),
                ("Lines", model.objects.filter { isLineObject($0) }),
                ("Circles & Regions", model.objects.filter { isRegionObject($0) }),
                ("Measures & Text", model.objects.filter { isMeasureObject($0) })
            ]
            ForEach(groups, id: \.0) { title, objects in
                if !objects.isEmpty {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 4)
                    ForEach(objects.sorted(by: { $0.order < $1.order })) { object in
                        objectRow(object)
                    }
                }
            }
        }
    }

    private func objectRow(_ object: SketchObject) -> some View {
        Button {
            model.selection = [object.id]
            tab = .object
        } label: {
            HStack(spacing: 7) {
                Image(systemName: model.symbol(for: object))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(model.selection.contains(object.id) ? Color.accentColor : Color.secondary)
                    .frame(width: 15)
                Text(model.displayName(for: object))
                    .font(.system(size: 11.5))
                    .foregroundStyle(object.visible ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer()
                if !object.visible {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(model.selection.contains(object.id) ? Color.accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Canvas")
            Toggle("Grid", isOn: $model.settings.grid)
                .font(.system(size: 11.5))
            Toggle("Axes", isOn: $model.settings.axes)
                .font(.system(size: 11.5))
            Toggle("Snap points to grid", isOn: $model.settings.snap)
                .font(.system(size: 11.5))
            Toggle("Show labels", isOn: $model.settings.showLabels)
                .font(.system(size: 11.5))
            HStack {
                Text("Length").font(.system(size: 11.5)).frame(width: 54, alignment: .leading)
                Picker("", selection: $model.settings.lengthUnit) {
                    ForEach(LengthUnit.allCases) { unit in
                        Text(unit.name).tag(unit)
                    }
                }
                .labelsHidden().pickerStyle(.menu)
            }
            HStack {
                Text("Angle").font(.system(size: 11.5)).frame(width: 54, alignment: .leading)
                Picker("", selection: $model.settings.angleUnit) {
                    ForEach(AngleUnit.allCases) { unit in
                        Text(unit.name).tag(unit)
                    }
                }
                .labelsHidden().pickerStyle(.menu)
            }
            HStack {
                Text("Decimals").font(.system(size: 11.5)).frame(width: 54, alignment: .leading)
                Picker("", selection: $model.settings.precision) {
                    ForEach(0...5, id: \.self) { p in
                        Text("\(p)").tag(p)
                    }
                }
                .labelsHidden().pickerStyle(.segmented)
            }
            HStack(spacing: 7) {
                Button("Fit") { model.fitCanvas(size: CGSize(width: 900, height: 700)) }
                Button("100%") { model.setZoom(SketchMetrics.pixelsPerCentimetre) }
                Button("Reset") {
                    model.settings.center = .zero
                    model.setZoom(SketchMetrics.pixelsPerCentimetre)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var constructSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("Construct")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                smallAction("Midpoint", "circle.dotted") { model.constructMidpoint() }
                smallAction("Intersection", "circle.circle") { model.constructIntersection() }
                smallAction("Perpendicular", "arrow.up.and.line.horizontal.and.arrow.down") { model.constructPerpendicular() }
                smallAction("Parallel", "equal") { model.constructParallel() }
                smallAction("Bisector", "angle") { model.constructBisector() }
                smallAction("Circle", "circle") { model.constructCircle() }
                smallAction("Polygon", "pentagon") { model.constructPolygon() }
                smallAction("Point on Object", "smallcircle.filled.circle") { model.constructPointOnPath() }
            }
            Button {
                onTextAnnotation(model.settings.center)
            } label: {
                Label("Add a caption", systemImage: "textformat")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
    }

    private func smallAction(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9.5))
                Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func actionButton(_ symbol: String, _ title: String, role: ButtonRole? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(title).font(.system(size: 9.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: object helpers / bindings

    private func needsLabel(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection, .caption, .angle: return true
        default: return false
        }
    }

    private func isMeasurement(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .angle: return true
        default: return false
        }
    }

    private func isLineObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector: return true
        default: return false
        }
    }

    private func isRegionObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .circle, .polygon: return true
        default: return false
        }
    }

    private func isMeasureObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .caption, .angle, .functionPlot: return true
        default: return false
        }
    }

    private func typeDescription(_ object: SketchObject) -> String {
        switch object.kind {
        case .freePoint: return "Free point"
        case .pointOnPath: return "Point on an object"
        case .midpoint: return "Constructed midpoint"
        case .intersection: return "Constructed intersection"
        case .segment: return "Segment"
        case .ray: return "Ray"
        case .line: return "Line"
        case .perpendicular: return "Perpendicular line"
        case .parallel: return "Parallel line"
        case .angleBisector: return "Angle bisector"
        case .circle: return "Circle"
        case .polygon: return "Polygon interior"
        case .angle: return "Angle marker"
        case .measurement(let kind, _): return "\(kind.title) measurement"
        case .calculation: return "Calculation"
        case .caption: return "Caption"
        case .functionPlot: return "Function plot"
        case .transformed(_, let spec): return "\(spec.kind.title) image"
        case .locus: return "Locus"
        }
    }

    private func labelBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { model.objectByID(id)?.label ?? "" },
            set: { value in
                guard let i = model.index(of: id) else { return }
                model.checkpoint("Edit Label", coalescing: "label-\(id)")
                model.objects[i].label = value
                model.isDirty = true
            }
        )
    }

    private func captionBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                if let object = model.objectByID(id), case .caption(let text) = object.kind { return text }
                return ""
            },
            set: { value in
                guard let i = model.index(of: id) else { return }
                if case .caption = model.objects[i].kind {
                    model.checkpoint("Edit Text", coalescing: "caption-\(id)")
                    model.objects[i].kind = .caption(value)
                    model.isDirty = true
                }
            }
        )
    }

    private func showLabelBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.objectByID(id)?.showLabel ?? true },
            set: { value in
                guard let i = model.index(of: id) else { return }
                model.checkpoint(value ? "Show Label" : "Hide Label")
                model.objects[i].showLabel = value
                model.isDirty = true
            }
        )
    }

    private func visibleBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.objectByID(id)?.visible ?? true },
            set: { value in
                guard let i = model.index(of: id) else { return }
                model.checkpoint(value ? "Show Object" : "Hide Object")
                model.objects[i].visible = value
                model.isDirty = true
            }
        )
    }

    private var lineWidthBinding: Binding<Double> {
        Binding(
            get: { model.selectedObjects.first?.style.lineWidth ?? 1.5 },
            set: { value in
                applyToSelection("Change Line Width", coalescing: "line-width") {
                    $0.style.lineWidth = value
                }
            }
        )
    }

    private var dashBinding: Binding<DashStyle> {
        Binding(
            get: { model.selectedObjects.first?.style.dash ?? .solid },
            set: { value in applyToSelection("Change Dash") { $0.style.dash = value } }
        )
    }

    private var pointShapeBinding: Binding<PointShape> {
        Binding(
            get: { model.selectedObjects.first?.style.pointShape ?? .filled },
            set: { value in applyToSelection("Change Point Shape") { $0.style.pointShape = value } }
        )
    }

    private var pointSizeBinding: Binding<Double> {
        Binding(
            get: { model.selectedObjects.first?.style.pointSize ?? 5.5 },
            set: { value in
                applyToSelection("Change Point Size") {
                    $0.style.pointSize = value
                }
            }
        )
    }

    private var fillBinding: Binding<Double> {
        Binding(
            get: { model.selectedObjects.first?.style.fillOpacity ?? 0.1 },
            set: { value in
                applyToSelection("Change Fill", coalescing: "fill") {
                    $0.style.fillOpacity = value
                }
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                let c = model.selectedObjects.first?.style.color ?? .ink
                return Color(red: c.r, green: c.g, blue: c.b)
            },
            set: { newValue in
                let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .black
                let c = RGBA(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
                applyToSelection("Change Color", coalescing: "colour") { $0.style.color = c }
            }
        )
    }

    private var anySelectedIsRegion: Bool {
        model.selectedObjects.contains { isRegionObject($0) }
    }

    private func applyToSelection(_ name: String, coalescing key: String? = nil,
                                  _ change: (inout SketchObject) -> Void) {
        guard !model.selection.isEmpty else { return }
        model.checkpoint(name, coalescing: key)
        for id in model.selection {
            if let i = model.index(of: id) {
                change(&model.objects[i])
            }
        }
        model.isDirty = true
    }
}

// MARK: - Small helpers
