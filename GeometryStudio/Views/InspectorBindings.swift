import SwiftUI
import AppKit

// Model plumbing for the inspector: kind predicates, display text, selection
// bindings and the shared undo-checkpointed style mutations.

extension InspectorView {

    // MARK: - Predicates and descriptions

    func needsLabel(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection, .angle, .parameter:
            return true
        case .graph(.table):
            return true
        default:
            return false
        }
    }

    func isMeasurement(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .angle:
            return true
        default:
            return false
        }
    }

    func isLineObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector,
             .construction, .vector:
            return true
        case .graph(.derivative), .graph(.tangent):
            return true
        default:
            return false
        }
    }

    func isArcObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .arcOnCircle, .arcThroughPoints:
            return true
        default:
            return false
        }
    }

    func isRegionObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .circle, .circleRadius, .polygon:
            return true
        case .graph(.integral):
            return true
        default:
            return false
        }
    }

    func isMeasureObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .caption, .angle, .functionPlot:
            return true
        default:
            return false
        }
    }

    func isConstructionObject(_ object: SketchObject) -> Bool {
        if case .construction = object.kind {
            return true
        }
        return false
    }

    func isParameterObject(_ object: SketchObject) -> Bool {
        if case .parameter = object.kind {
            return true
        }
        return false
    }

    func isCoordinateObject(_ object: SketchObject) -> Bool {
        if case .coordinateSystem = object.kind {
            return true
        }
        return false
    }

    func isGraphObject(_ object: SketchObject) -> Bool {
        if case .graph = object.kind {
            return true
        }
        return false
    }

    func isVectorObject(_ object: SketchObject) -> Bool {
        if case .vector = object.kind {
            return true
        }
        return false
    }

    func isTransformedObject(_ object: SketchObject) -> Bool {
        if case .transformed = object.kind {
            return true
        }
        return false
    }

    func isLocusObject(_ object: SketchObject) -> Bool {
        if case .locus = object.kind {
            return true
        }
        return false
    }

    func typeDescription(_ object: SketchObject) -> String {
        switch object.kind {
        case .freePoint:
            return "Free point"
        case .pointOnPath:
            return "Point on an object"
        case .midpoint:
            return "Constructed midpoint"
        case .intersection:
            return "Constructed intersection"
        case .segment:
            return "Segment"
        case .ray:
            return "Ray"
        case .line:
            return "Line"
        case .perpendicular:
            return "Perpendicular line"
        case .parallel:
            return "Parallel line"
        case .angleBisector:
            return "Angle bisector"
        case .circle:
            return "Circle"
        case .circleRadius:
            return "Circle by radius"
        case .arcOnCircle:
            return "Arc on a circle"
        case .arcThroughPoints:
            return "Arc through three points"
        case .polygon:
            return "Polygon interior"
        case .angle:
            return "Angle marker"
        case .measurement(let kind, _):
            return "\(kind.title) measurement"
        case .calculation:
            return "Calculation"
        case .caption:
            return "Caption"
        case .functionPlot:
            return "Function plot"
        case .transformed(_, let spec):
            return "\(spec.kind.title) image"
        case .locus:
            return "Locus"
        case .parameter:
            return "Parameter"
        case .construction(let kind):
            switch kind {
            case .perpendicularBisector:
                return "Perpendicular bisector"
            case .tangentPointToCircle:
                return "Tangent from a point"
            case .tangentCircleToCircle:
                return "Common tangent"
            case .radicalAxis:
                return "Radical axis"
            }
        case .vector(let kind):
            switch kind {
            case .fromPoints:
                return "Vector"
            case .sum(_, _, let subtract):
                return subtract ? "Vector difference" : "Vector sum"
            }
        case .coordinateSystem(let kind, _, _, _):
            return "\(kind.title) coordinate system"
        case .graph(let feature):
            switch feature {
            case .derivative:
                return "Derivative plot"
            case .integral:
                return "Integral shading"
            case .tangent:
                return "Tangent line"
            case .table:
                return "Value table"
            }
        }
    }

    // MARK: - Object bindings

    func labelBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { model.objectByID(id)?.label ?? "" },
            set: { value in
                guard let i = model.index(of: id) else {
                    return
                }
                model.checkpoint("Edit Label", coalescing: "label-\(id)")
                model.objects[i].label = value
            }
        )
    }

    func parameterValueBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                if let object = model.objectByID(id), case .parameter(let value, _, _) = object.kind {
                    return value
                }
                return 0
            },
            set: { value in
                guard let i = model.index(of: id),
                      case .parameter(_, let minimum, let maximum) = model.objects[i].kind else {
                    return
                }
                model.checkpoint("Change Parameter", coalescing: "parameter-\(id)")
                model.objects[i].kind = .parameter(value: min(max(value, minimum), maximum),
                                                   minimum: minimum, maximum: maximum)
            }
        )
    }

    func parameterMinimumBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                if let object = model.objectByID(id), case .parameter(_, let minimum, _) = object.kind {
                    return minimum
                }
                return 0
            },
            set: { value in
                guard let i = model.index(of: id),
                      case .parameter(let current, _, let maximum) = model.objects[i].kind else {
                    return
                }
                model.checkpoint("Change Parameter Range")
                let minimum = min(value, maximum - 1e-6)
                model.objects[i].kind = .parameter(value: max(current, minimum),
                                                   minimum: minimum, maximum: maximum)
            }
        )
    }

    func parameterMaximumBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                if let object = model.objectByID(id), case .parameter(_, _, let maximum) = object.kind {
                    return maximum
                }
                return 10
            },
            set: { value in
                guard let i = model.index(of: id),
                      case .parameter(let current, let minimum, _) = model.objects[i].kind else {
                    return
                }
                model.checkpoint("Change Parameter Range")
                let maximum = max(value, minimum + 1e-6)
                model.objects[i].kind = .parameter(value: min(current, maximum),
                                                   minimum: minimum, maximum: maximum)
            }
        )
    }

    func coordinateKindBinding(_ id: UUID) -> Binding<CoordinateKind> {
        Binding(
            get: {
                if let object = model.objectByID(id),
                   case .coordinateSystem(let kind, _, _, _) = object.kind {
                    return kind
                }
                return .cartesian
            },
            set: { value in
                guard let i = model.index(of: id),
                      case .coordinateSystem(_, let origin, let step, let unit) = model.objects[i].kind else {
                    return
                }
                model.checkpoint("Change Coordinate System")
                model.objects[i].kind = .coordinateSystem(kind: value, origin: origin,
                                                          step: step, unit: unit)
            }
        )
    }

    func coordinateUnitBinding(_ id: UUID) -> Binding<LengthUnit> {
        Binding(
            get: {
                if let object = model.objectByID(id),
                   case .coordinateSystem(_, _, _, let unit) = object.kind {
                    return unit
                }
                return .inches
            },
            set: { value in
                guard let i = model.index(of: id),
                      case .coordinateSystem(let kind, let origin, let step, _) = model.objects[i].kind else {
                    return
                }
                model.checkpoint("Change Coordinate Unit")
                model.objects[i].kind = .coordinateSystem(kind: kind, origin: origin,
                                                          step: step, unit: value)
            }
        )
    }

    func coordinateStepBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                if let object = model.objectByID(id),
                   case .coordinateSystem(_, _, let step, let unit) = object.kind {
                    return step / max(unit.perUnit, 1e-6)
                }
                return 1
            },
            set: { value in
                guard let i = model.index(of: id),
                      case .coordinateSystem(let kind, let origin, _, let unit) = model.objects[i].kind,
                      value.isFinite, value > 0 else {
                    return
                }
                model.checkpoint("Change Coordinate Step", coalescing: "coordinate-step-\(id)")
                model.objects[i].kind = .coordinateSystem(kind: kind, origin: origin,
                                                          step: value * unit.perUnit, unit: unit)
            }
        )
    }

    func graphTangentXBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                if let object = model.objectByID(id),
                   case .graph(.tangent(_, let x)) = object.kind {
                    return x
                }
                return 0
            },
            set: { value in
                guard let i = model.index(of: id),
                      case .graph(.tangent(let source, _)) = model.objects[i].kind,
                      value.isFinite else {
                    return
                }
                model.checkpoint("Change Tangent", coalescing: "graph-\(id)")
                model.objects[i].kind = .graph(.tangent(source, x: value))
            }
        )
    }

    func graphFromBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                guard let object = model.objectByID(id) else {
                    return 0
                }
                switch object.kind {
                case .graph(.integral(_, let from, _)):
                    return from
                case .graph(.table(_, let from, _, _)):
                    return from
                default:
                    return 0
                }
            },
            set: { value in
                guard let i = model.index(of: id), value.isFinite else {
                    return
                }
                switch model.objects[i].kind {
                case .graph(.integral(let source, _, let to)):
                    model.checkpoint("Change Integral Range", coalescing: "graph-\(id)")
                    model.objects[i].kind = .graph(.integral(source, from: value, to: to))
                case .graph(.table(let source, _, let to, let step)):
                    model.checkpoint("Change Table Range", coalescing: "graph-\(id)")
                    model.objects[i].kind = .graph(.table(source, from: value, to: to, step: step))
                default:
                    break
                }
            }
        )
    }

    func graphToBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                guard let object = model.objectByID(id) else {
                    return 0
                }
                switch object.kind {
                case .graph(.integral(_, _, let to)):
                    return to
                case .graph(.table(_, _, let to, _)):
                    return to
                default:
                    return 0
                }
            },
            set: { value in
                guard let i = model.index(of: id), value.isFinite else {
                    return
                }
                switch model.objects[i].kind {
                case .graph(.integral(let source, let from, _)):
                    model.checkpoint("Change Integral Range", coalescing: "graph-\(id)")
                    model.objects[i].kind = .graph(.integral(source, from: from, to: value))
                case .graph(.table(let source, let from, _, let step)):
                    model.checkpoint("Change Table Range", coalescing: "graph-\(id)")
                    model.objects[i].kind = .graph(.table(source, from: from, to: value, step: step))
                default:
                    break
                }
            }
        )
    }

    func graphStepBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                if let object = model.objectByID(id),
                   case .graph(.table(_, _, _, let step)) = object.kind {
                    return step
                }
                return 1
            },
            set: { value in
                guard let i = model.index(of: id),
                      case .graph(.table(let source, let from, let to, _)) = model.objects[i].kind,
                      value.isFinite, abs(value) > 1e-6 else {
                    return
                }
                model.checkpoint("Change Table Step", coalescing: "graph-\(id)")
                model.objects[i].kind = .graph(.table(source, from: from, to: to, step: value))
            }
        )
    }

    func captionBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                if let object = model.objectByID(id), case .caption(let text) = object.kind {
                    return text
                }
                return ""
            },
            set: { value in
                guard let i = model.index(of: id) else {
                    return
                }
                if case .caption = model.objects[i].kind {
                    model.checkpoint("Edit Text", coalescing: "caption-\(id)")
                    model.objects[i].kind = .caption(value)
                }
            }
        )
    }

    // MARK: - Selection binding

    /// The object list selects through a set; the model keeps click order so
    /// constructions that read the first picked object still see it.
    var objectSelection: Binding<Set<UUID>> {
        Binding(
            get: { Set(model.selection) },
            set: { newValue in
                let kept = model.selection.filter { newValue.contains($0) }
                let added = model.objects.map(\.id).filter { newValue.contains($0) && !kept.contains($0) }
                model.selection = kept + added
                if !newValue.isEmpty {
                    tab = .object
                }
            }
        )
    }

    // MARK: - Style bindings

    var lineWidthBinding: Binding<Double> {
        Binding(
            get: { model.selectedObjects.first?.style.lineWidth ?? 1.5 },
            set: { value in
                applyToSelection("Change Line Width", coalescing: "line-width") {
                    $0.style.lineWidth = value
                }
            }
        )
    }

    var dashBinding: Binding<DashStyle> {
        Binding(
            get: { model.selectedObjects.first?.style.dash ?? .solid },
            set: { value in
                applyToSelection("Change Dash") {
                    $0.style.dash = value
                }
            }
        )
    }

    var pointShapeBinding: Binding<PointShape> {
        Binding(
            get: { model.selectedObjects.first?.style.pointShape ?? .filled },
            set: { value in
                applyToSelection("Change Point Shape") {
                    $0.style.pointShape = value
                }
            }
        )
    }

    var pointSizeBinding: Binding<Double> {
        Binding(
            get: { model.selectedObjects.first?.style.pointSize ?? 5.5 },
            set: { value in
                applyToSelection("Change Point Size") {
                    $0.style.pointSize = value
                }
            }
        )
    }

    var tickCountBinding: Binding<Int> {
        Binding(
            get: { model.selectedObjects.first?.style.tickCount ?? 0 },
            set: { value in
                applyToSelection("Change Tick Marks") {
                    $0.style.tickCount = min(max(value, 0), 3)
                }
            }
        )
    }

    var angleMarkerBinding: Binding<AngleMarkerStyle> {
        Binding(
            get: { model.selectedObjects.first?.style.angleMarker ?? .arc },
            set: { value in
                applyToSelection("Change Angle Marker") {
                    $0.style.angleMarker = value
                }
            }
        )
    }

    var fillBinding: Binding<Double> {
        Binding(
            get: { model.selectedObjects.first?.style.fillOpacity ?? 0.1 },
            set: { value in
                applyToSelection("Change Fill", coalescing: "fill") {
                    $0.style.fillOpacity = value
                }
            }
        )
    }

    var arcFillBinding: Binding<ArcFill> {
        Binding(
            get: { model.selectedObjects.first?.arcFill ?? .none },
            set: { value in
                applyToSelection("Change Arc Fill") {
                    $0.arcFill = value
                }
            }
        )
    }

    var canvasBackgroundBinding: Binding<Color> {
        Binding(
            get: { model.settings.backgroundColor.color },
            set: { newValue in
                let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .white
                model.settings.backgroundColor = RGBA(Double(ns.redComponent),
                                                      Double(ns.greenComponent),
                                                      Double(ns.blueComponent),
                                                      Double(ns.alphaComponent))
            }
        )
    }

    var colorBinding: Binding<Color> {
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

    var anySelectedIsRegion: Bool {
        model.selectedObjects.contains { isRegionObject($0) }
    }

    var anySelectedIsArc: Bool {
        model.selectedObjects.contains { isArcObject($0) }
    }

    var anySelectedIsSegment: Bool {
        model.selectedObjects.contains {
            if case .segment = $0.kind {
                return true
            }
            return false
        }
    }

    var anySelectedIsAngle: Bool {
        model.selectedObjects.contains {
            if case .angle = $0.kind {
                return true
            }
            return false
        }
    }

    // MARK: - Mutations

    func applyToSelection(_ name: String, coalescing key: String? = nil,
                          _ change: (inout SketchObject) -> Void) {
        guard !model.selection.isEmpty else {
            return
        }
        model.checkpoint(name, coalescing: key)
        for id in model.selection {
            if let i = model.index(of: id) {
                change(&model.objects[i])
            }
        }
    }
}
