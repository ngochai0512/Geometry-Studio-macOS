import SwiftUI

// Inspector sections. The computed properties are internal because
// `InspectorView.body` composes them; helpers that stay in this file are
// private.

extension InspectorView {

    @ViewBuilder
    var objectSection: some View {
        Section("Selection") {
            if model.selection.count == 1, let id = model.selection.first, let object = model.objectByID(id) {
                HStack(spacing: 8) {
                    Image(systemName: model.symbol(for: object))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.displayName(for: object))
                            .font(.callout.weight(.semibold))
                        Text(typeDescription(object))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.definition(for: object))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if needsLabel(object) {
                    LabeledContent("Label") {
                        TextField("Label", text: labelBinding(id))
                            .textFieldStyle(.bordered)
                            .textInputBorderShape(.roundedRectangle)
                            .frame(minWidth: 120)
                            .font(.subheadline)
                    }
                }

                if case .caption = object.kind {
                    TextField("Text", text: captionBinding(id), axis: .vertical)
                        .lineLimit(2...5)
                        .font(.subheadline)
                }

                let measurement = model.evaluated(id).text
                if let measurement, !measurement.isEmpty, isMeasurement(object) {
                    Text(measurement)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .textSelection(.enabled)
                }
            } else if model.selection.count > 1 {
                Text("\(model.selection.count) objects selected")
                    .font(.callout.weight(.medium))
                Text("Change their colour, line style or visibility together, or use Construct to build from them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing selected")
                    .font(.callout.weight(.medium))
                Text("Pick an object on the canvas, or choose Sketch to browse every object.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var actionsSection: some View {
        if !model.selection.isEmpty {
            Section("Actions") {
                HStack(spacing: 8) {
                    Button {
                        model.hideSelection()
                    } label: {
                        Label("Hide", systemImage: "eye.slash")
                    }
                    Button {
                        model.toggleLabels(for: model.selection)
                    } label: {
                        Label("Labels", systemImage: "textformat.abc")
                    }
                    Button(role: .destructive) {
                        model.deleteSelection()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .selectionDisabled()

                Menu {
                    Button("Reflect") { model.reflectSelection() }
                    Button("Rotate") { model.rotateSelection() }
                    Button("Dilate") { model.dilateSelection() }
                    Button("Translate") { model.translateSelection() }
                    Divider()
                    Button("Mark Mirror") { model.markMirror() }
                    Button("Mark Center") { model.markCenter() }
                    Button("Mark Angle") { model.markAngle() }
                    Button("Mark Ratio") { model.markRatio() }
                    Button("Mark Vector") { model.markVector() }
                    Divider()
                    Button("Clear Marks") { model.clearMarks() }
                } label: {
                    Label("Transform Selection", systemImage: "arrow.triangle.2.circlepath")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .selectionDisabled()

                HStack(spacing: 8) {
                    Button {
                        model.toggleAnimation()
                    } label: {
                        Label(model.animationPointID == nil ? "Animate" : "Pause",
                              systemImage: model.animationPointID == nil ? "play" : "pause")
                    }
                    Button {
                        model.toggleTrace()
                    } label: {
                        Label(traceLabel,
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .selectionDisabled()
            }
        }
    }

    @ViewBuilder
    var stylingSection: some View {
        if !model.selection.isEmpty {
            Section("Style") {
                colorRow
                LabeledContent("Line") {
                    Picker("Line", selection: lineWidthBinding) {
                        Text("Hairline").tag(0.8)
                        Text("Thin").tag(1.2)
                        Text("Regular").tag(1.5)
                        Text("Bold").tag(2.2)
                        Text("Heavy").tag(3.2)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                LabeledContent("Dash") {
                    Picker("Dash", selection: dashBinding) {
                        ForEach(DashStyle.allCases) { style in
                            Text(style.name).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                LabeledContent("Point") {
                    Picker("Point", selection: pointShapeBinding) {
                        ForEach(PointShape.allCases) { shape in
                            Text(shape.name).tag(shape)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                LabeledContent("Size") {
                    Picker("Size", selection: pointSizeBinding) {
                        Text("Default").tag(5.5)
                        Text("Dot").tag(3.0)
                        Text("Small").tag(4.5)
                        Text("Medium").tag(6.0)
                        Text("Large").tag(8.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                if anySelectedIsRegion || anySelectedIsArc {
                    LabeledContent("Fill") {
                        Slider(value: fillBinding, in: 0...0.4)
                            .labelsHidden()
                    }
                }
                if anySelectedIsArc {
                    LabeledContent("Arc fill") {
                        Picker("Arc fill", selection: arcFillBinding) {
                            ForEach(ArcFill.allCases) { fill in
                                Text(fill.title).tag(fill)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var sketchSection: some View {
        ForEach(objectGroups, id: \.0) { title, objects in
            if !objects.isEmpty {
                Section(title) {
                    ForEach(objects.sorted(by: { $0.order < $1.order })) { object in
                        objectRow(object)
                            .tag(object.id)
                    }
                }
            }
        }
    }

    var marksSection: some View {
        Section("Marks") {
            LabeledContent("Mirror", value: model.markName(model.marks.mirror))
            LabeledContent("Center", value: model.markName(model.marks.center))
            LabeledContent("Angle", value: angleMarkName)
            LabeledContent("Ratio", value: ratioMarkName)
            LabeledContent("Vector", value: vectorMarkName)
            Button("Clear Marks") { model.clearMarks() }
                .disabled(model.marks.isEmpty)
                .selectionDisabled()
        }
    }

    private var angleMarkName: String {
        guard let mark = model.marks.angle else {
            return "—"
        }
        return "\(model.markName(mark.a)) \(model.markName(mark.vertex)) \(model.markName(mark.c))"
    }

    private var ratioMarkName: String {
        guard let mark = model.marks.ratio else {
            return "—"
        }
        return "\(model.markName(mark.first)) / \(model.markName(mark.second))"
    }

    private var vectorMarkName: String {
        guard let mark = model.marks.vector else {
            return "—"
        }
        return "\(model.markName(mark.from)) → \(model.markName(mark.to))"
    }

    var canvasSection: some View {
        Section("Canvas") {
            Group {
                Toggle("Grid", isOn: $model.settings.grid)
                LabeledContent("Grid style") {
                    Picker("Grid style", selection: $model.settings.gridType) {
                        ForEach(GridType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Toggle("Axes", isOn: $model.settings.axes)
                Toggle("Snap points to grid", isOn: $model.settings.snap)
                Toggle("Show labels", isOn: $model.settings.showLabels)
                LabeledContent("Length") {
                    Picker("Length", selection: $model.settings.lengthUnit) {
                        ForEach(LengthUnit.allCases) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                LabeledContent("Angle") {
                    Picker("Angle", selection: $model.settings.angleUnit) {
                        ForEach(AngleUnit.allCases) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                LabeledContent("Decimals") {
                    Picker("Decimals", selection: $model.settings.precision) {
                        ForEach(0...5, id: \.self) { p in
                            Text("\(p)").tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                HStack(spacing: 8) {
                    Button("Fit") { model.fitCanvas(size: model.canvasSize) }
                    Button("100%") { model.setZoom(SketchMetrics.pixelsPerCentimetre) }
                    Button("Reset") {
                        model.settings.center = .zero
                        model.setZoom(SketchMetrics.pixelsPerCentimetre)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.subheadline)
            .selectionDisabled()
        }
    }

    var constructSection: some View {
        Section("Construct") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                constructButton("Midpoint", "circle.dotted") { model.constructMidpoint() }
                constructButton("Intersection", "circle.circle") { model.constructIntersection() }
                constructButton("Perpendicular", "arrow.up.and.line.horizontal.and.arrow.down") { model.constructPerpendicular() }
                constructButton("Parallel", "equal") { model.constructParallel() }
                constructButton("Bisector", "angle") { model.constructBisector() }
                constructButton("Circle", "circle") { model.constructCircle() }
                constructButton("Circle by Radius", "circle.dashed") {
                    NotificationCenter.default.post(name: .openCircleRadius, object: nil)
                }
                constructButton("Arc on Circle", "circle.dotted") { model.constructArcOnCircle() }
                constructButton("Arc Through 3", "circle.dashed") { model.constructArcThroughPoints() }
                constructButton("Polygon", "pentagon") { model.constructPolygon() }
                constructButton("Point on Object", "smallcircle.filled.circle") { model.constructPointOnPath() }
            }
            .selectionDisabled()

            Button {
                onTextAnnotation(model.settings.center)
            } label: {
                Label("Add a caption", systemImage: "textformat")
            }
            .selectionDisabled()
        }
    }

    // MARK: - Row and section helpers

    private var objectGroups: [(String, [SketchObject])] {
        [
            ("Points", model.objects.filter { $0.isPointLike }),
            ("Lines", model.objects.filter { isLineObject($0) }),
            ("Arcs", model.objects.filter { isArcObject($0) }),
            ("Circles & Regions", model.objects.filter { isRegionObject($0) }),
            ("Measures & Text", model.objects.filter { isMeasureObject($0) })
        ]
    }

    private var traceLabel: String {
        !model.selection.isEmpty && model.selection.allSatisfy { model.tracedIDs.contains($0) }
            ? "Untrace" : "Trace"
    }

    private var colorRow: some View {
        LabeledContent("Color") {
            HStack(spacing: 8) {
                Menu {
                    ForEach(RGBA.palette, id: \.0) { name, color in
                        Button(name) {
                            applyToSelection("Change Color") { object in
                                object.style.color = color
                            }
                        }
                    }
                } label: {
                    Label("Palette", systemImage: "paintpalette")
                        .labelStyle(.iconOnly)
                }
                .help("Palette")
                .accessibilityLabel("Palette")

                ColorPicker("Color", selection: colorBinding)
                    .labelsHidden()
            }
        }
    }

    private func objectRow(_ object: SketchObject) -> some View {
        HStack(spacing: 7) {
            Label {
                Text(model.displayName(for: object))
                    .foregroundStyle(object.visible ? .primary : .secondary)
                    .lineLimit(1)
            } icon: {
                Image(systemName: model.symbol(for: object))
            }
            Spacer()
            if !object.visible {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Hidden")
            }
        }
    }

    private func constructButton(_ title: String, _ symbol: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
