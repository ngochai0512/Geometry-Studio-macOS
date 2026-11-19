import SwiftUI
import AppKit

// Model plumbing for the inspector: kind predicates, display text, selection
// bindings and the shared undo-checkpointed style mutations.

extension InspectorView {

    // MARK: - Predicates and descriptions

    func needsLabel(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .freePoint, .pointOnPath, .midpoint, .intersection, .caption, .angle: return true
        default: return false
        }
    }

    func isMeasurement(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .angle: return true
        default: return false
        }
    }

    func isLineObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .segment, .ray, .line, .perpendicular, .parallel, .angleBisector: return true
        default: return false
        }
    }

    func isRegionObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .circle, .polygon: return true
        default: return false
        }
    }

    func isMeasureObject(_ object: SketchObject) -> Bool {
        switch object.kind {
        case .measurement, .calculation, .caption, .angle, .functionPlot: return true
        default: return false
        }
    }

    func typeDescription(_ object: SketchObject) -> String {
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

    func showLabelBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.objectByID(id)?.showLabel ?? true },
            set: { value in
                guard let i = model.index(of: id) else {
                    return
                }
                model.checkpoint(value ? "Show Label" : "Hide Label")
                model.objects[i].showLabel = value
            }
        )
    }

    func visibleBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.objectByID(id)?.visible ?? true },
            set: { value in
                guard let i = model.index(of: id) else {
                    return
                }
                model.checkpoint(value ? "Show Object" : "Hide Object")
                model.objects[i].visible = value
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
