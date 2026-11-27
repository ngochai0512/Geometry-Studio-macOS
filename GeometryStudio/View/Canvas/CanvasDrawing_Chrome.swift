import SwiftUI
import AppKit

extension SketchCanvas {

    func drawMarquee(context: inout GraphicsContext, size: CGSize) {
        guard let ms = marqueeStart, let mc = marqueeCurrent else {
            return
        }
        let rect = CGRect(x: min(ms.x, mc.x), y: min(ms.y, mc.y),
                          width: abs(mc.x - ms.x), height: abs(mc.y - ms.y))
        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(accent.opacity(0.08)))
        context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(accent.opacity(0.7)), lineWidth: 1)
    }

    @ViewBuilder
    func canvasOverlay(size: CGSize) -> some View {
        if let id = dragPointID, didMove, let screen = hudScreen {
            let rows = model.dragReadout(for: id)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 6) {
                        Text(rows[index].0)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(rows[index].1)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(accent.opacity(0.25), lineWidth: 0.8)
            }
            .frame(width: 190)
            .position(
                x: min(max(screen.x + 106, 100), max(size.width - 100, 100)),
                y: max(screen.y - 44, 34)
            )
            .allowsHitTesting(false)
        }

        if let id = editingLabelID,
           let object = model.objectByID(id),
           let anchor = model.labelAnchor(for: object) {
            let point = model.screenPoint(anchor, size: size)
            HStack(spacing: 5) {
                TextField("Label", text: $labelDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($labelFieldFocused)
                    .frame(width: 170)
                    .onSubmit { commitLabelEdit() }
                Button {
                    commitLabelEdit()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Apply label")
                .accessibilityLabel("Apply label")
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.35), lineWidth: 0.8)
            }
            .position(
                x: min(max(point.x + 90, 110), max(size.width - 110, 110)),
                y: min(max(point.y - 26, 26), max(size.height - 26, 26))
            )
            .onAppear {
                DispatchQueue.main.async {
                    labelFieldFocused = true
                }
            }
            .onChange(of: labelFieldFocused) { _, focused in
                if !focused {
                    commitLabelEdit()
                }
            }
            .onExitCommand {
                editingLabelID = nil
                labelFieldFocused = false
            }
        }

        if let id = editingCoordinateID,
           let object = model.objectByID(id),
           let position = object.position {
            let point = model.screenPoint(position, size: size)
            HStack(spacing: 5) {
                TextField("x", text: $coordinateDraftX)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 62)
                    .focused($coordinateFieldFocused)
                    .onSubmit { commitCoordinateEdit() }
                TextField("y", text: $coordinateDraftY)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 62)
                    .onSubmit { commitCoordinateEdit() }
                Button {
                    commitCoordinateEdit()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Apply coordinates")
                .accessibilityLabel("Apply coordinates")
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.35), lineWidth: 0.8)
            }
            .position(
                x: min(max(point.x + 110, 130), max(size.width - 130, 130)),
                y: min(max(point.y - 26, 26), max(size.height - 26, 26))
            )
            .onAppear {
                DispatchQueue.main.async {
                    coordinateFieldFocused = true
                }
            }
            .onExitCommand {
                editingCoordinateID = nil
                coordinateFieldFocused = false
            }
        }
    }

    func beginCoordinateEditing(_ id: UUID) {
        guard let object = model.objectByID(id), !object.isLocked,
              case .freePoint = object.kind,
              let position = object.position else {
            return
        }
        let unit = model.settings.lengthUnit.perUnit
        let digits = max(0, min(model.settings.precision, 6))
        coordinateDraftX = String(format: "%.\(digits)f", position.x / unit)
        coordinateDraftY = String(format: "%.\(digits)f", position.y / unit)
        model.selection = [id]
        editingLabelID = nil
        editingCoordinateID = id
    }

    func commitCoordinateEdit() {
        guard let id = editingCoordinateID, let object = model.objectByID(id),
              case .freePoint = object.kind else {
            editingCoordinateID = nil
            return
        }
        func number(_ text: String) -> Double? {
            let normalized = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            guard let value = Double(normalized), value.isFinite else {
                return nil
            }
            return value
        }
        guard let x = number(coordinateDraftX), let y = number(coordinateDraftY) else {
            return
        }
        let unit = model.settings.lengthUnit.perUnit
        model.moveFreePoint(id, to: Vec2(x * unit, y * unit), coalescing: "inline-point-\(id)")
        editingCoordinateID = nil
        coordinateFieldFocused = false
    }

    func beginLabelEditing(_ id: UUID) {
        guard let object = model.objectByID(id), !object.isLocked else {
            return
        }
        switch object.kind {
        case .measurement, .calculation, .functionPlot, .graph:
            // These cards show a computed value, not an editable label.
            return
        default:
            break
        }
        guard model.labelAnchor(for: object) != nil else {
            return
        }
        model.selection = [id]
        if case .caption(let text) = object.kind {
            labelDraft = text
        } else {
            labelDraft = object.label
        }
        editingCoordinateID = nil
        editingLabelID = id
    }

    func commitLabelEdit() {
        guard let id = editingLabelID, let object = model.objectByID(id) else {
            editingLabelID = nil
            return
        }
        let trimmed = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        var isCaption = false
        if case .caption = object.kind {
            isCaption = true
        }
        if !trimmed.isEmpty || !isCaption {
            model.setLabelText(id, isCaption ? trimmed : labelDraft)
        }
        editingLabelID = nil
        labelFieldFocused = false
    }

    func drawSmartGuides(context: inout GraphicsContext, size: CGSize) {
        guard !printing else {
            return
        }
        drawGuides(model.smartGuides, context: &context, size: size)
    }

    func drawGuides(_ guides: [SmartGuide], context: inout GraphicsContext, size: CGSize) {
        for guide in guides {
            switch guide.kind {
            case .point, .midpoint, .intersection:
                let center = Vec2((guide.from.x + guide.to.x) / 2,
                                  (guide.from.y + guide.to.y) / 2)
                let s = model.screenPoint(center, size: size)
                let box = CGRect(x: s.x - 5, y: s.y - 5, width: 10, height: 10)
                context.stroke(Path(ellipseIn: box),
                               with: .color(accent.opacity(0.85)),
                               lineWidth: 1.3)
            case .alignment, .parallel, .perpendicular, .angle:
                var path = Path()
                path.move(to: model.screenPoint(guide.from, size: size))
                path.addLine(to: model.screenPoint(guide.to, size: size))
                context.stroke(path, with: .color(accent.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
    }

    func drawSelectionHandles(context: inout GraphicsContext, size: CGSize) {
        guard !printing, let box = model.movableSelectionBounds() else {
            return
        }
        let a = model.screenPoint(Vec2(box.minX, box.minY), size: size)
        let b = model.screenPoint(Vec2(box.maxX, box.maxY), size: size)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(b.x - a.x), height: abs(b.y - a.y))
        context.stroke(Path(roundedRect: rect, cornerRadius: 2),
                       with: .color(accent.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        for corner in corners {
            let handle = CGRect(x: corner.x - 4, y: corner.y - 4, width: 8, height: 8)
            context.fill(Path(roundedRect: handle, cornerRadius: 1.5),
                         with: .color(palette.card.color))
            context.stroke(Path(roundedRect: handle, cornerRadius: 1.5),
                           with: .color(accent.opacity(0.8)), lineWidth: 1.2)
        }

        let rotate = CGPoint(x: rect.midX, y: rect.minY - 20)
        var stem = Path()
        stem.move(to: CGPoint(x: rect.midX, y: rect.minY))
        stem.addLine(to: rotate)
        context.stroke(stem, with: .color(accent.opacity(0.6)), lineWidth: 1)
        let rotateHandle = CGRect(x: rotate.x - 5, y: rotate.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: rotateHandle), with: .color(palette.card.color))
        context.stroke(Path(ellipseIn: rotateHandle),
                       with: .color(accent.opacity(0.85)), lineWidth: 1.3)
    }

    func drawDraft(context: inout GraphicsContext, size: CGSize) {
        var evaluator = model.evaluator()
        var pending = model.draft.compactMap { evaluator.evaluate($0).point }
        var previewAnchor: Vec2?
        if pending.isEmpty {
            previewAnchor = dragPreviewStart
            if let start = dragPreviewStart {
                pending = [start]
            }
        }
        guard let first = pending.first else {
            return
        }

        let anchor = previewAnchor ?? pending.last
        let hover = dragPreviewStart == nil ? model.hoverWorld : dragPreviewCurrent
        var target = hover
        var guides: [SmartGuide] = []
        if let hover {
            let exclusions: Set<UUID> = (model.tool == .polygon || model.tool == .angle)
                ? []
                : Set(model.draft)
            let snap = model.smartSnappedPoint(hover,
                                               tolerance: 9 / model.settings.scale,
                                               anchor: anchor,
                                               excluding: exclusions,
                                               includeIntersections: false)
            target = snap.point
            guides = snap.guides
        }
        drawGuides(guides, context: &context, size: size)

        var p = Path()
        p.move(to: model.screenPoint(first, size: size))
        for point in pending.dropFirst() {
            p.addLine(to: model.screenPoint(point, size: size))
        }
        if let target {
            p.addLine(to: model.screenPoint(target, size: size))
        }
        context.stroke(p, with: .color(accent.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [6, 4]))

        if model.tool == .circle {
            let c = model.screenPoint(first, size: size)
            let edge = target ?? first
            let edgeScreen = model.screenPoint(edge, size: size)
            let r = hypot(edgeScreen.x - c.x, edgeScreen.y - c.y)
            let box = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: box), with: .color(accent.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }

        if pending.count >= 3 && model.tool == .polygon {
            var fill = Path()
            fill.move(to: model.screenPoint(pending[0], size: size))
            for point in pending.dropFirst() {
                fill.addLine(to: model.screenPoint(point, size: size))
            }
            fill.closeSubpath()
            context.fill(fill, with: .color(accent.opacity(0.07)))
        }

        if let target {
            let readout: String?
            switch model.tool {
            case .segment, .ray, .line, .polygon:
                let origin = pending.last ?? first
                readout = evaluator.formatLength(origin.distance(to: target))
            case .circle:
                readout = "r " + evaluator.formatLength(first.distance(to: target))
            case .angle where pending.count >= 2:
                let vertex = pending[pending.count - 1]
                let start = pending[pending.count - 2]
                var delta = atan2(target.y - vertex.y, target.x - vertex.x)
                    - atan2(start.y - vertex.y, start.x - vertex.x)
                while delta > .pi {
                    delta -= .pi * 2
                }
                while delta < -.pi {
                    delta += .pi * 2
                }
                readout = evaluator.formatAngle(abs(delta))
            default:
                readout = nil
            }
            if let readout, !readout.isEmpty {
                drawDraftReadout(readout,
                                 at: model.screenPoint(target, size: size),
                                 context: &context,
                                 size: size)
            }
        }
    }

    /// The live dimension chip shown while a tool is drawing.
    func drawDraftReadout(_ text: String, at point: CGPoint,
                                  context: inout GraphicsContext, size: CGSize) {
        let resolved = context.resolve(
            Text(text)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(palette.ink.color)
        )
        let measured = resolved.measure(in: CGSize(width: 240, height: 40))
        let width = measured.width + 14
        let height = measured.height + 8
        var origin = CGPoint(x: point.x + 14, y: point.y - 14 - height)
        if origin.x + width > size.width - 6 {
            origin.x = point.x - 14 - width
        }
        if origin.y < 6 {
            origin.y = point.y + 16
        }
        let rect = CGRect(origin: origin, size: CGSize(width: width, height: height))
        context.fill(Path(roundedRect: rect, cornerRadius: 5),
                     with: .color(palette.card.color))
        context.stroke(Path(roundedRect: rect, cornerRadius: 5),
                       with: .color(palette.cardBorder.color),
                       lineWidth: 0.8)
        context.draw(resolved, at: CGPoint(x: rect.minX + 7, y: rect.minY + 4),
                     anchor: .topLeading)
    }

    func drawScaleBar(context: inout GraphicsContext, size: CGSize) {
        // A quiet scale reference in the lower-left corner.
        let scale = model.settings.scale
        let unit = model.settings.lengthUnit
        let oneUnit = scale * unit.perUnit
        guard oneUnit > 0, oneUnit.isFinite else {
            return
        }
        let target = oneUnit
        var length = target
        while length < 46 {
            length *= 2
        }
        while length > 140 {
            length /= 2
        }
        let x: CGFloat = 18
        let y = size.height - 20
        var p = Path()
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x + length, y: y))
        p.move(to: CGPoint(x: x, y: y - 3))
        p.addLine(to: CGPoint(x: x, y: y + 3))
        p.move(to: CGPoint(x: x + length, y: y - 3))
        p.addLine(to: CGPoint(x: x + length, y: y + 3))
        context.stroke(p, with: .color(secondaryInk.opacity(0.5)), lineWidth: 1)
        let value = length / scale / unit.perUnit
        let label = Text("\(GridMetrics.cleanNumber(value)) \(unit.short)")
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(secondaryInk.opacity(0.65))
        context.draw(label, at: CGPoint(x: x, y: y - 6), anchor: .bottomLeading)
    }
}
