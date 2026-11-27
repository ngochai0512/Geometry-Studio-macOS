import Foundation

enum VectorKind: Codable, Hashable {
    case fromPoints(from: UUID, to: UUID)
    case sum(a: UUID, b: UUID, subtract: Bool)
}
