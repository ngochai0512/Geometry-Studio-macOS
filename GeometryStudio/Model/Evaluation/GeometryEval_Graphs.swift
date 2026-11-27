import Foundation

extension GeometryEval {

    mutating func graphResult(_ feature: GraphFeature, object: SketchObject) -> EvalResult {
        var result = EvalResult()
        switch feature {
        case .derivative(let source):
            let points = sampleFunction(source, from: -10, to: 10, samples: 200, derivative: true)
            if points.count > 1 {
                result.path = .polyline(points)
            }

        case .integral(let source, let from, let to):
            let points = sampleFunction(source, from: min(from, to), to: max(from, to),
                                        samples: 160, derivative: false)
            if points.count > 1 {
                var polygon = [Vec2(points[0].x, 0)]
                polygon.append(contentsOf: points)
                polygon.append(Vec2(points[points.count - 1].x, 0))
                result.fill = .polygon(polygon)
                result.path = .polyline(points)
            }

        case .tangent(let source, let x):
            guard let y = expressionValue(source, x: x) else {
                return result
            }
            let h = 1e-4
            let left = expressionValue(source, x: x - h) ?? y
            let right = expressionValue(source, x: x + h) ?? y
            let slope = (right - left) / (2 * h)
            result.path = .line(Vec2(x, y), Vec2(x + 1, y + slope))
            result.anchor = Vec2(x, y)
            result.text = "tangent at \(formatNumber(x, precision: settings.precision))"

        case .table(let source, let from, let to, let step):
            guard abs(step) > Metrics.epsilon else {
                return result
            }
            let lower = min(from, to)
            let upper = max(from, to)
            var lines = ["x\tf(x)"]
            var x = lower
            var rows = 0
            while x <= upper + 1e-9 && rows < 200 {
                let text = expressionValue(source, x: x)
                    .map { formatNumber($0, precision: settings.precision) } ?? "—"
                lines.append("\(formatNumber(x, precision: settings.precision))\t\(text)")
                x += abs(step)
                rows += 1
            }
            result.text = lines.joined(separator: "\n")
            result.anchor = object.position ?? Vec2(lower, 0)
        }
        return result
    }

    func expressionValue(_ source: String, x: Double) -> Double? {
        guard var expression = Expression(source) else {
            return nil
        }
        expression.setAngleUnit(settings.angleUnit)
        return expression.evaluate(x: x)
    }

    func sampleFunction(_ source: String, from: Double, to: Double,
                                samples: Int, derivative: Bool) -> [Vec2] {
        guard var expression = Expression(source) else {
            return []
        }
        expression.setAngleUnit(settings.angleUnit)
        let count = max(2, samples)
        var points: [Vec2] = []
        for index in 0...count {
            let x = from + (to - from) * Double(index) / Double(count)
            if derivative {
                let h = 1e-4
                guard let left = expression.evaluate(x: x - h),
                      let right = expression.evaluate(x: x + h) else {
                    continue
                }
                points.append(Vec2(x, (right - left) / (2 * h)))
            } else if let y = expression.evaluate(x: x) {
                points.append(Vec2(x, y))
            }
        }
        return points
    }
}
