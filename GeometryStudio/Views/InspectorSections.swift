import SwiftUI

/// The object browser's kind filter.
enum ObjectBrowserFilter: String, CaseIterable, Identifiable {
    case all
    case points
    case paths
    case regions
    case measures
    case hidden
    case locked

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .points:
            return "Points"
        case .paths:
            return "Paths"
        case .regions:
            return "Regions"
        case .measures:
            return "Measures & Text"
        case .hidden:
            return "Hidden"
        case .locked:
            return "Locked"
        }
    }
}

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
                            .help("Math: ^{2}, _{1}, \\alpha, \\overline{AB}, \\widehat{AB}")
                    }
                }

                if needsLabel(object), !object.label.isEmpty {
                    Text(MathLabel.attributed(object.label,
                                              base: .callout,
                                              script: .caption2,
                                              superscriptOffset: 5,
                                              subscriptOffset: -2))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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

                if case .parameter(_, let minimum, let maximum) = object.kind {
                    parameterControls(id, minimum: minimum, maximum: maximum)
                }
                if case .coordinateSystem(_, _, _, let unit) = object.kind {
                    coordinateControls(id, unit: unit)
                }
                if case .graph(let feature) = object.kind {
                    graphControls(id, feature: feature)
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
                Text("Pick an object on the canvas or in Layers below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var numericSection: some View {
        if model.selection.count == 1, let id = model.selection.first,
           let object = model.objectByID(id) {
            if case .freePoint = object.kind {
                Section("Position") {
                    lengthField("X", pointXBinding(id))
                    lengthField("Y", pointYBinding(id))
                }
            } else if case .circleRadius = object.kind {
                Section("Geometry") {
                    lengthField("Radius", circleRadiusBinding(id))
                }
            } else if case .segment = object.kind, segmentLengthEditable(id) {
                Section("Geometry") {
                    lengthField("Length", segmentLengthBinding(id))
                }
            } else if case .angle = object.kind, angleEditable(id) {
                Section("Geometry") {
                    LabeledContent("Angle") {
                        HStack(spacing: 6) {
                            TextField("Angle", value: angleBinding(id), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 72)
                            Text(model.settings.angleUnit == .radians ? "rad" : "°")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func lengthField(_ title: String, _ value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 72)
                Text(model.settings.lengthUnit.short)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func parameterControls(_ id: UUID, minimum: Double, maximum: Double) -> some View {
        LabeledContent("Value") {
            Slider(value: parameterValueBinding(id),
                   in: min(minimum, maximum)...max(minimum, maximum))
        }
        LabeledContent("Range") {
            HStack(spacing: 6) {
                TextField("Min", value: parameterMinimumBinding(id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 64)
                Text("to")
                    .foregroundStyle(.secondary)
                TextField("Max", value: parameterMaximumBinding(id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 64)
            }
        }
    }

    @ViewBuilder
    private func coordinateControls(_ id: UUID, unit: LengthUnit) -> some View {
        LabeledContent("Type") {
            Picker("Type", selection: coordinateKindBinding(id)) {
                ForEach(CoordinateKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        LabeledContent("Unit") {
            Picker("Unit", selection: coordinateUnitBinding(id)) {
                ForEach(LengthUnit.allCases) { unit in
                    Text(unit.name).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        LabeledContent("Step") {
            HStack(spacing: 6) {
                TextField("Step", value: coordinateStepBinding(id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 64)
                Text(unit.short)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func graphControls(_ id: UUID, feature: GraphFeature) -> some View {
        switch feature {
        case .derivative:
            EmptyView()
        case .integral:
            LabeledContent("From") {
                TextField("From", value: graphFromBinding(id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 64)
            }
            LabeledContent("To") {
                TextField("To", value: graphToBinding(id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 64)
            }
        case .tangent:
            LabeledContent("At x") {
                TextField("x", value: graphTangentXBinding(id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 64)
            }
        case .table:
            LabeledContent("From") {
                TextField("From", value: graphFromBinding(id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 64)
            }
            LabeledContent("To") {
                TextField("To", value: graphToBinding(id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 64)
            }
            LabeledContent("Step") {
                TextField("Step", value: graphStepBinding(id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 64)
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

                Menu {
                    Text("Mirror: \(model.markName(model.marks.mirror))")
                    Text("Center: \(model.markName(model.marks.center))")
                    Text("Angle: \(angleMarkName)")
                    Text("Ratio: \(ratioMarkName)")
                    Text("Vector: \(vectorMarkName)")
                    Divider()
                    Button("Clear Marks") { model.clearMarks() }
                        .disabled(model.marks.isEmpty)
                } label: {
                    Label("Marks", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .selectionDisabled()

                Button {
                    onTextAnnotation(model.settings.center)
                } label: {
                    Label("Add Caption", systemImage: "textformat")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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

                HStack(spacing: 8) {
                    Button {
                        model.duplicateSelection()
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    Button {
                        model.toggleLockSelection()
                    } label: {
                        Label(lockLabel,
                              systemImage: selectionIsLocked ? "lock.open" : "lock")
                    }
                    Button {
                        model.bringSelectionToFront()
                    } label: {
                        Label("Front", systemImage: "chevron.up.square")
                    }
                    Button {
                        model.sendSelectionToBack()
                    } label: {
                        Label("Back", systemImage: "chevron.down.square")
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
                if anySelectedIsSegment {
                    LabeledContent("Ticks") {
                        Picker("Ticks", selection: tickCountBinding) {
                            Text("None").tag(0)
                            Text("One").tag(1)
                            Text("Two").tag(2)
                            Text("Three").tag(3)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                if anySelectedIsAngle {
                    LabeledContent("Marker") {
                        Picker("Marker", selection: angleMarkerBinding) {
                            ForEach(AngleMarkerStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
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
    var layersSection: some View {
        Section("Layers") {
            TextField("Search objects", text: $browserQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search objects")
            LabeledContent("Filter") {
                Picker("Filter", selection: $browserFilter) {
                    ForEach(ObjectBrowserFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if filteredObjects.isEmpty {
                Text("No objects match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        ForEach(objectGroups, id: \.0) { title, objects in
            if !objects.isEmpty {
                DisclosureGroup(isExpanded: expandedGroup(title)) {
                    ForEach(objects.sorted(by: { $0.order < $1.order })) { object in
                        objectRow(object)
                            .tag(object.id)
                    }
                } label: {
                    Text(title)
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var filteredObjects: [SketchObject] {
        var result = model.objects.filter(matchesBrowserFilter)
        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter {
                model.displayName(for: $0).localizedCaseInsensitiveContains(query)
                    || $0.label.localizedCaseInsensitiveContains(query)
            }
        }
        return result
    }

    private func matchesBrowserFilter(_ object: SketchObject) -> Bool {
        switch browserFilter {
        case .all:
            return true
        case .points:
            return object.isPointLike
        case .paths:
            return isLineObject(object) || isArcObject(object)
        case .regions:
            return isRegionObject(object)
        case .measures:
            return isMeasureObject(object)
        case .hidden:
            return !object.visible
        case .locked:
            return object.isLocked
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

    // MARK: - Row and section helpers

    private var objectGroups: [(String, [SketchObject])] {
        [
            ("Points", filteredObjects.filter { $0.isPointLike }),
            ("Lines", filteredObjects.filter {
                isLineObject($0) && !isVectorObject($0) && !isConstructionObject($0)
                    && !isGraphObject($0)
            }),
            ("Arcs", filteredObjects.filter { isArcObject($0) }),
            ("Circles & Regions", filteredObjects.filter {
                isRegionObject($0) && !isGraphObject($0)
            }),
            ("Vectors & Constructions", filteredObjects.filter {
                isVectorObject($0) || isConstructionObject($0)
            }),
            ("Graph", filteredObjects.filter {
                isGraphObject($0) || isCoordinateObject($0)
            }),
            ("Images & Loci", filteredObjects.filter {
                isTransformedObject($0) || isLocusObject($0)
            }),
            ("Parameters", filteredObjects.filter { isParameterObject($0) }),
            ("Measures & Text", filteredObjects.filter { isMeasureObject($0) })
        ]
    }

    private var traceLabel: String {
        !model.selection.isEmpty && model.selection.allSatisfy { model.tracedIDs.contains($0) }
            ? "Untrace" : "Trace"
    }

    private var selectionIsLocked: Bool {
        !model.selection.isEmpty && model.selectedObjects.allSatisfy(\.isLocked)
    }

    private var lockLabel: String {
        selectionIsLocked ? "Unlock" : "Lock"
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
            if object.isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Locked")
            }
            if !object.visible {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Hidden")
            }
        }
        .contextMenu {
            Button(object.isLocked ? "Unlock" : "Lock") {
                selectForRow(object.id)
                model.toggleLockSelection()
            }
            Button("Bring to Front") {
                selectForRow(object.id)
                model.bringSelectionToFront()
            }
            Button("Send to Back") {
                selectForRow(object.id)
                model.sendSelectionToBack()
            }
            Divider()
            Button("Duplicate") {
                selectForRow(object.id)
                model.duplicateSelection()
            }
            Button("Delete", role: .destructive) {
                selectForRow(object.id)
                model.deleteSelection()
            }
        }
    }

    private func selectForRow(_ id: UUID) {
        if !model.selection.contains(id) {
            model.selection = [id]
        }
    }

}
