import Foundation
import CoreGraphics

// MARK: - Small vector type

struct Vec2: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ x: Double = 0, _ y: Double = 0) {
        self.x = x
        self.y = y
    }

    static let zero = Vec2(0, 0)

    var cg: CGPoint { CGPoint(x: x, y: y) }
    var length: Double { (x * x + y * y).squareRoot() }
    var angle: Double { atan2(y, x) }

    func distance(to other: Vec2) -> Double { (self - other).length }
    func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }
    func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }
    func normalized() -> Vec2 {
        let l = length
        return l < 1e-12 ? Vec2(0, 0) : Vec2(x / l, y / l)
    }
    func perpendicular() -> Vec2 { Vec2(-y, x) }
    func rotated(by radians: Double) -> Vec2 {
        let c = cos(radians), s = sin(radians)
        return Vec2(x * c - y * s, x * s + y * c)
    }
    func scaled(_ k: Double) -> Vec2 { Vec2(x * k, y * k) }
    func lerp(to other: Vec2, _ t: Double) -> Vec2 {
        Vec2(x + (other.x - x) * t, y + (other.y - y) * t)
    }

    static func + (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x + r.x, l.y + r.y) }
    static func - (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x - r.x, l.y - r.y) }
    static func * (l: Vec2, r: Double) -> Vec2 { Vec2(l.x * r, l.y * r) }
    static func / (l: Vec2, r: Double) -> Vec2 { Vec2(l.x / r, l.y / r) }
    static prefix func - (v: Vec2) -> Vec2 { Vec2(-v.x, -v.y) }
}

struct WorldRect: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var center: Vec2 { Vec2((minX + maxX) / 2, (minY + maxY) / 2) }
    func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }
    func inset(_ d: Double) -> WorldRect {
        WorldRect(minX: minX + d, minY: minY + d, maxX: maxX - d, maxY: maxY - d)
    }
}
