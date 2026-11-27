import Foundation

extension GeometryEval {

    /// Samples a driven object while its driver sweeps the driver's whole
    /// path. Sketchpad calls this a locus; a point on an open path uses the
    /// path parameter from 0 to 1, a point on a circle a full counter-clockwise
    /// turn, matching the animation direction rule.
    mutating func locusCurve(driver: UUID, target: UUID) -> [Vec2]? {
        guard let driverObject = objects[driver],
              case .pointOnPath(let pathID, _) = driverObject.kind,
              let driverPath = path(pathID),
              let targetObject = objects[target] else {
            return nil
        }
        if case .locus = targetObject.kind {
            return nil
        }
        let closed: Bool
        if case .circle = driverPath {
            closed = true
        } else {
            closed = false
        }
        var base = Array(objects.values)
        guard let index = base.firstIndex(where: { $0.id == driver }) else {
            return nil
        }
        var points: [Vec2] = []
        for step in 0...Metrics.locusSamples {
            let unit = Double(step) / Double(Metrics.locusSamples)
            let param = closed ? unit * 2 * .pi : unit
            base[index].kind = .pointOnPath(path: pathID, param: param)
            var sample = GeometryEval(objects: base, settings: settings)
            guard let p = sample.evaluate(target).point else {
                continue
            }
            let last = points.last?.distance(to: p) ?? .infinity
            if last > Metrics.locusDedupTolerance {
                points.append(p)
            }
        }
        return points.count > 1 ? points : nil
    }
}
