import Foundation

enum GraphFeature: Codable, Hashable {
    case derivative(String)
    case integral(String, from: Double, to: Double)
    case tangent(String, x: Double)
    case table(String, from: Double, to: Double, step: Double)
}
