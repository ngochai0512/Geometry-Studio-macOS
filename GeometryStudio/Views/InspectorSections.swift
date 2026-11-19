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

                Toggle("Show label", isOn: showLabelBinding(id))
                    .font(.subheadline)
                Toggle("Visible", isOn: visibleBinding(id))
                    .font(.subheadline)
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
                    Button("Reflect Across Selected Line") { model.reflectSelection() }
                    Button("Rotate…") { NotificationCenter.default.post(name: .openRotate, object: nil) }
                    Button("Dilate…") { NotificationCenter.default.post(name: .openDilate, object: nil) }
                    Button("Translate…") { NotificationCenter.default.post(name: .openTranslate, object: nil) }
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
                if anySelectedIsRegion {
                    LabeledContent("Fill") {
                        Slider(value: fillBinding, in: 0...0.4)
                            .labelsHidden()
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

    var canvasSection: some View {
        Section("Canvas") {
            Group {
                Toggle("Grid", isOn: $model.settings.grid)
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
