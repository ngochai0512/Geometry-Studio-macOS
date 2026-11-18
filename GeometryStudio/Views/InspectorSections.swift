import SwiftUI

// Inspector sections. The computed properties are internal because
// `InspectorView.body` composes them; helpers that stay in this file are
// private.

extension InspectorView {

    @ViewBuilder
    var objectSection: some View {
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
                    LabeledContent("Label") {
                        TextField("Label", text: labelBinding(id))
                            .textFieldStyle(.bordered)
                            .textInputBorderShape(.roundedRectangle)
                            .frame(width: 130)
                            .font(.system(size: 11.5))
                    }
                }

                if case .caption = object.kind {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Text").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        TextField("Text", text: captionBinding(id), axis: .vertical)
                            .textFieldStyle(.bordered)
                            .textInputBorderShape(.roundedRectangle)
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
    var actionsSection: some View {
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
                .menuStyle(.button)
                .buttonStyle(.borderless)

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

    @ViewBuilder
    var stylingSection: some View {
        if !model.selection.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Style")
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
                    .pickerStyle(.segmented)
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
            .font(.system(size: 11.5))
        }
    }

    var sketchSection: some View {
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

    var canvasSection: some View {
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
        .font(.system(size: 11.5))
    }

    var constructSection: some View {
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

    // MARK: - Row and section helpers

    private var traceLabel: String {
        !model.selection.isEmpty && model.selection.allSatisfy { model.tracedIDs.contains($0) }
            ? "Untrace" : "Trace"
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
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                                .padding(-1)
                        }
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
}
