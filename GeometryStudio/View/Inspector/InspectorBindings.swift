import SwiftUI
import AppKit

// Model plumbing for the inspector: kind predicates, display text, selection
// bindings and the shared undo-checkpointed style mutations.

extension InspectorView {

    // MARK: - Predicates and descriptions















    // MARK: - Object bindings













    // MARK: - Selection binding

    /// The object list selects through a set; the model keeps click order so
    /// constructions that read the first picked object still see it. Stay on
    /// the sketch tab: switching tabs while the list is applying a selection
    /// tears down the list mid-update and can crash SwiftUI.
    var objectSelection: Binding<Set<UUID>> {
        Binding(
            get: { Set(model.selection) },
            set: { newValue in
                let kept = model.selection.filter { newValue.contains($0) }
                let added = model.objects.map(\.id).filter { newValue.contains($0) && !kept.contains($0) }
                model.selection = kept + added
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

    // MARK: - Numeric geometry

    var displayUnit: Double {
        max(model.settings.lengthUnit.perUnit, 1e-6)
    }










}
