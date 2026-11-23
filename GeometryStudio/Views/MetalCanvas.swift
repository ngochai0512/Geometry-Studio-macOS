import AppKit
import MetalKit
import SwiftUI

/// A Metal-backed geometry layer. Grid, labels, points and interaction chrome
/// stay in the SwiftUI canvases above and below this view; fills, paths,
/// traces and ticks are drawn here with one triangle pipeline.
struct MetalCanvas: NSViewRepresentable {
    let model: SketchModel

    static let isSupported: Bool = MTLCreateSystemDefaultDevice() != nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor

        if let device = view.device,
           let renderer = MetalSceneRenderer(device: device, pixelFormat: view.colorPixelFormat) {
            view.delegate = renderer
            context.coordinator.renderer = renderer
        }
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else {
            return
        }
        renderer.update(model: model, size: view.bounds.size)
        view.setNeedsDisplay(view.bounds)
    }

    final class Coordinator {
        var renderer: MetalSceneRenderer?
    }
}

/// Six floats per vertex keep the Swift and Metal layouts identical.
struct MetalVertex {
    var x: Float
    var y: Float
    var r: Float
    var g: Float
    var b: Float
    var a: Float
}

final class MetalSceneRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var vertices: [MetalVertex] = []

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        guard let queue = device.makeCommandQueue() else {
            return nil
        }
        let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct VIn {
            float x; float y; float r; float g; float b; float a;
        };
        struct VOut {
            float4 position [[position]];
            float4 color;
        };
        vertex VOut vmain(const device VIn* vertices [[buffer(0)]], uint vid [[vertex_id]]) {
            VIn v = vertices[vid];
            VOut o;
            o.position = float4(v.x, v.y, 0.0, 1.0);
            o.color = float4(v.r, v.g, v.b, v.a);
            return o;
        }
        fragment float4 fmain(VOut in [[stage_in]]) {
            return in.color;
        }
        """
        guard let library = try? device.makeLibrary(source: shader, options: nil),
              let vertexFunction = library.makeFunction(name: "vmain"),
              let fragmentFunction = library.makeFunction(name: "fmain") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = pixelFormat
        attachment?.isBlendingEnabled = true
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.sourceAlphaBlendFactor = .sourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        super.init()
    }

    func update(model: SketchModel, size: CGSize) {
        guard size.width > 1, size.height > 1 else {
            vertices.removeAll()
            return
        }
        var builder = MetalSceneBuilder(model: model, size: size)
        vertices = builder.build()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.setRenderPipelineState(pipeline)
        if !vertices.isEmpty {
            let length = vertices.count * MemoryLayout<MetalVertex>.stride
            var buffer: MTLBuffer?
            vertices.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else {
                    return
                }
                buffer = device.makeBuffer(bytes: base, length: length,
                                           options: .storageModeShared)
            }
            if let buffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0,
                                       vertexCount: vertices.count)
            }
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

private struct MetalSceneBuilder {
    let model: SketchModel
    let size: CGSize
    let rect: WorldRect
    private var vertices: [MetalVertex] = []

    init(model: SketchModel, size: CGSize) {
        self.model = model
        self.size = size
        self.rect = model.visibleRect(size: size)
    }

    mutating func build() -> [MetalVertex] {
        var evaluator = model.evaluator()
        let ordered = model.objects.sorted { $0.order < $1.order }

        for (id, points) in model.tracePaths where points.count > 1 {
            guard let object = model.objectByID(id), object.visible else {
                continue
            }
            appendPolyline(points.map(screen), color: object.style.color,
                           width: 1.1, alpha: 0.5)
        }

        for object in ordered where object.visible {
            let result = evaluator.evaluate(object.id)
            if let fill = result.fill {
                appendFill(fill, style: object.style)
            } else if let path = result.path {
                appendFill(path, style: object.style)
            }
        }

        for object in ordered where object.visible {
            guard let path = evaluator.evaluate(object.id).path else {
                continue
            }
            let selected = model.isSelected(object.id)
            if selected {
                appendPath(path, color: .accent, width: object.style.lineWidth + 5,
                           dash: [], alpha: 0.22, ticks: 0)
            }
            appendPath(path,
                       color: selected ? .accent : object.style.color,
                       width: object.style.lineWidth + (selected ? 1.2 : 0),
                       dash: dashPattern(object.style),
                       alpha: 1,
                       ticks: object.style.tickCount)
        }
        return vertices
    }

    private func dashPattern(_ style: ObjectStyle) -> [CGFloat] {
        switch style.dash {
        case .solid:
            return []
        case .dashed:
            return [7, 4]
        case .dotted:
            return [1.2, 3.5]
        }
    }

    private func screen(_ p: Vec2) -> CGPoint {
        model.screenPoint(p, size: size)
    }

    private mutating func appendPath(_ path: EvalPath, color: RGBA, width: Double,
                                     dash: [CGFloat], alpha: Double, ticks: Int) {
        switch path {
        case .segment(let a, let b):
            let pa = screen(a)
            let pb = screen(b)
            appendPolyline([pa, pb], color: color, width: width, alpha: alpha, dash: dash)
            if ticks > 0, alpha > 0.9 {
                appendTicks(pa, pb, count: ticks, color: color)
            }

        case .ray(let a, let b):
            let direction = (b - a).normalized()
            let end = a + direction * max(rect.width, rect.height) * 3
            if let (ca, cb) = clipLine(a, end, to: rect) {
                appendPolyline([screen(ca), screen(cb)], color: color, width: width,
                               alpha: alpha, dash: dash)
            }

        case .line(let a, let b):
            let direction = (b - a).normalized()
            let far = max(rect.width, rect.height) * 4
            if let (ca, cb) = clipLine(a - direction * far, b + direction * far, to: rect) {
                appendPolyline([screen(ca), screen(cb)], color: color, width: width,
                               alpha: alpha, dash: dash)
            }

        case .circle(let center, let radius):
            guard radius.isFinite, radius > 0 else {
                return
            }
            let points = (0...96).map { index -> CGPoint in
                let angle = Double(index) / 96 * 2 * .pi
                return screen(center + Vec2(cos(angle), sin(angle)) * radius)
            }
            appendPolyline(points, color: color, width: width, alpha: alpha,
                           dash: dash, closed: true)

        case .arc(let center, let radius, let start, let sweep):
            guard radius.isFinite, radius > 0 else {
                return
            }
            let steps = max(8, Int(abs(sweep) / (2 * .pi) * 96))
            let points = (0...steps).map { index -> CGPoint in
                let angle = start + sweep * Double(index) / Double(steps)
                return screen(center + Vec2(cos(angle), sin(angle)) * radius)
            }
            appendPolyline(points, color: color, width: width, alpha: alpha, dash: dash)

        case .polygon(let points):
            appendPolyline(points.map(screen), color: color, width: width, alpha: alpha,
                           dash: dash, closed: true)

        case .polyline(let points):
            appendPolyline(points.map(screen), color: color, width: width, alpha: alpha,
                           dash: dash)

        case .functionPlot(let expression):
            appendFunction(expression, color: color, width: width, alpha: alpha, dash: dash)
        }
    }

    private mutating func appendFunction(_ expression: String, color: RGBA, width: Double,
                                         alpha: Double, dash: [CGFloat]) {
        guard var parser = Expression(expression) else {
            return
        }
        parser.setAngleUnit(model.settings.angleUnit)
        let steps = 400
        var run: [CGPoint] = []
        for index in 0...steps {
            let x = rect.minX + (rect.maxX - rect.minX) * Double(index) / Double(steps)
            guard let y = parser.evaluate(x: x), y.isFinite, abs(y) < 1e7 else {
                if run.count > 1 {
                    appendPolyline(run, color: color, width: width, alpha: alpha, dash: dash)
                }
                run.removeAll()
                continue
            }
            run.append(screen(Vec2(x, y)))
        }
        if run.count > 1 {
            appendPolyline(run, color: color, width: width, alpha: alpha, dash: dash)
        }
    }

    private mutating func appendFill(_ path: EvalPath, style: ObjectStyle) {
        switch path {
        case .polygon(let points):
            appendPolygon(points.map(screen), color: style.color,
                          alpha: style.fillOpacity)
        case .circle(let center, let radius):
            let p = screen(center)
            let r = radius * model.settings.scale
            guard r.isFinite, r > 0, r < 200_000 else {
                return
            }
            appendCircleFill(center: p, radius: r, color: style.color,
                             alpha: style.fillOpacity * 0.7)
        default:
            break
        }
    }

    private mutating func appendPolyline(_ points: [CGPoint], color: RGBA, width: Double,
                                         alpha: Double = 1, dash: [CGFloat] = [],
                                         closed: Bool = false) {
        guard points.count > 1, width > 0 else {
            return
        }
        var points = points
        if closed, let first = points.first {
            points.append(first)
        }
        if dash.isEmpty {
            for index in 0..<(points.count - 1) {
                appendLine(points[index], points[index + 1], color: color,
                           width: width, alpha: alpha)
            }
            return
        }
        var patternIndex = 0
        var remaining = dash[0]
        var drawing = true
        for index in 0..<(points.count - 1) {
            var start = points[index]
            let end = points[index + 1]
            var length = hypot(end.x - start.x, end.y - start.y)
            guard length > 0.0001 else {
                continue
            }
            let ux = (end.x - start.x) / length
            let uy = (end.y - start.y) / length
            while length > 0.0001 {
                let step = min(length, remaining)
                let next = CGPoint(x: start.x + ux * step, y: start.y + uy * step)
                if drawing {
                    appendLine(start, next, color: color, width: width, alpha: alpha)
                }
                length -= step
                remaining -= step
                start = next
                if remaining <= 0.0001 {
                    patternIndex = (patternIndex + 1) % dash.count
                    remaining = dash[patternIndex]
                    drawing.toggle()
                }
            }
        }
    }

    private mutating func appendLine(_ a: CGPoint, _ b: CGPoint, color: RGBA,
                                     width: Double, alpha: Double) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.01 else {
            return
        }
        let nx = -dy / length * CGFloat(width) / 2
        let ny = dx / length * CGFloat(width) / 2
        let p1 = CGPoint(x: a.x + nx, y: a.y + ny)
        let p2 = CGPoint(x: a.x - nx, y: a.y - ny)
        let p3 = CGPoint(x: b.x + nx, y: b.y + ny)
        let p4 = CGPoint(x: b.x - nx, y: b.y - ny)
        appendTriangle(p1, p2, p3, color: color, alpha: alpha)
        appendTriangle(p2, p4, p3, color: color, alpha: alpha)
    }

    private mutating func appendTicks(_ a: CGPoint, _ b: CGPoint, count: Int, color: RGBA) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 1 else {
            return
        }
        let ux = dx / length
        let uy = dy / length
        let half = min(5, max(3, length / 12))
        for index in 0..<max(0, min(count, 3)) {
            let t = CGFloat(index + 1) / CGFloat(count + 1)
            let center = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
            appendLine(CGPoint(x: center.x - uy * half, y: center.y + ux * half),
                       CGPoint(x: center.x + uy * half, y: center.y - ux * half),
                       color: color, width: 1.2, alpha: 1)
        }
    }

    private mutating func appendCircleFill(center: CGPoint, radius: CGFloat,
                                           color: RGBA, alpha: Double) {
        let steps = 64
        for index in 0..<steps {
            let a1 = Double(index) / Double(steps) * 2 * .pi
            let a2 = Double(index + 1) / Double(steps) * 2 * .pi
            let p1 = CGPoint(x: center.x + CGFloat(cos(a1)) * radius,
                             y: center.y + CGFloat(sin(a1)) * radius)
            let p2 = CGPoint(x: center.x + CGFloat(cos(a2)) * radius,
                             y: center.y + CGFloat(sin(a2)) * radius)
            appendTriangle(center, p1, p2, color: color, alpha: alpha)
        }
    }

    private mutating func appendPolygon(_ points: [CGPoint], color: RGBA, alpha: Double) {
        guard points.count >= 3 else {
            return
        }
        for triangle in triangulate(points) {
            appendTriangle(triangle.0, triangle.1, triangle.2, color: color, alpha: alpha)
        }
    }

    private func triangulate(_ input: [CGPoint]) -> [(CGPoint, CGPoint, CGPoint)] {
        var points = input
        let area = signedArea(points)
        if area < 0 {
            points.reverse()
        }
        var indices = Array(points.indices)
        var triangles: [(CGPoint, CGPoint, CGPoint)] = []
        var guardCount = 0
        while indices.count > 3, guardCount < points.count * points.count {
            guardCount += 1
            var clipped = false
            for offset in indices.indices {
                let i0 = indices[(offset + indices.count - 1) % indices.count]
                let i1 = indices[offset]
                let i2 = indices[(offset + 1) % indices.count]
                let a = points[i0]
                let b = points[i1]
                let c = points[i2]
                guard cross(a, b, c) > 0 else {
                    continue
                }
                let contains = indices.contains { index in
                    index != i0 && index != i1 && index != i2
                        && pointInTriangle(points[index], a, b, c)
                }
                if contains {
                    continue
                }
                triangles.append((a, b, c))
                indices.remove(at: offset)
                clipped = true
                break
            }
            if !clipped {
                break
            }
        }
        if indices.count == 3 {
            triangles.append((points[indices[0]], points[indices[1]], points[indices[2]]))
        } else if triangles.isEmpty {
            for index in 1..<(points.count - 1) {
                triangles.append((points[0], points[index], points[index + 1]))
            }
        }
        return triangles
    }

    private func signedArea(_ points: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return sum / 2
    }

    private func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private func pointInTriangle(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let d1 = cross(a, b, p)
        let d2 = cross(b, c, p)
        let d3 = cross(c, a, p)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }

    private mutating func appendTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint,
                                         color: RGBA, alpha: Double) {
        appendVertex(a, color: color, alpha: alpha)
        appendVertex(b, color: color, alpha: alpha)
        appendVertex(c, color: color, alpha: alpha)
    }

    private mutating func appendVertex(_ p: CGPoint, color: RGBA, alpha: Double) {
        let x = Float(p.x / size.width * 2 - 1)
        let y = Float(1 - p.y / size.height * 2)
        vertices.append(MetalVertex(x: x, y: y,
                                    r: Float(color.r),
                                    g: Float(color.g),
                                    b: Float(color.b),
                                    a: Float(color.a * alpha)))
    }
}
