import SwiftUI
import AppKit

extension InspectorView {

    func pointXBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                guard let object = model.objectByID(id), case .freePoint = object.kind,
                      let position = object.position else {
                    return 0
                }
                return position.x / displayUnit
            },
            set: { value in
                guard value.isFinite,
                      let object = model.objectByID(id), case .freePoint = object.kind,
                      let position = object.position else {
                    return
                }
                model.moveFreePoint(id, to: Vec2(value * displayUnit, position.y),
                                    coalescing: "point-x-\(id)")
            }
        )
    }

    func pointYBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                guard let object = model.objectByID(id), case .freePoint = object.kind,
                      let position = object.position else {
                    return 0
                }
                return position.y / displayUnit
            },
            set: { value in
                guard value.isFinite,
                      let object = model.objectByID(id), case .freePoint = object.kind,
                      let position = object.position else {
                    return
                }
                model.moveFreePoint(id, to: Vec2(position.x, value * displayUnit),
                                    coalescing: "point-y-\(id)")
            }
        )
    }

    func circleRadiusBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                guard let object = model.objectByID(id),
                      case .circleRadius(_, let radius) = object.kind else {
                    return 0
                }
                return radius / displayUnit
            },
            set: { value in
                guard value.isFinite, value > 0,
                      let i = model.index(of: id),
                      case .circleRadius(let center, _) = model.objects[i].kind else {
                    return
                }
                model.checkpoint("Change Radius", coalescing: "radius-\(id)")
                model.objects[i].kind = .circleRadius(center: center,
                                                      radius: value * displayUnit)
            }
        )
    }

    func segmentLengthEditable(_ id: UUID) -> Bool {
        guard let (a, b) = segmentEndpoints(id) else {
            return false
        }
        return freeEndpoint(a: a, b: b) != nil
    }

    func segmentLengthBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                guard let (a, b) = segmentEndpoints(id),
                      let pa = model.evaluated(a).point,
                      let pb = model.evaluated(b).point else {
                    return 0
                }
                return pa.distance(to: pb) / displayUnit
            },
            set: { value in
                guard value.isFinite, value > 0,
                      let (a, b) = segmentEndpoints(id),
                      let pa = model.evaluated(a).point,
                      let pb = model.evaluated(b).point,
                      let free = freeEndpoint(a: a, b: b) else {
                    return
                }
                let direction = (pb - pa).normalized()
                let target = free == b
                    ? pa + direction * (value * displayUnit)
                    : pb - direction * (value * displayUnit)
                model.moveFreePoint(free, to: target, coalescing: "segment-length-\(id)")
            }
        )
    }

    func angleEditable(_ id: UUID) -> Bool {
        guard let object = model.objectByID(id),
              case .angle(_, _, let c) = object.kind,
              let third = model.objectByID(c) else {
            return false
        }
        if case .freePoint = third.kind {
            return true
        }
        return false
    }

    func angleBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                guard let radians = angleRadians(id) else {
                    return 0
                }
                return model.settings.angleUnit == .radians ? radians : radians * 180 / .pi
            },
            set: { value in
                guard value.isFinite, value > 0,
                      let object = model.objectByID(id),
                      case .angle(let a, let vertex, let c) = object.kind,
                      let third = model.objectByID(c), case .freePoint = third.kind else {
                    return
                }
                let radians = model.settings.angleUnit == .radians ? value : value * .pi / 180
                let clamped = min(max(radians, 1e-4), .pi - 1e-4)
                var e = model.evaluator()
                guard let pa = e.point(a), let pv = e.point(vertex), let pc = e.point(c) else {
                    return
                }
                let start = atan2(pa.y - pv.y, pa.x - pv.x)
                let current = atan2(pc.y - pv.y, pc.x - pv.x)
                var delta = current - start
                while delta > .pi {
                    delta -= .pi * 2
                }
                while delta < -.pi {
                    delta += .pi * 2
                }
                let sign: Double = delta < 0 ? -1 : 1
                let angle = current + sign * (clamped - abs(delta))
                let target = pv + Vec2(cos(angle), sin(angle)) * pv.distance(to: pc)
                model.moveFreePoint(c, to: target, coalescing: "angle-\(id)")
            }
        )
    }

    func segmentEndpoints(_ id: UUID) -> (UUID, UUID)? {
        guard let object = model.objectByID(id),
              case .segment(let a, let b) = object.kind else {
            return nil
        }
        return (a, b)
    }

    func freeEndpoint(a: UUID, b: UUID) -> UUID? {
        if let object = model.objectByID(a), case .freePoint = object.kind {
            return a
        }
        if let object = model.objectByID(b), case .freePoint = object.kind {
            return b
        }
        return nil
    }

    func angleRadians(_ id: UUID) -> Double? {
        guard let object = model.objectByID(id),
              case .angle(let a, let vertex, let c) = object.kind else {
            return nil
        }
        var e = model.evaluator()
        guard let pa = e.point(a), let pv = e.point(vertex), let pc = e.point(c) else {
            return nil
        }
        var delta = atan2(pc.y - pv.y, pc.x - pv.x) - atan2(pa.y - pv.y, pa.x - pv.x)
        while delta > .pi {
            delta -= .pi * 2
        }
        while delta < -.pi {
            delta += .pi * 2
        }
        return abs(delta)
    }
}
