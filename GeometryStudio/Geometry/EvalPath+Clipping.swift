import Foundation

private typealias Tolerance = EvalPathTolerance

// MARK: - Clipping

func clipLine(_ a: Vec2, _ b: Vec2, to rect: WorldRect) -> (Vec2, Vec2)? {
    // Liang–Barsky, used to draw infinite lines and rays inside the viewport.
    var lower = 0.0
    var upper = 1.0
    let delta = b - a
    let normals = [-delta.x, delta.x, -delta.y, delta.y]
    let distances = [
        a.x - rect.minX,
        rect.maxX - a.x,
        a.y - rect.minY,
        rect.maxY - a.y
    ]
    for index in 0..<4 {
        let normal = normals[index]
        let distance = distances[index]
        if abs(normal) < Tolerance.zero {
            if distance < 0 {
                return nil
            }
        } else {
            let ratio = distance / normal
            if normal < 0 {
                if ratio > upper {
                    return nil
                }
                if ratio > lower {
                    lower = ratio
                }
            } else {
                if ratio < lower {
                    return nil
                }
                if ratio < upper {
                    upper = ratio
                }
            }
        }
    }
    return (a.lerp(to: b, lower), a.lerp(to: b, upper))
}
