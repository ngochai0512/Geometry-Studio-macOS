import SwiftUI
import AppKit

extension InspectorView {

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
}
