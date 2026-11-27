import SwiftUI
import AppKit

extension SketchCanvas {

    // MARK: drawing

    func draw(context: inout GraphicsContext, size: CGSize) {
        let rect = model.visibleRect(size: size)
        drawGrid(context: &context, size: size, rect: rect)
        drawCoordinateSystems(context: &context, size: size)
        drawTraces(context: &context, size: size)

        var e = model.evaluator()
        let ordered = model.objects.sorted { $0.order < $1.order }

        // Fills first: polygons, circles and filled arcs sit under the lines.
        for object in ordered where object.visible {
            let result = e.evaluate(object.id)
            if let fill = result.fill {
                drawFill(fill, style: object.style, context: &context, size: size)
                continue
            }
            guard let path = result.path else {
                continue
            }
            drawFill(path, style: object.style, context: &context, size: size)
        }

        // Paths.
        for object in ordered where object.visible {
            guard let path = e.evaluate(object.id).path else {
                continue
            }
            let selected = model.isSelected(object.id)
            if selected {
                stroke(path: path, style: object.style, selected: false, glow: true,
                       context: &context, size: size, rect: rect)
            }
            stroke(path: path, style: object.style, selected: selected, glow: false,
                   context: &context, size: size, rect: rect)
        }

        drawDraft(context: &context, size: size)
        drawSmartGuides(context: &context, size: size)
        drawVectors(context: &context, size: size, evaluator: &e)
        drawAngles(context: &context, size: size, evaluator: &e)
        drawPoints(context: &context, size: size, evaluator: &e)
        drawTexts(context: &context, size: size, evaluator: &e)
        drawParameters(context: &context, size: size)
        drawSelectionHandles(context: &context, size: size)
        drawScaleBar(context: &context, size: size)
        drawMarquee(context: &context, size: size)
    }

    /// CPU layer under the Metal geometry: grid, coordinate systems and axes.
    func drawBackground(context: inout GraphicsContext, size: CGSize) {
        let rect = model.visibleRect(size: size)
        drawGrid(context: &context, size: size, rect: rect)
        drawCoordinateSystems(context: &context, size: size)
    }

    /// The Metal layer is an enhancement, not the only copy of the geometry.
    /// Drawing the same fills and strokes here keeps a sketch readable if the
    /// GPU layer cannot present, which would otherwise leave only the points
    /// that the foreground canvas draws.
    func drawMetalFallback(context: inout GraphicsContext, size: CGSize,
                                   rect: WorldRect) {
        var evaluator = model.evaluator()
        let ordered = model.objects.sorted { $0.order < $1.order }
        if !metalReady {
            drawTraces(context: &context, size: size)
            for object in ordered where object.visible {
                let result = evaluator.evaluate(object.id)
                if let fill = result.fill {
                    drawFill(fill, style: object.style, alphaScale: 0.5,
                             context: &context, size: size)
                    continue
                }
                guard let path = result.path else {
                    continue
                }
                drawFill(path, style: object.style, alphaScale: 0.5,
                         context: &context, size: size)
            }
        }
        // Opaque strokes are safe to overdraw when Metal is working; this
        // keeps every path visible even if the GPU layer never presents.
        for object in ordered where object.visible {
            guard let path = evaluator.evaluate(object.id).path else {
                continue
            }
            stroke(path: path,
                   style: object.style,
                   selected: model.isSelected(object.id),
                   glow: false,
                   context: &context,
                   size: size,
                   rect: rect)
        }
    }

    /// CPU layer above the Metal geometry: points, labels, draft and chrome.
    func drawForeground(context: inout GraphicsContext, size: CGSize) {
        var e = model.evaluator()
        if usesMetal {
            drawMetalFallback(context: &context, size: size,
                              rect: model.visibleRect(size: size))
        }
        drawDraft(context: &context, size: size)
        drawSmartGuides(context: &context, size: size)
        drawVectors(context: &context, size: size, evaluator: &e)
        drawAngles(context: &context, size: size, evaluator: &e)
        drawPoints(context: &context, size: size, evaluator: &e)
        drawTexts(context: &context, size: size, evaluator: &e)
        drawParameters(context: &context, size: size)
        drawSelectionHandles(context: &context, size: size)
        drawScaleBar(context: &context, size: size)
        drawMarquee(context: &context, size: size)
    }


    // MARK: live overlays































}
